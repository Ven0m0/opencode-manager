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

prompt_secret() {
	local prompt="$1" var_name="$2" _input
	if [ -t 0 ]; then
		printf '%b%s%b' "$BOLD" "$prompt" "$NC"
		read -rs _input
		printf "\n"
	else
		_input=""
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

SKIP_ENV="${SKIP_ENV:-false}"
NO_VAPID=false
NO_ADMIN=false
NO_START=false

usage() {
	cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Automatic Docker setup for OpenCode Manager.

Options:
  --skip-env    Don't create .env (use existing)
  --no-vapid    Skip VAPID key generation prompt
  --no-admin    Skip admin credentials prompt
  --no-start    Build only, don't start containers
  -h, --help    Show this help message

Environment variables (for CI/CD):
  ADMIN_EMAIL       Pre-set admin email
  ADMIN_PASSWORD    Pre-set admin password
  VAPID_SUBJECT     Pre-set VAPID subject (triggers key generation)
  SKIP_ENV          Set to "true" to skip .env creation
USAGE
	exit 0
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--skip-env) SKIP_ENV=true ;;
	--no-vapid) NO_VAPID=true ;;
	--no-admin) NO_ADMIN=true ;;
	--no-start) NO_START=true ;;
	-h | --help) usage ;;
	*) die "Unknown option: $1. Use --help for usage." ;;
	esac
	shift
done

cd "$PROJECT_DIR"

printf '\n%bOpenCode Manager — Docker Setup%b\n\n' "$BOLD" "$NC"

DOCKER_COMPOSE=""

detect_docker_compose() {
	if docker compose version &>/dev/null; then
		DOCKER_COMPOSE="docker compose"
	elif docker-compose --version &>/dev/null; then
		DOCKER_COMPOSE="docker-compose"
	else
		die "Docker Compose is not installed. Install it from https://docs.docker.com/compose/install/"
	fi
}

info "Checking prerequisites..."

command -v docker &>/dev/null || die "Docker is not installed. Install it from https://docs.docker.com/get-docker/"
success "Docker found"

detect_docker_compose
success "Docker Compose found ($DOCKER_COMPOSE)"

command -v openssl &>/dev/null || die "OpenSSL is not installed. Install it with your package manager."
success "OpenSSL found"

printf "\n"

info "Generating AUTH_SECRET..."
GENERATED_AUTH_SECRET=$(openssl rand -base64 32)
success "AUTH_SECRET generated"

GENERATED_VAPID_PUBLIC=""
GENERATED_VAPID_PRIVATE=""
GENERATED_VAPID_SUBJECT="${VAPID_SUBJECT:-}"

generate_vapid_keys() {
	local tmpdir
	tmpdir=$(mktemp -d)
	# shellcheck disable=SC2064
	trap "rm -rf \"$tmpdir\"" RETURN

	openssl ecparam -genkey -name prime256v1 -noout -out "$tmpdir/ec_key.pem" 2>/dev/null

	local raw_private
	raw_private=$(openssl ec -in "$tmpdir/ec_key.pem" -outform DER 2>/dev/null |
		openssl asn1parse -inform DER -offset 7 -length 32 -out "$tmpdir/raw_priv" -noout 2>/dev/null &&
		cat "$tmpdir/raw_priv" | openssl base64 -A)

	local raw_public
	raw_public=$(openssl ec -in "$tmpdir/ec_key.pem" -pubout -outform DER 2>/dev/null |
		tail -c 65 | openssl base64 -A)

	base64url_encode() {
		tr '+/' '-_' | tr -d '='
	}

	GENERATED_VAPID_PRIVATE=$(echo -n "$raw_private" | base64url_encode)
	GENERATED_VAPID_PUBLIC=$(echo -n "$raw_public" | base64url_encode)
}

if [[ "$NO_VAPID" == false ]]; then
	if [[ -n "$GENERATED_VAPID_SUBJECT" ]]; then
		info "VAPID_SUBJECT detected from environment, generating keys..."
		generate_vapid_keys
		success "VAPID keys generated"
	elif prompt_yn "Enable push notifications? (y/N): " "n"; then
		while true; do
			prompt_input "VAPID subject (mailto:you@example.com): " GENERATED_VAPID_SUBJECT
			if [[ "$GENERATED_VAPID_SUBJECT" == mailto:* ]]; then
				break
			fi
			warn "VAPID subject must start with 'mailto:' — required for iOS/Safari"
		done
		info "Generating VAPID keys..."
		generate_vapid_keys
		success "VAPID keys generated"
	fi
fi

printf "\n"

GENERATED_ADMIN_EMAIL="${ADMIN_EMAIL:-}"
GENERATED_ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

