#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() { printf '%b  %s\n' "${BLUE}ℹ${NC}" "$*"; }
success() { printf '%b  %s\n' "${GREEN}✓${NC}" "$*" ; }
warn() { printf '%b  %s\n' "${YELLOW}⚠${NC}" "$*" ; }
error() { printf '%b  %s\n' "${RED}✗${NC}" "$*" >&2; }

die() {
    error "$@"
    exit 1
}

prompt_input() {
    local prompt="$1" var_name="$2" default="${3:-}" _input
    if [ -t 0 ]; then
        printf '%b%s%b' "$BOLD" "$prompt" "$NC"
        read -r _input
        if [[ -z "$_input" && -n "$default" ]]; then
            _input="$default"
        fi
    else
        _input="$default"
    fi
    printf -v "$var_name" '%s' "$_input"
}

prompt_yn() {
    local prompt="$1" default="${2:-n}"
    if [ ! -t 0 ]; then
        [[ "$default" == "y" ]] && return 0 || return 1
    fi
    local answer
    printf '%b%s%b' "$BOLD" "$prompt" "$NC"
    read -r answer
    answer="${answer:-$default}"
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

printf '\n%bOpenCode Manager — Tailscale Setup%b\n\n' "$BOLD" "$NC"

info "Checking prerequisites..."

command -v docker &>/dev/null || die "Docker is not installed. Install it from https://docs.docker.com/get-docker/"

if command -v docker compose &>/dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &>/dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    die "Docker Compose is not installed. Install it from https://docs.docker.com/compose/install/"
fi
success "Docker Compose found ($DOCKER_COMPOSE)"

printf "\n"

# Check if .env file exists
if [[ ! -f .env ]]; then
    warn ".env file not found. Creating from .env.example..."
    cp .env.example .env
    info ".env file created from .env.example"
fi

# Check if Tailscale auth key is set in .env
if ! grep -q "^TS_AUTHKEY=" .env 2>/dev/null; then
    info "Tailscale configuration not found in .env"
    
    if prompt_yn "Would you like to set up Tailscale access? (y/N): " "n"; then
        echo "" >> .env
        echo "# Tailscale Configuration" >> .env
        echo "# Get an auth key from https://login.tailscale.com/admin/authkeys" >> .env
        
        prompt_input "Tailscale auth key: " TS_AUTHKEY
        if [[ -n "$TS_AUTHKEY" ]]; then
            sed -i.bak "s|^# TS_AUTHKEY=.*|TS_AUTHKEY=$TS_AUTHKEY|" .env
            success "Tailscale auth key added to .env"
        fi
        
        prompt_input "Tailscale hostname (default: opencode-manager): " TS_HOSTNAME "opencode-manager"
        if [[ -n "$TS_HOSTNAME" ]]; then
            sed -i.bak "s|^# TS_HOSTNAME=.*|TS_HOSTNAME=$TS_HOSTNAME|" .env
            success "Tailscale hostname set to $TS_HOSTNAME"
        fi
    fi
else
    info "Tailscale configuration found in .env"
fi

printf "\n"

info "Starting OpenCode Manager with Tailscale..."
$DOCKER_COMPOSE -f docker-compose.yml -f docker-compose.tailscale.yml up -d

info "Waiting for services to start..."
sleep 10

info "Checking container status..."
$DOCKER_COMPOSE -f docker-compose.yml -f docker-compose.tailscale.yml ps

printf '\n'
printf '%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$BOLD" "$NC"
printf '%b  OpenCode Manager with Tailscale%b\n' "$BOLD" "$NC"
printf '%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$BOLD" "$NC"
printf '\n'
printf '  %bAccess:%b  Your Tailscale IP will appear once connected\n' "$BOLD" "$NC"
printf '  %bNote:%b    Find your Tailscale IP at https://login.tailscale.com/admin/machines\n' "$BOLD" "$NC"
printf '\n'
printf '  %bLogs:%b   %s -f docker-compose.yml -f docker-compose.tailscale.yml logs -f\n' "$BOLD" "$NC" "$DOCKER_COMPOSE"
printf '  %bStop:%b   %s -f docker-compose.yml -f docker-compose.tailscale.yml down\n' "$BOLD" "$NC" "$DOCKER_COMPOSE"
printf '\n'

success "Tailscale setup complete! Check your Tailscale admin panel for the assigned IP address."