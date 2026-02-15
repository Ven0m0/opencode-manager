# Docker-Slim & Tailscale Integration Implementation Plan

> **REQUIRED SUB-SKILL:** Use the executing-plans skill to implement this plan task-by-task.

**Goal:** Complete docker-slim optimization for smaller images, ensure container builds successfully, finish auto-setup scripts, and add Tailscale integration for secure internet exposure.

**Architecture:** Multi-stage Docker build with docker-slim post-processing to reduce image size by 60-80%. Tailscale sidecar pattern for secure remote access without exposing ports publicly. Auto-setup scripts handle environment generation, VAPID keys, and admin account creation.

**Tech Stack:** Docker, docker-slim, Tailscale, Bash scripting, Bun runtime, OpenCode

---

## Task 1: Fix Docker Entrypoint Script

**Files:**
- Modify: `scripts/docker-entrypoint.sh`

**Step 1: Make entrypoint executable**

Run:
```bash
chmod +x scripts/docker-entrypoint.sh
```

**Step 2: Test the entrypoint script syntax**

Run:
```bash
bash -n scripts/docker-entrypoint.sh
```

Expected: No output (syntax valid)

**Step 3: Verify the docker build completes**

Run:
```bash
docker compose build app
```

Expected: Build completes successfully without errors

**Step 4: Commit**

```bash
git add scripts/docker-entrypoint.sh
git commit -m "fix: ensure docker-entrypoint.sh is executable"
```

---

## Task 2: Enhance Docker-Slim Script

**Files:**
- Modify: `scripts/docker-slim.sh`
- Create: `scripts/docker-slim-tailscale.sh`

**Step 1: Make docker-slim.sh executable**

Run:
```bash
chmod +x scripts/docker-slim.sh
```

**Step 2: Add slim tag support to docker-compose**

Add to `docker-compose.yml` in the app service:

```yaml
app:
  image: ${IMAGE_TAG:-opencode-manager:latest}
  # rest of config...
```

**Step 3: Test docker-slim build**

Run:
```bash
./scripts/docker-slim.sh build
```

Expected: Image builds successfully

**Step 4: Commit**

```bash
git add scripts/docker-slim.sh docker-compose.yml
git commit -m "feat: add docker-slim image tag support to compose"
```

---

## Task 3: Add Tailscale to Dockerfile

**Files:**
- Modify: `Dockerfile`
- Create: `scripts/tailscale-setup.sh`

**Step 1: Add Tailscale installation to Dockerfile base stage**

Add after existing apt-get install in base stage:

```dockerfile
FROM oven/bun:1 AS base

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl lsof ripgrep ca-certificates grep gawk sed \
    findutils coreutils procps jq less tree file \
    python3 python3-pip python3-venv \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && curl -fsSL https://tailscale.com/install.sh | sh \
    && find /usr/lib/python*/ \( -name test -o -name tests \) -exec rm -rf {} + 2>/dev/null || true \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
```

**Step 2: Create Tailscale setup script**

Create `scripts/tailscale-setup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() { printf '%b  %s\n' "${BLUE}ℹ${NC}" "$*"; }
success() { printf '%b  %s\n' "${GREEN}✓${NC}" "$*"; }
error() { printf '%b  %s\n' "${RED}✗${NC}" "$*" >&2; }

die() {
    error "$@"
    exit 1
}

if [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
    die "TAILSCALE_AUTHKEY environment variable is required"
fi

info "Starting Tailscale daemon..."
tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock &
TAILSCALED_PID=$!

sleep 2

info "Authenticating with Tailscale..."
tailscale up \
    --authkey="${TAILSCALE_AUTHKEY}" \
    --hostname="${TAILSCALE_HOSTNAME:-opencode-manager}" \
    --accept-routes="${TAILSCALE_ACCEPT_ROUTES:-false}" \
    --advertise-tags="${TAILSCALE_TAGS:-}"

success "Tailscale connected"
tailscale status

wait $TAILSCALED_PID
```

**Step 3: Make script executable**

Run:
```bash
chmod +x scripts/tailscale-setup.sh
```

**Step 4: Test Dockerfile builds with Tailscale**

Run:
```bash
docker compose build app
```

Expected: Build completes successfully with Tailscale installed

**Step 5: Commit**

```bash
git add Dockerfile scripts/tailscale-setup.sh
git commit -m "feat: add Tailscale installation to Docker image"
```

---

## Task 4: Create Tailscale Docker Compose Service