if [[ "$NO_ADMIN" == false && -z "$GENERATED_ADMIN_EMAIL" ]]; then
	if prompt_yn "Set up admin account? (y/N): " "n"; then
		prompt_input "Admin email: " GENERATED_ADMIN_EMAIL
		if [[ -n "$GENERATED_ADMIN_EMAIL" ]]; then
			confirm_pw=""
			while true; do
				prompt_secret "Admin password: " GENERATED_ADMIN_PASSWORD
				prompt_secret "Confirm password: " confirm_pw
				if [[ "$GENERATED_ADMIN_PASSWORD" == "$confirm_pw" ]]; then
					break
				fi
				warn "Passwords do not match, try again"
			done
			success "Admin credentials configured"
		fi
	fi
fi

printf "\n"

if [[ "$SKIP_ENV" != "true" ]]; then
	if [[ -f .env ]]; then
		if ! prompt_yn "Overwrite existing .env? (y/N): " "n"; then
			info "Keeping existing .env"
			SKIP_ENV=true
		fi
	fi

	if [[ "$SKIP_ENV" != "true" ]]; then
		[[ -f .env.example ]] || die ".env.example not found in $PROJECT_DIR"

		info "Creating .env from .env.example..."
		cp .env.example .env

		sed -i "s|^# AUTH_SECRET=.*|AUTH_SECRET=${GENERATED_AUTH_SECRET}|" .env

		if [[ -n "$GENERATED_VAPID_PUBLIC" ]]; then
			sed -i "s|^# VAPID_PUBLIC_KEY=.*|VAPID_PUBLIC_KEY=${GENERATED_VAPID_PUBLIC}|" .env
			sed -i "s|^# VAPID_PRIVATE_KEY=.*|VAPID_PRIVATE_KEY=${GENERATED_VAPID_PRIVATE}|" .env
			sed -i "s|^# VAPID_SUBJECT=.*|VAPID_SUBJECT=${GENERATED_VAPID_SUBJECT}|" .env
		fi

		if [[ -n "$GENERATED_ADMIN_EMAIL" ]]; then
			sed -i "s|^# ADMIN_EMAIL=.*|ADMIN_EMAIL=${GENERATED_ADMIN_EMAIL}|" .env
		fi

		if [[ -n "$GENERATED_ADMIN_PASSWORD" ]]; then
			sed -i "s|^# ADMIN_PASSWORD=.*|ADMIN_PASSWORD=${GENERATED_ADMIN_PASSWORD}|" .env
		fi

		success ".env created"
	fi
fi

printf "\n"

info "Building Docker image..."
$DOCKER_COMPOSE build

success "Docker image built"

if [[ "$NO_START" == true ]]; then
	printf "\n"
	success "Setup complete (--no-start: containers not started)"
	printf "\n"
	info "Start with: $DOCKER_COMPOSE up -d"
	exit 0
fi

printf "\n"

info "Starting containers..."
$DOCKER_COMPOSE up -d

info "Waiting for health check..."
HEALTH_URL="http://localhost:5003/api/health"
TIMEOUT=60
INTERVAL=2
ELAPSED=0

while [[ $ELAPSED -lt $TIMEOUT ]]; do
	if curl -sf "$HEALTH_URL" &>/dev/null; then
		success "Application is healthy"
		break
	fi
	sleep "$INTERVAL"
	ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
	warn "Health check timed out after ${TIMEOUT}s — container may still be starting"
	warn "Check logs: $DOCKER_COMPOSE logs -f"
fi

printf '\n'
printf '%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$BOLD" "$NC"
printf '%b  OpenCode Manager is running%b\n' "$BOLD" "$NC"
printf '%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$BOLD" "$NC"
printf '\n'
printf '  %bURL:%b  http://localhost:5003\n' "$BOLD" "$NC"

if [[ -n "$GENERATED_ADMIN_EMAIL" ]]; then
	printf '  %bAdmin:%b  %s\n' "$BOLD" "$NC" "$GENERATED_ADMIN_EMAIL"
fi

if [[ -n "$GENERATED_VAPID_PUBLIC" ]]; then
	printf '  %bPush:%b  Enabled\n' "$BOLD" "$NC"
fi

printf '\n'
printf '  %bLogs:%b   %s logs -f\n' "$BOLD" "$NC" "$DOCKER_COMPOSE"
printf '  %bStop:%b   %s down\n' "$BOLD" "$NC" "$DOCKER_COMPOSE"
printf '  %bStatus:%b %s ps\n' "$BOLD" "$NC" "$DOCKER_COMPOSE"
printf '\n'
