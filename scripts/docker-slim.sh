#!/usr/bin/env bash
set -euo pipefail

IMAGE="opencode-manager"
TAG_FULL="${IMAGE}:latest"
TAG_SLIM="${IMAGE}:slim"

usage() {
  echo "Usage: $0 [build|slim|run|all|clean]"
  echo "  build  - Build the Docker image"
  echo "  slim   - Run slim against the built image"
  echo "  run    - Start the container"
  echo "  all    - Build, slim, then run the slimmed image"
  echo "  clean  - Remove slimmed image"
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
      --continue-after=10 \
      --include-path=/app \
      --include-path=/workspace \
      --include-path=/opt/opencode \
      --include-path=/usr/local/bin \
      --include-shell \
      --include-cert-all \
      --include-oslibs-net \
      --show-blogs=true \
      --copy-meta-artifacts=/tmp/artifacts
  else
    docker run --rm \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v /tmp:/tmp \
      dslim/slim build \
        --target "${TAG_FULL}" \
        --tag "${TAG_SLIM}" \
        --http-probe=false \
        --continue-after=10 \
        --include-path=/app \
        --include-path=/workspace \
        --include-path=/opt/opencode \
        --include-path=/usr/local/bin \
        --include-shell \
        --include-cert-all \
        --include-oslibs-net \
        --show-blogs=true \
        --copy-meta-artifacts=/tmp/artifacts
  fi

  echo ""
  echo "==> Size comparison:"
  docker images "${IMAGE}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
  
  echo ""
  echo "Slimmed image ${TAG_SLIM} created successfully!"
}

cmd_clean() {
  echo "==> Removing slimmed image ${TAG_SLIM}..."
  docker rmi "${TAG_SLIM}" 2>/dev/null || echo "Image ${TAG_SLIM} not found or already removed"
}

cmd_run() {
  local tag="${1:-latest}"
  echo "==> Starting ${IMAGE}:${tag}..."
  IMAGE_TAG="${tag}" docker compose up -d app
}

case "${1:-}" in
  build) cmd_build ;;
  slim)  cmd_slim ;;
  run)   cmd_run "${2:-latest}" ;;
  clean) cmd_clean ;;
  all)   cmd_build; cmd_slim; cmd_run slim ;;
  *)     usage ;;
esac