**Files:**
- Modify: `docker-compose.yml`
- Create: `docker-compose.tailscale.yml`

**Step 1: Create Tailscale compose override**

Create `docker-compose.tailscale.yml`:

```yaml
services:
  tailscale:
    image: tailscale/tailscale:latest
    container_name: opencode-tailscale
    hostname: opencode-manager
    environment:
      - TS_AUTHKEY=${TAILSCALE_AUTHKEY}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_HOSTNAME=${TAILSCALE_HOSTNAME:-opencode-manager}
      - TS_ACCEPT_ROUTES=${TAILSCALE_ACCEPT_ROUTES:-false}
      - TS_EXTRA_ARGS=${TAILSCALE_EXTRA_ARGS:---advertise-tags=tag:container}
    volumes:
      - tailscale-state:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    restart: unless-stopped
    network_mode: service:app

  app:
    depends_on:
      - tailscale

volumes:
  tailscale-state:
    driver: local
```

**Step 2: Add Tailscale environment variables to .env.example**

Add to `.env.example`:

```bash
# ============================================
# Tailscale Configuration (optional)
# ============================================
# Enable remote access via Tailscale VPN
# Get auth key from: https://login.tailscale.com/admin/settings/keys
# TAILSCALE_AUTHKEY=tskey-auth-xxxxx
# TAILSCALE_HOSTNAME=opencode-manager
# TAILSCALE_ACCEPT_ROUTES=false
# TAILSCALE_EXTRA_ARGS=--advertise-tags=tag:container
```

**Step 3: Test Tailscale compose file syntax**

Run:
```bash
docker compose -f docker-compose.yml -f docker-compose.tailscale.yml config
```

Expected: Valid YAML output without errors

**Step 4: Commit**

```bash
git add docker-compose.tailscale.yml .env.example
git commit -m "feat: add Tailscale docker compose service"
```

---

## Task 5: Create Tailscale Setup Script

**Files:**
- Create: `scripts/setup-tailscale.sh`

**Step 1: Create interactive Tailscale setup script**

Create `scripts/setup-tailscale.sh`:

```bash
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
    printf '%b%s%b' "$BOLD" "$prompt" "$NC"
    read -r _input
    if [[ -z "$_input" && -n "$default" ]]; then
        _input="$default"
    fi
    printf -v "$var_name" '%s' "$_input"
}

prompt_yn() {
    local prompt="$1" default="${2:-n}"
    local answer
    printf '%b%s%b' "$BOLD" "$prompt" "$NC"
    read -r answer
    answer="${answer:-$default}"
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

printf '\n%bTailscale Setup for OpenCode Manager%b\n\n' "$BOLD" "$NC"

[[ -f .env ]] || die ".env file not found. Run ./scripts/setup-docker.sh first."

if grep -q "^TAILSCALE_AUTHKEY=" .env 2>/dev/null; then
    if ! prompt_yn "Tailscale already configured. Reconfigure? (y/N): " "n"; then
        info "Keeping existing Tailscale configuration"
        exit 0
    fi
fi

printf '\n'
info "Tailscale allows secure remote access to your OpenCode Manager without exposing ports."
info "You'll need an auth key from: https://login.tailscale.com/admin/settings/keys"
printf '\n'

AUTHKEY=""
HOSTNAME=""
ACCEPT_ROUTES=""
EXTRA_ARGS=""

prompt_input "Tailscale auth key (tskey-auth-...): " AUTHKEY
[[ -n "$AUTHKEY" ]] || die "Auth key is required"

prompt_input "Hostname (default: opencode-manager): " HOSTNAME "opencode-manager"

if prompt_yn "Accept subnet routes? (y/N): " "n"; then
    ACCEPT_ROUTES="true"
else
    ACCEPT_ROUTES="false"
fi

prompt_input "Extra Tailscale args (default: --advertise-tags=tag:container): " EXTRA_ARGS "--advertise-tags=tag:container"

info "Updating .env..."

if grep -q "^# TAILSCALE_AUTHKEY=" .env; then
    sed -i "s|^# TAILSCALE_AUTHKEY=.*|TAILSCALE_AUTHKEY=${AUTHKEY}|" .env
    sed -i "s|^# TAILSCALE_HOSTNAME=.*|TAILSCALE_HOSTNAME=${HOSTNAME}|" .env
    sed -i "s|^# TAILSCALE_ACCEPT_ROUTES=.*|TAILSCALE_ACCEPT_ROUTES=${ACCEPT_ROUTES}|" .env
    sed -i "s|^# TAILSCALE_EXTRA_ARGS=.*|TAILSCALE_EXTRA_ARGS=${EXTRA_ARGS}|" .env
else
    cat >> .env <<EOF

# Tailscale Configuration
TAILSCALE_AUTHKEY=${AUTHKEY}
TAILSCALE_HOSTNAME=${HOSTNAME}
TAILSCALE_ACCEPT_ROUTES=${ACCEPT_ROUTES}
TAILSCALE_EXTRA_ARGS=${EXTRA_ARGS}
EOF
fi

success "Tailscale configuration saved to .env"

printf '\n'
info "Starting Tailscale service..."

if command -v docker compose &>/dev/null; then
    docker compose -f docker-compose.yml -f docker-compose.tailscale.yml up -d tailscale
elif command -v docker-compose &>/dev/null; then
    docker-compose -f docker-compose.yml -f docker-compose.tailscale.yml up -d tailscale
else
    die "Docker Compose not found"
fi

sleep 5

info "Checking Tailscale status..."
docker exec opencode-tailscale tailscale status || warn "Tailscale not connected yet (may take a moment)"

printf '\n'
printf '%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$BOLD" "$NC"
printf '%b  Tailscale Setup Complete%b\n' "$BOLD" "$NC"
printf '%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$BOLD" "$NC"
printf '\n'
printf '  %bNext Steps:%b\n' "$BOLD" "$NC"
printf '  1. Check Tailscale admin: https://login.tailscale.com/admin/machines\n'
printf '  2. Find your Tailscale IP for %s\n' "$HOSTNAME"
printf '  3. Access OpenCode Manager at: http://<tailscale-ip>:5003\n'
printf '\n'
printf '  %bCommands:%b\n' "$BOLD" "$NC"
printf '  Status:   docker exec opencode-tailscale tailscale status\n'
printf '  Restart:  docker compose -f docker-compose.yml -f docker-compose.tailscale.yml restart tailscale\n'
printf '\n'
```

