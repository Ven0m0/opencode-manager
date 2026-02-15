#!/usr/bin/env bash
set -euo pipefail

IMAGE="opencode-manager"
TAG_FULL="${IMAGE}:latest"
TAG_SLIM="${IMAGE}:slim"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

usage() {
  echo "Usage: $0 [build|slim|run|expose|all]"
  echo "  build   - Build the Docker image"
  echo "  slim    - Run slim against the built image"
  echo "  run     - Start the container"
  echo "  expose  - Start with Tailscale exposure (requires TS_AUTHKEY)"
  echo "  all     - Build, slim, then run the slimmed image"
  exit 1
}

cmd_build() {
  echo "==> Building ${TAG_FULL}..."
  docker compose build --no-cache
  docker images "${IMAGE}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
}

cmd_slim() {
  if ! command -v slim >/dev/null 2>&1 && ! docker image inspect dslim/slim >/dev/null 2>&1; then
    echo "Installing slim..."
    curl -sL https://raw.githubusercontent.com/slimtoolkit/slim/master/scripts/install-slim.sh | sudo -E bash -
  fi

  echo "==> Slimming ${TAG_FULL} -> ${TAG_SLIM}..."

  if command -v slim >/dev/null 2>&1; then
    slim build \
      --target "${TAG_FULL}" \
      --tag "${TAG_SLIM}" \
      --http-probe=false \
      --continue-after=1 \
      --include-path=/app \
      --include-path=/workspace \
      --include-path=/opt/opencode \
      --include-path=/usr/local/bin \
      --include-shell \
      --include-cert-all \
      --include-oslibs-net
  else
    docker run --rm \
      -v /var/run/docker.sock:/var/run/docker.sock \
      dslim/slim build \
        --target "${TAG_FULL}" \
        --tag "${TAG_SLIM}" \
        --http-probe=false \
        --continue-after=1 \
        --include-path=/app \
        --include-path=/workspace \
        --include-path=/opt/opencode \
        --include-path=/usr/local/bin \
        --include-shell \
        --include-cert-all \
        --include-oslibs-net
  fi

  echo ""
  echo "==> Size comparison:"
  docker images "${IMAGE}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
}

cmd_run() {
  local tag="${1:-latest}"
  echo "==> Starting ${IMAGE}:${tag}..."
  IMAGE_TAG="${tag}" docker compose up -d app
}

cmd_expose() {
  local tag="${1:-latest}"
  
  if [[ -z "${TS_AUTHKEY:-}" ]]; then
    echo "ERROR: TS_AUTHKEY is required for Tailscale exposure."
    echo ""
    echo "Get an auth key from: https://login.tailscale.com/admin/settings/keys"
    echo "Then run: TS_AUTHKEY=tskey-auth-xxx $0 expose"
    exit 1
  fi
  
  echo "==> Starting ${IMAGE}:${tag} with Tailscale exposure..."
  IMAGE_TAG="${tag}" docker compose --profile expose up -d
  
  echo ""
  echo "==> Tailscale status:"
  sleep 5
  docker exec opencode-tailscale tailscale status 2>/dev/null || echo "Waiting for Tailscale to connect..."
  
  echo ""
  echo "Your service will be available at: https://${TS_HOSTNAME:-opencode-manager}.<your-tailnet>.ts.net"
  echo "Check status: docker exec opencode-tailscale tailscale status"
}

case "${1:-}" in
  build)  cmd_build ;;
  slim)   cmd_slim ;;
  run)    cmd_run "${2:-latest}" ;;
  expose) cmd_expose "${2:-latest}" ;;
  all)    cmd_build; cmd_slim; cmd_run slim ;;
  *)      usage ;;
esac
