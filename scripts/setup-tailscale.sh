#!/usr/bin/env bash
set -euo pipefail

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

DOCKER_COMPOSE=""

detect_docker_compose() {
	if docker compose version &>/dev/null; then
		DOCKER_COMPOSE="docker compose"
	elif docker-compose --version &>/dev/null; then
		DOCKER_COMPOSE="docker-compose"
	else
		die "Docker Compose is not installed."
	fi
}

info "Checking prerequisites..."

command -v docker &>/dev/null || die "Docker is not installed."
success "Docker found"

detect_docker_compose
success "Docker Compose found ($DOCKER_COMPOSE)"

if [[ ! -f .env ]]; then
	die ".env file not found. Run setup-docker.sh first."
fi
success ".env file exists"

if ! grep -q "^AUTH_SECRET=" .env 2>/dev/null; then
	die "AUTH_SECRET not configured. Run setup-docker.sh first."
fi
success "AUTH_SECRET configured"

printf "\n"

TS_AUTHKEY="${TS_AUTHKEY:-}"

if [[ -z "$TS_AUTHKEY" ]]; then
	cat <<EOF
${BOLD}Tailscale Auth Key Required${NC}

1. Go to: https://login.tailscale.com/admin/settings/keys
2. Generate a new auth key with:
   - Reusable: Yes (recommended for containers)
   - Ephemeral: Yes (node removed when container stops)
   - Tags: tag:container (optional, for ACL control)

EOF
	prompt_input "Tailscale auth key (tskey-auth-...): " TS_AUTHKEY
fi

if [[ -z "$TS_AUTHKEY" || ! "$TS_AUTHKEY" =~ ^tskey-auth- ]]; then
	die "Invalid Tailscale auth key. Must start with 'tskey-auth-'"
fi

success "Tailscale auth key provided"

if grep -q "^TS_AUTHKEY=" .env 2>/dev/null; then
	sed -i "s|^TS_AUTHKEY=.*|TS_AUTHKEY=${TS_AUTHKEY}|" .env
elif grep -q "^# TS_AUTHKEY=" .env 2>/dev/null; then
	sed -i "s|^# TS_AUTHKEY=.*|TS_AUTHKEY=${TS_AUTHKEY}|" .env
else
	echo "TS_AUTHKEY=${TS_AUTHKEY}" >> .env
fi

success "TS_AUTHKEY saved to .env"

printf "\n"

if [[ ! -d tailscale-config ]]; then
	mkdir -p tailscale-config
fi

cat > tailscale-config/serve.json <<'SERVEJSON'
{
  "TCP": {
    "443": {
      "HTTPS": true
    }
  },
  "Web": {
    "${TS_CERT_DOMAIN}:443": {
      "Handlers": {
        "/": {
          "Proxy": "http://127.0.0.1:5003"
        }
      }
    }
  }
}
SERVEJSON

success "Tailscale serve config created"

printf "\n"

info "Building Docker images..."
$DOCKER_COMPOSE --profile tailscale build

success "Docker images built"

printf "\n"

info "Starting containers with Tailscale..."
$DOCKER_COMPOSE --profile tailscale up -d

printf "\n"

info "Waiting for Tailscale to connect..."
TIMEOUT=60
INTERVAL=3
ELAPSED=0

while [[ $ELAPSED -lt $TIMEOUT ]]; do
	if docker exec opencode-tailscale tailscale status &>/dev/null; then
		success "Tailscale connected"
		break
	fi
	sleep "$INTERVAL"
	ELAPSED=$((ELAPSED + INTERVAL))
	printf "."
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
	warn "Tailscale connection timeout. Check logs: docker logs opencode-tailscale"
fi

printf "\n"

TS_IP=$(docker exec opencode-tailscale tailscale ip -4 2>/dev/null || echo "")
TS_HOSTNAME=$(docker exec opencode-tailscale tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//' || echo "")

printf '\n'
printf '%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$BOLD" "$NC"
printf '%b  OpenCode Manager + Tailscale is running%b\n' "$BOLD" "$NC"
printf '%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$BOLD" "$NC"
printf '\n'

if [[ -n "$TS_HOSTNAME" ]]; then
	printf '  %bTailscale URL:%b  https://%s\n' "$BOLD" "$NC" "$TS_HOSTNAME"
fi

if [[ -n "$TS_IP" ]]; then
	printf '  %bTailscale IP:%b   %s\n' "$BOLD" "$NC" "$TS_IP"
fi

printf '  %bLocal URL:%b      http://localhost:5003\n' "$BOLD" "$NC"
printf '\n'
printf '  %bLogs:%b   %s --profile tailscale logs -f\n' "$BOLD" "$NC" "$DOCKER_COMPOSE"
printf '  %bStop:%b   %s --profile tailscale down\n' "$BOLD" "$NC" "$DOCKER_COMPOSE"
printf '  %bStatus:%b %s --profile tailscale ps\n' "$BOLD" "$NC" "$DOCKER_COMPOSE"
printf '\n'

cat <<EOF
${BOLD}Next Steps:${NC}
1. Access the app via your Tailscale network using the URL above
2. For public HTTPS access, enable Tailscale Funnel:
   ${BOLD}docker exec opencode-tailscale tailscale funnel 443 on${NC}
3. Update AUTH_TRUSTED_ORIGINS in .env with your Tailscale hostname

EOF