**Step 2: Make script executable**

Run:
```bash
chmod +x scripts/setup-tailscale.sh
```

**Step 3: Test script syntax**

Run:
```bash
bash -n scripts/setup-tailscale.sh
```

Expected: No output (syntax valid)

**Step 4: Commit**

```bash
git add scripts/setup-tailscale.sh
git commit -m "feat: add interactive Tailscale setup script"
```

---

## Task 6: Update Docker Setup Script with Tailscale Option

**Files:**
- Modify: `scripts/setup-docker.sh`

**Step 1: Add Tailscale prompt to setup-docker.sh**

Add before the "Starting containers..." section:

```bash
printf "\n"

SETUP_TAILSCALE=false
if prompt_yn "Set up Tailscale for remote access? (y/N): " "n"; then
    SETUP_TAILSCALE=true
fi
```

**Step 2: Add Tailscale setup call after container start**

Add after the health check section:

```bash
if [[ "$SETUP_TAILSCALE" == true ]]; then
    printf "\n"
    info "Running Tailscale setup..."
    "$SCRIPT_DIR/setup-tailscale.sh"
fi
```

**Step 3: Test script syntax**

Run:
```bash
bash -n scripts/setup-docker.sh
```

Expected: No output (syntax valid)

**Step 4: Commit**

```bash
git add scripts/setup-docker.sh
git commit -m "feat: integrate Tailscale setup into Docker setup script"
```

---

## Task 7: Create Docker-Slim with Tailscale Build Script

**Files:**
- Create: `scripts/docker-all.sh`

**Step 1: Create comprehensive build script**

Create `scripts/docker-all.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() { printf '%b  %s\n' "${BLUE}ℹ${NC}" "$*"; }
success() { printf '%b  %s\n' "${GREEN}✓${NC}" "$*"; }
error() { printf '%b  %s\n' "${RED}✗${NC}" "$*" >&2; }

die() {
    error "$@"
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Complete Docker setup: build, slim, and optionally configure Tailscale.

Options:
  --skip-slim        Skip docker-slim optimization
  --skip-tailscale   Skip Tailscale configuration
  --no-cache         Build without cache
  --help             Show this help message
USAGE
    exit 0
}

SKIP_SLIM=false
SKIP_TAILSCALE=false
NO_CACHE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-slim) SKIP_SLIM=true ;;
        --skip-tailscale) SKIP_TAILSCALE=true ;;
        --no-cache) NO_CACHE="--no-cache" ;;
        --help) usage ;;
        *) die "Unknown option: $1. Use --help for usage." ;;
    esac
    shift
done

printf '\n%bOpenCode Manager — Complete Docker Setup%b\n\n' "$BOLD" "$NC"

info "Running base setup..."
"$SCRIPT_DIR/setup-docker.sh"

if [[ "$SKIP_SLIM" == false ]]; then
    printf '\n'
    info "Running docker-slim optimization..."
    "$SCRIPT_DIR/docker-slim.sh" slim
    
    printf '\n'
    info "Restarting with slim image..."
    IMAGE_TAG="slim" docker compose up -d app
fi

if [[ "$SKIP_TAILSCALE" == false ]]; then
    printf '\n'
    info "Running Tailscale setup..."
    "$SCRIPT_DIR/setup-tailscale.sh"
fi

printf '\n'
success "Complete setup finished!"
printf '\n'
```

