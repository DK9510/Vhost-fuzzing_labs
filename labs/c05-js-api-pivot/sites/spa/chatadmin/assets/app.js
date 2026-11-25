/* Chat Admin bundle — lab C05 */
window.__ENV = {
  API_BASE: "https://chat-api.corp.lab/api",
  STAGING_API: "https://chat-staging.corp.lab/api",
  BUILD: "2026.11.1",
  FEATURES: ["chat-status", "chat-settings", "canned-replies"]
};
(function () {
  var base = window.__ENV.API_BASE;
  fetch(base + "/chat-status", { credentials: "include" })
    .then(function (r) { return r.json(); })
    .then(function (d) { console.log("status", d); })
    .catch(function () { /* offline */ });
})();
