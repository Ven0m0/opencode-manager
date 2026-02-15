#!/usr/bin/env bash
set -euo pipefail

IMAGE="opencode-manager"
TAG_FULL="${IMAGE}:latest"
TAG_SLIM="${IMAGE}:slim"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() { printf '%b  %s\n' "${BLUE}ℹ${NC}" "$*"; }
success() { printf '%b  %s\n' "${GREEN}✓${NC}" "$*"; }
warn() { printf '%b  %s\n' "${YELLOW}⚠${NC}" "$*"; }
error() { printf '%b  %s\n' "${RED}✗${NC}" "$*" >&2; }

usage() {
  cat <<USAGE
Usage: $0 [COMMAND]

Commands:
  build    Build the Docker image (opencode-manager:latest)
  slim     Create optimized slim image (opencode-manager:slim)
  run      Start the container (use 'run slim' for slim image)
  compare  Show size comparison between images
  all      Build, slim, then run the slimmed image

Examples:
  $0 build          # Build standard image
  $0 slim           # Create slim image from latest
  $0 run            # Run standard image
  $0 run slim       # Run slim image
  $0 all            # Full pipeline: build -> slim -> run slim
USAGE
  exit 1
}

cmd_build() {
  info "Building ${TAG_FULL}..."
  docker compose build --no-cache
  success "Build complete"
  printf "\n"
  docker images "${IMAGE}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
}

cmd_slim() {
  if ! docker image inspect "${TAG_FULL}" >/dev/null 2>&1; then
    error "Image ${TAG_FULL} not found. Run '$0 build' first."
    exit 1
  fi

  if ! command -v slim >/dev/null 2>&1 && ! docker image inspect dslim/slim >/dev/null 2>&1; then
    info "Installing slim toolkit..."
    curl -sL https://raw.githubusercontent.com/slimtoolkit/slim/master/scripts/install-slim.sh | sudo -E bash -
  fi

  info "Slimming ${TAG_FULL} -> ${TAG_SLIM}..."
  info "This may take several minutes..."

  local slim_args=(
    --target "${TAG_FULL}"
    --tag "${TAG_SLIM}"
    --http-probe=false
    --continue-after=1
    --include-path=/app
    --include-path=/workspace
    --include-path=/opt/opencode
    --include-path=/opt/bun
    --include-path=/usr/local/bin
    --include-path=/usr/bin/git
    --include-path=/usr/bin/gh
    --include-path=/usr/bin/curl
    --include-path=/usr/bin/jq
    --include-path=/usr/bin/rg
    --include-path=/usr/lib
    --include-path=/etc/ssl
    --include-path=/etc/ca-certificates
    --include-shell
    --include-cert-all
    --include-oslibs-net
    --preserve-path=/home/bun
    --preserve-path=/tmp
  )

  if command -v slim >/dev/null 2>&1; then
    slim build "${slim_args[@]}"
  else
    docker run --rm \
      -v /var/run/docker.sock:/var/run/docker.sock \
      dslim/slim build "${slim_args[@]}"
  fi

  success "Slim complete"
  printf "\n"
  cmd_compare
}

cmd_compare() {
  info "Image size comparison:"
  docker images "${IMAGE}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"
  
  if docker image inspect "${TAG_FULL}" >/dev/null 2>&1 && docker image inspect "${TAG_SLIM}" >/dev/null 2>&1; then
    local full_size slim_size
    full_size=$(docker image inspect "${TAG_FULL}" --format '{{.Size}}')
    slim_size=$(docker image inspect "${TAG_SLIM}" --format '{{.Size}}')
    local reduction=$((100 - (slim_size * 100 / full_size)))
    printf "\n"
    success "Size reduction: ${reduction}%% ($(numfmt --to=iec ${full_size}) -> $(numfmt --to=iec ${slim_size}))"
  fi
}

cmd_run() {
  local tag="${1:-latest}"
  local image_tag="${IMAGE}:${tag}"
  
  if ! docker image inspect "${image_tag}" >/dev/null 2>&1; then
    error "Image ${image_tag} not found."
    if [[ "$tag" == "slim" ]]; then
      info "Run '$0 slim' to create the slim image first."
    else
      info "Run '$0 build' to build the image first."
    fi
    exit 1
  fi

  info "Starting ${image_tag}..."
  
  if [[ "$tag" == "slim" ]]; then
    docker run -d \
      --name opencode-manager-slim \
      --env-file .env \
      -p 5003:5003 \
      -p 5100-5103:5100-5103 \
      -v opencode-workspace:/workspace \
      -v opencode-data:/app/data \
      --restart unless-stopped \
      "${image_tag}"
  else
    docker compose up -d app
  fi
  
  success "Container started"
  info "Access at: http://localhost:5003"
}

cmd_stop() {
  info "Stopping containers..."
  docker compose down 2>/dev/null || true
  docker stop opencode-manager-slim 2>/dev/null || true
  docker rm opencode-manager-slim 2>/dev/null || true
  success "Containers stopped"
}

case "${1:-}" in
  build)   cmd_build ;;
  slim)    cmd_slim ;;
  run)     cmd_run "${2:-latest}" ;;
  compare) cmd_compare ;;
  stop)    cmd_stop ;;
  all)     cmd_build; cmd_slim; cmd_stop; cmd_run slim ;;
  *)       usage ;;
esac