**Step 2: Make script executable**

Run:
```bash
chmod +x scripts/docker-all.sh
```

**Step 3: Test script syntax**

Run:
```bash
bash -n scripts/docker-all.sh
```

Expected: No output (syntax valid)

**Step 4: Commit**

```bash
git add scripts/docker-all.sh
git commit -m "feat: add comprehensive Docker setup script with slim and Tailscale"
```

---

## Task 8: Update Documentation

**Files:**
- Create: `docs/deployment/docker-slim.md`
- Create: `docs/deployment/tailscale.md`
- Modify: `README.md`

**Step 1: Create docker-slim documentation**

Create `docs/deployment/docker-slim.md`:

```markdown
# Docker Slim Optimization

OpenCode Manager supports docker-slim optimization to reduce image size by 60-80%.

## Quick Start

```bash
# Build and slim in one command
./scripts/docker-slim.sh all

# Or step by step
./scripts/docker-slim.sh build
./scripts/docker-slim.sh slim
./scripts/docker-slim.sh run slim
```

## Size Comparison

Typical results:
- Full image: ~1.5-2GB
- Slim image: ~300-600MB

## How It Works

docker-slim analyzes the running container and creates a minimal image containing only:
- Required binaries and libraries
- Application code
- Runtime dependencies
- Certificate bundles
- Network libraries

## Configuration

The slim build includes:
- `/app` - Application code
- `/workspace` - Workspace directory
- `/opt/opencode` - OpenCode installation
- `/usr/local/bin` - System binaries
- Shell access for debugging
- SSL certificates
- Network libraries

## Manual Slimming

Using docker-slim directly:

```bash
slim build \
  --target opencode-manager:latest \
  --tag opencode-manager:slim \
  --http-probe=false \
  --continue-after=1 \
  --include-path=/app \
  --include-path=/workspace \
  --include-path=/opt/opencode \
  --include-path=/usr/local/bin \
  --include-shell \
  --include-cert-all \
  --include-oslibs-net
```

## Docker Compose

Use the slim profile:

```bash
# Build slim image
docker compose --profile slim up slim

# Run slim image
IMAGE_TAG=slim docker compose up -d app
```

## Troubleshooting

**Slim image fails to start:**
- Check logs: `docker compose logs -f app`
- Verify included paths contain all dependencies
- Try without `--http-probe=false` for interactive probing

**Missing dependencies:**
- Add additional paths with `--include-path`
- Use `--include-oslibs-net` for network libraries
- Use `--include-cert-all` for SSL certificates
```

**Step 2: Create Tailscale documentation**

Create `docs/deployment/tailscale.md`:

```markdown
# Tailscale Integration

Securely expose OpenCode Manager to the internet using Tailscale VPN.

## Why Tailscale?

- **No port forwarding** - Works behind NAT/firewalls
- **Zero-trust security** - End-to-end encrypted
- **Simple setup** - One auth key
- **Free tier** - Up to 100 devices

## Quick Start

```bash
# Interactive setup
./scripts/setup-tailscale.sh

# Or integrated with Docker setup
./scripts/setup-docker.sh
# Choose "yes" when prompted for Tailscale

# Complete setup (Docker + Slim + Tailscale)
./scripts/docker-all.sh
```

## Manual Setup

### 1. Get Tailscale Auth Key

1. Visit https://login.tailscale.com/admin/settings/keys
2. Generate a new auth key
3. Copy the key (starts with `tskey-auth-`)

### 2. Configure Environment

Add to `.env`:

```bash
TAILSCALE_AUTHKEY=tskey-auth-xxxxx
TAILSCALE_HOSTNAME=opencode-manager
TAILSCALE_ACCEPT_ROUTES=false
TAILSCALE_EXTRA_ARGS=--advertise-tags=tag:container
```

### 3. Start Tailscale Service

```bash
docker compose -f docker-compose.yml -f docker-compose.tailscale.yml up -d
```

## Access Your Instance

1. Check Tailscale admin: https://login.tailscale.com/admin/machines
2. Find your device's Tailscale IP
3. Access OpenCode Manager: `http://<tailscale-ip>:5003`

