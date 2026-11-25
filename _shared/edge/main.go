// vhostlab edge gateway: one listener, host/SNI/keyword routing, per-route Server header.
// Config is data (sites.json); this binary contains no site content.
package main

import (
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

type PathRule struct {
	Prefix   string `json:"prefix"`
	Upstream string `json:"upstream"`
	Rewrite  string `json:"rewrite"`   // replacement for Prefix ("" = "/")
	DropPath bool   `json:"drop_path"` // ignore the remainder: one 200 for every path
}

type HostRule struct {
	Host            string            `json:"host"`
	Upstream        string            `json:"upstream"`
	Server          string            `json:"server"`
	Status          int               `json:"status"`    // >0: answer locally, no upstream
	BodyFile        string            `json:"body_file"` // local body
	CaseInsensitive bool              `json:"case_insensitive"`
	TrailingDot     string            `json:"trailing_dot"` // "strip" (default) | "keep"
	Paths           []PathRule        `json:"paths"`
	AppHeader       map[string]string `json:"app_header"`
}

type KeywordRule struct {
	Contains    string            `json:"contains"`
	Match       string            `json:"match"` // contains (default) | suffix | prefix
	Upstream    string            `json:"upstream"`
	Server      string            `json:"server"`
	Status      int               `json:"status"`
	BodyFile    string            `json:"body_file"`
	AppHeader   map[string]string `json:"app_header"`
	IgnoreCase  *bool             `json:"ignore_case"` // default true
	StripPort   *bool             `json:"strip_port"`  // default true
	TrailingDot string            `json:"trailing_dot"`
}

type CertPair struct {
	Cert string `json:"cert"`
	Key  string `json:"key"`
}

// Silence models a front end that drops traffic instead of answering: no SNI (or
// an unexpected one) stalls the TLS handshake, an unexpected Host gets no response
// at all. Both sides must be right before anything is served.
type Silence struct {
	RequireSNI  bool     `json:"require_sni"`
	AllowSNI    []string `json:"allow_sni"`
	RequireHost bool     `json:"require_host"`
	AllowHost   []string `json:"allow_host"`
	Hold        int      `json:"hold_seconds"`
}

type Config struct {
	HTTPAddr      string              `json:"http_addr"`
	HTTPSAddr     string              `json:"https_addr"`
	CertFile      string              `json:"cert_file"`
	KeyFile       string              `json:"key_file"`
	SNI           map[string]CertPair `json:"sni"`
	DefaultServer string              `json:"default_server"`
	DefaultBody   string              `json:"default_body"`
	DefaultHost   *HostRule           `json:"default_host"`
	Sites         []HostRule          `json:"sites"`
	Keywords      []KeywordRule       `json:"keywords"`
	Silent        *Silence            `json:"silent"`
}

type route struct {
	proxy       *httputil.ReverseProxy
	server      string
	app         map[string]string
	status      int
	body        []byte
	bodyKnown   bool
	label       string
	pathPrefix  string
	pathRewrite string
	dropPath    bool
	subs        []*route // path rules of an exact host
	ci          bool     // case-insensitive paths (IIS-style site)
}

type kwRule struct {
	raw    string // lowercased needle
	match  string
	r      *route
}

type gateway struct {
	cfg      Config
	exact    map[string]*route // key: normalised host (dot policy applied by rule)
	kw       []kwRule
	def      *route
	fallback *route
	tlsConf  *tls.Config
}

var bodies = struct {
	sync.Mutex
	m map[string][]byte
}{m: map[string][]byte{}}

func loadBody(path string) ([]byte, error) {
	if path == "" {
		return nil, nil
	}
	bodies.Lock()
	defer bodies.Unlock()
	if b, ok := bodies.m[path]; ok {
		return b, nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	bodies.m[path] = b
	return b, nil
}

func makeProxy(upstream, server string, app map[string]string) (*httputil.ReverseProxy, error) {
	u, err := url.Parse(upstream)
	if err != nil || u.Host == "" {
		return nil, fmt.Errorf("bad upstream %q: %v", upstream, err)
	}
	p := httputil.NewSingleHostReverseProxy(u)
	p.Transport = &http.Transport{
		MaxIdleConns:        256,
		MaxIdleConnsPerHost: 128,
		IdleConnTimeout:     30 * time.Second,
		DialContext: (&net.Dialer{Timeout: 5 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
	}
	p.FlushInterval = -1
	p.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		w.Header().Set("Server", server)
		w.Header().Set("Content-Type", "text/html")
		w.WriteHeader(http.StatusBadGateway)
		_, _ = w.Write([]byte("502 upstream unavailable"))
	}
	p.ModifyResponse = func(res *http.Response) error {
		res.Header.Set("Server", server)
		res.Header.Del("X-Powered-By")
		res.Header.Del("Via")
		for k, v := range app {
			res.Header.Set(k, v)
		}
		return nil
	}
	return p, nil
}

func splitPort(raw string) string {
	if i := strings.LastIndex(raw, ":"); i > 0 && !strings.Contains(raw[i:], "]") {
		if _, err := strconv.Atoi(raw[i+1:]); err == nil {
			return raw[:i]
		}
	}
	return raw
}

func normHost(raw string, stripDot bool) string {
	h := strings.ToLower(splitPort(raw))
	if stripDot {
		h = strings.TrimSuffix(h, ".")
	}
	return h
}

func stripPolicy(v string) bool { return v != "keep" }

func newRoute(h HostRule) (*route, error) {
	rt := &route{server: h.Server, app: h.AppHeader, status: h.Status, label: h.Host}
	if rt.server == "" {
		rt.server = "Microsoft-HTTPAPI/2.0"
	}
	if h.Status > 0 || (h.Upstream == "" && h.BodyFile != "") {
		b, err := loadBody(h.BodyFile)
		if err != nil {
			return nil, err
		}
		rt.body, rt.bodyKnown = b, true
		return rt, nil
	}
	if h.Upstream == "" {
		return nil, fmt.Errorf("rule %q: no upstream and no status", h.Host)
	}
	p, err := makeProxy(h.Upstream, rt.server, rt.app)
	if err != nil {
		return nil, err
	}
	rt.proxy = p
	return rt, nil
}

func loadConfig(path string) (*gateway, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg Config
	if err := json.Unmarshal(raw, &cfg); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	g := &gateway{cfg: cfg, exact: map[string]*route{}}

	// unknown host / bare IP
	fb := &route{server: cfg.DefaultServer, label: "default-404"}
	if fb.server == "" {
		fb.server = "Microsoft-HTTPAPI/2.0"
	}
	if cfg.DefaultBody != "" {
		b, err := loadBody(cfg.DefaultBody)
		if err != nil {
			return nil, err
		}
		fb.body, fb.bodyKnown = b, true
	}
	g.fallback = fb

	if cfg.DefaultHost != nil {
		rt, err := newRoute(*cfg.DefaultHost)
		if err != nil {
			return nil, err
		}
		rt.label = "default-host:" + cfg.DefaultHost.Host
		g.def = rt
	}

	for _, h := range cfg.Sites {
		rt, err := newRoute(h)
		if err != nil {
			return nil, err
		}
		rt.ci = h.CaseInsensitive
		for _, pr := range h.Paths {
			sub, err := newRoute(HostRule{Host: h.Host + pr.Prefix, Upstream: pr.Upstream,
				Server: rt.server, AppHeader: h.AppHeader})
			if err != nil {
				return nil, err
			}
			sub.pathPrefix, sub.label = pr.Prefix, "path:"+h.Host+pr.Prefix
			sub.pathRewrite = pr.Rewrite
			sub.dropPath = pr.DropPath
			if sub.pathRewrite == "" {
				sub.pathRewrite = "/"
			}
			rt.subs = append(rt.subs, sub)
		}
		key := normHost(h.Host, stripPolicy(h.TrailingDot))
		g.exact[key] = rt
	}

	for _, k := range cfg.Keywords {
		rt, err := newRoute(HostRule{Host: k.Contains, Upstream: k.Upstream, Server: k.Server,
			Status: k.Status, BodyFile: k.BodyFile, AppHeader: k.AppHeader})
		if err != nil {
			return nil, err
		}
		rt.label = "keyword:" + k.Contains
		m := k.Match
		if m == "" {
			m = "contains"
		}
		g.kw = append(g.kw, kwRule{raw: strings.ToLower(k.Contains), match: m, r: rt})
	}
	// longest / most specific first
	rank := map[string]int{"suffix": 0, "prefix": 1, "contains": 2}
	sort.SliceStable(g.kw, func(i, j int) bool {
		if len(g.kw[i].raw) != len(g.kw[j].raw) {
			return len(g.kw[i].raw) > len(g.kw[j].raw)
		}
		return rank[g.kw[i].match] < rank[g.kw[j].match]
	})

	cert, err := tls.LoadX509KeyPair(cfg.CertFile, cfg.KeyFile)
	if err != nil {
		return nil, fmt.Errorf("default cert: %w", err)
	}
	sniCerts := map[string]*tls.Certificate{}
	for name, pair := range cfg.SNI {
		c, err := tls.LoadX509KeyPair(pair.Cert, pair.Key)
		if err != nil {
			return nil, fmt.Errorf("sni cert %s: %w", name, err)
		}
		cc := c
		sniCerts[strings.ToLower(name)] = &cc
	}
	g.tlsConf = &tls.Config{
		MinVersion: tls.VersionTLS12,
		GetCertificate: func(chi *tls.ClientHelloInfo) (*tls.Certificate, error) {
			if silentSNIBlocked(cfg, chi.ServerName) {
				// never answer: the client times out waiting for ServerHello
				time.Sleep(holdDuration(cfg))
				return nil, fmt.Errorf("handshake refused")
			}
			if c, ok := sniCerts[strings.ToLower(chi.ServerName)]; ok {
				return c, nil
			}
			return &cert, nil
		},
	}
	if cfg.Silent != nil && cfg.Silent.RequireHost {
		// hijacking needs HTTP/1.1; a silent-drop front end does not offer h2 anyway
		g.tlsConf.NextProtos = []string{"http/1.1"}
	}
	return g, nil
}

func holdDuration(cfg Config) time.Duration {
	secs := 20
	if cfg.Silent != nil && cfg.Silent.Hold > 0 {
		secs = cfg.Silent.Hold
	}
	return time.Duration(secs) * time.Second
}

func inList(list []string, v string) bool {
	v = strings.ToLower(strings.TrimSuffix(strings.TrimSpace(v), "."))
	if v == "" {
		return false
	}
	for _, x := range list {
		if strings.ToLower(strings.TrimSuffix(strings.TrimSpace(x), ".")) == v {
			return true
		}
	}
	return false
}

func silentSNIBlocked(cfg Config, sni string) bool {
	if cfg.Silent == nil || !cfg.Silent.RequireSNI {
		return false
	}
	return !inList(cfg.Silent.AllowSNI, sni)
}

// inListExact is the strict form: the value is lowercased and the port removed,
// but a trailing dot is NOT normalised away (that is exactly the kind of gap a
// literal allow-list leaves open).
func inListExact(list []string, v string) bool {
	v = strings.ToLower(strings.TrimSpace(splitPort(v)))
	if v == "" {
		return false
	}
	for _, x := range list {
		if strings.ToLower(strings.TrimSpace(x)) == v {
			return true
		}
	}
	return false
}

func silentHostBlocked(cfg Config, host string) bool {
	if cfg.Silent == nil || !cfg.Silent.RequireHost {
		return false
	}
	return !inListExact(cfg.Silent.AllowHost, host)
}

// silentDrop keeps the socket open and writes nothing: the client sees a hang,
// not a 4xx. Hijacking is the only way to answer with zero bytes on HTTP/1.1.
func silentDrop(w http.ResponseWriter, hold time.Duration) {
	hj, ok := w.(http.Hijacker)
	if !ok {
		time.Sleep(hold)
		panic(http.ErrAbortHandler)
	}
	conn, _, err := hj.Hijack()
	if err != nil {
		return
	}
	time.Sleep(hold)
	_ = conn.Close()
}

func (g *gateway) resolve(hostHeader string) *route {
	if rt, ok := g.exact[normHost(hostHeader, true)]; ok {
		return rt
	}
	if rt, ok := g.exact[normHost(hostHeader, false)]; ok {
		return rt
	}
	h := normHost(hostHeader, true)
	rawLower := strings.ToLower(splitPort(hostHeader))
	for _, k := range g.kw {
		// suffix/prefix rules are about the literal Host, so a trailing dot matters;
		// contains rules look at the dot-stripped name.
		subject := h
		if k.match == "suffix" || k.match == "prefix" {
			subject = rawLower
		}
		var hit bool
		switch k.match {
		case "suffix":
			hit = strings.HasSuffix(subject, k.raw)
		case "prefix":
			hit = strings.HasPrefix(subject, k.raw)
		default:
			hit = strings.Contains(subject, k.raw)
		}
		if hit {
			return k.r
		}
	}
	if g.def != nil {
		return g.def
	}
	return g.fallback
}

func (g *gateway) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	start := time.Now()
	if silentHostBlocked(g.cfg, r.Host) {
		log.Printf("%s host=%q silent-drop (host not allowed)", clientIP(r), r.Host)
		silentDrop(w, holdDuration(g.cfg))
		return
	}
	sw := &statusWriter{ResponseWriter: w}
	rt := g.resolve(r.Host)
	hostRT := rt
	path := r.URL.Path

	// path rules: match case-insensitively when the site is flagged as an IIS-style host
	matchPath := path
	if hostRT.ci {
		matchPath = strings.ToLower(path)
	}
	if len(hostRT.subs) > 0 {
		for _, sub := range hostRT.subs {
			if strings.HasPrefix(matchPath, sub.pathPrefix) {
				if sub.dropPath {
					path = sub.pathRewrite
				} else {
					path = sub.pathRewrite + strings.TrimPrefix(matchPath, sub.pathPrefix)
				}
				rt = sub
				break
			}
		}
	}
	if rt == hostRT && hostRT.ci {
		path = matchPath
	}

	if rt.proxy == nil {
		sw.Header().Set("Server", rt.server)
		sw.Header().Set("Content-Type", "text/html")
		for k, v := range rt.app {
			sw.Header().Set(k, v)
		}
		if rt.bodyKnown {
			sw.Header().Set("Content-Length", strconv.Itoa(len(rt.body)))
		}
		st := rt.status
		if st == 0 {
			st = http.StatusNotFound
		}
		sw.WriteHeader(st)
		if len(rt.body) > 0 {
			_, _ = io.Copy(sw, strings.NewReader(string(rt.body)))
		}
	} else {
		r2 := r.Clone(r.Context())
		r2.URL.Path = path
		r2.Header.Set("X-Forwarded-Host", r.Host)
		if r.TLS != nil {
			r2.Header.Set("X-Forwarded-Proto", "https")
		} else {
			r2.Header.Set("X-Forwarded-Proto", "http")
		}
		rt.proxy.ServeHTTP(sw, r2)
	}
	log.Printf("%s host=%q path=%q rule=%q status=%d dur=%s",
		clientIP(r), r.Host, r.URL.Path, rt.label, sw.status, time.Since(start).Round(time.Millisecond))
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (s *statusWriter) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusWriter) Write(b []byte) (int, error) {
	if s.status == 0 {
		s.status = 200
	}
	return s.ResponseWriter.Write(b)
}

func clientIP(r *http.Request) string {
	if v := r.Header.Get("X-Forwarded-For"); v != "" {
		return strings.TrimSpace(strings.Split(v, ",")[0])
	}
	if h, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return h
	}
	return r.RemoteAddr
}

func main() {
	cfgPath := os.Getenv("SITES_CONFIG")
	if cfgPath == "" {
		cfgPath = "/etc/vhostlab/sites.json"
	}
	g, err := loadConfig(cfgPath)
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	log.Printf("edge: %d exact hosts, %d keyword rules, http=%s https=%s",
		len(g.exact), len(g.kw), g.cfg.HTTPAddr, g.cfg.HTTPSAddr)

	srvHTTP := &http.Server{Addr: g.cfg.HTTPAddr, Handler: g, ReadHeaderTimeout: 10 * time.Second}
	srvHTTPS := &http.Server{Addr: g.cfg.HTTPSAddr, Handler: g, TLSConfig: g.tlsConf,
		ReadHeaderTimeout: 10 * time.Second}

	if g.cfg.HTTPAddr != "" {
		go func() {
			if err := srvHTTP.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				log.Fatalf("http: %v", err)
			}
		}()
	}
	if g.cfg.HTTPSAddr != "" {
		go func() {
			if err := srvHTTPS.ListenAndServeTLS("", ""); err != nil && err != http.ErrServerClosed {
				log.Fatalf("https: %v", err)
			}
		}()
	}

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	log.Printf("edge: shutting down")
}
