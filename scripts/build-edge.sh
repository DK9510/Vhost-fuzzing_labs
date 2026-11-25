#!/usr/bin/env bash
# Build the shared edge image. Uses the containerised Go toolchain when the registry is
# reachable; falls back to the host Go toolchain + a scratch base image when it is not.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="vhostlab/edge:1.0"
LOG="${TMPDIR:-/tmp}/vhostlab-edge-build.log"

if docker build -q -t "$IMAGE" "$ROOT/_shared/edge" >"$LOG" 2>&1; then
  echo "built $IMAGE (containerised toolchain)"
  exit 0
fi

echo "container build failed (registry/toolchain unavailable), using host Go toolchain"
tail -3 "$LOG" | sed 's/^/    /' || true

case "$(uname -m)" in
  arm64|aarch64) GOARCH=arm64 ;;
  x86_64|amd64)  GOARCH=amd64 ;;
  *) echo "unsupported arch $(uname -m)"; exit 1 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
(
  cd "$ROOT/_shared/edge"
  CGO_ENABLED=0 GOOS=linux GOARCH="$GOARCH" go build -trimpath -ldflags='-s -w' -o "$tmp/edge" .
)
cat > "$tmp/Dockerfile" <<'EOF'
FROM scratch
COPY edge /usr/local/bin/edge
EXPOSE 8080 8443
ENTRYPOINT ["/usr/local/bin/edge"]
EOF
docker build -q -t "$IMAGE" "$tmp" >/dev/null
echo "built $IMAGE (host toolchain, scratch base, linux/$GOARCH)"