## Architecture

Tailscale runs as a sidecar container sharing the network namespace with the app:

```yaml
services:
  tailscale:
    network_mode: service:app  # Shares network with app
  
  app:
    depends_on:
      - tailscale
```

This allows Tailscale to expose the app's ports without additional configuration.

## Security Considerations

### Auth Tokens

Store auth keys securely:
- Use reusable keys for persistent deployments
- Use ephemeral keys for temporary access
- Rotate keys regularly

### Access Control

Configure ACLs in Tailscale admin:
- Restrict which devices can access the container
- Use tags for grouping containers
- Enable key expiry for better security

### HTTPS

For production use:
1. Use Tailscale HTTPS (`tailscale cert`)
2. Or configure a reverse proxy with SSL
3. Update `AUTH_TRUSTED_ORIGINS` in `.env`
4. Set `AUTH_SECURE_COOKIES=true`

## Commands

```bash
# Check Tailscale status
docker exec opencode-tailscale tailscale status

# View Tailscale IP
docker exec opencode-tailscale tailscale ip

# Restart Tailscale
docker compose -f docker-compose.yml -f docker-compose.tailscale.yml restart tailscale

# Stop Tailscale
docker compose -f docker-compose.yml -f docker-compose.tailscale.yml down tailscale
```

## Troubleshooting

**Tailscale won't connect:**
- Verify auth key is valid and not expired
- Check container logs: `docker logs opencode-tailscale`
- Ensure `NET_ADMIN` capability is granted

**Can't access from Tailscale network:**
- Verify device is connected to Tailscale
- Check firewall rules
- Ensure ports are not bound to localhost only

**State not persisting:**
- Verify `tailscale-state` volume exists
- Check volume mounts: `docker inspect opencode-tailscale`
```

**Step 3: Update README.md**

Add to README.md in the deployment section:

```markdown
## Docker Deployment

### Quick Setup

```bash
# Complete automated setup
./scripts/setup-docker.sh

# With docker-slim optimization
./scripts/docker-slim.sh all

# With Tailscale remote access
./scripts/setup-tailscale.sh

# Everything at once
./scripts/docker-all.sh
```

### Docker Slim

Reduce image size by 60-80% using docker-slim:

```bash
./scripts/docker-slim.sh all
```

See [docs/deployment/docker-slim.md](docs/deployment/docker-slim.md) for details.

### Tailscale Remote Access

Securely expose to the internet without port forwarding:

```bash
./scripts/setup-tailscale.sh
```

See [docs/deployment/tailscale.md](docs/deployment/tailscale.md) for details.
```

**Step 4: Commit**

```bash
git add docs/deployment/docker-slim.md docs/deployment/tailscale.md README.md
git commit -m "docs: add docker-slim and Tailscale deployment guides"
```

---

## Task 9: Verification and Testing

**Files:**
- None (testing only)

**Step 1: Clean build test**

Run:
```bash
docker compose down -v
docker compose build --no-cache
```

Expected: Build completes without errors

**Step 2: Test container startup**

Run:
```bash
docker compose up -d
sleep 10
curl -f http://localhost:5003/api/health
```

Expected: `{"status":"ok"}` or similar health response

**Step 3: Test docker-slim optimization**

Run:
```bash
./scripts/docker-slim.sh slim
docker images opencode-manager
```

Expected: Two images shown (latest and slim), slim significantly smaller

**Step 4: Test setup scripts**

Run:
```bash
docker compose down -v
./scripts/setup-docker.sh --no-admin --no-vapid --no-start
```

Expected: `.env` created, no errors

**Step 5: Clean up test artifacts**

Run:
```bash
docker compose down -v
docker rmi opencode-manager:slim || true
```

**Step 6: Commit verification**

```bash
git status
# Ensure all changes are committed
```

---

## Success Criteria

- ✅ Docker image builds without errors
- ✅ Container starts and passes health checks
- ✅ Docker-slim reduces image size by >60%
- ✅ Setup scripts run without user input (CI mode)
- ✅ Tailscale configuration documented and tested
- ✅ All scripts are executable
- ✅ Documentation is complete and accurate
