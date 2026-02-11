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
    && find /usr/lib/python*/ \( -name test -o -name tests \) -exec rm -rf {} + 2>/dev/null || true \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /app

# --- deps stage: install node_modules with bun ---
FROM base AS deps

COPY --chown=bun:bun package.json bun.lock ./
COPY --chown=bun:bun shared/package.json ./shared/
COPY --chown=bun:bun backend/package.json ./backend/
COPY --chown=bun:bun frontend/package.json ./frontend/

RUN bun install --frozen-lockfile

# --- builder stage: build frontend ---
FROM base AS builder

COPY --from=deps /app ./
COPY shared ./shared
COPY backend ./backend
COPY frontend/src ./frontend/src
COPY frontend/public ./frontend/public
COPY frontend/index.html frontend/vite.config.ts frontend/tsconfig*.json frontend/components.json frontend/eslint.config.js ./frontend/

RUN cd frontend && bun run build

# --- runner stage: final image ---
FROM base AS runner

ARG UV_VERSION=latest
ARG OPENCODE_VERSION=latest

RUN curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh \
    && mv /root/.local/bin/uv /usr/local/bin/uv \
    && mv /root/.local/bin/uvx /usr/local/bin/uvx \
    && chmod +x /usr/local/bin/uv /usr/local/bin/uvx \
    && if [ "${OPENCODE_VERSION}" = "latest" ]; then \
         curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path; \
       else \
         curl -fsSL https://opencode.ai/install | bash -s -- --version "${OPENCODE_VERSION}" --no-modify-path; \
       fi \
    && mv /root/.opencode /opt/opencode \
    && chmod -R 755 /opt/opencode \
    && ln -s /opt/opencode/bin/opencode /usr/local/bin/opencode

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=5003 \
    OPENCODE_SERVER_PORT=5551 \
    DATABASE_PATH=/app/data/opencode.db \
    WORKSPACE_PATH=/workspace

COPY --from=deps --chown=bun:bun /app/node_modules ./node_modules
COPY --from=builder /app/shared ./shared
COPY --from=builder /app/backend ./backend
COPY --from=builder /app/frontend/dist ./frontend/dist
COPY package.json ./

RUN mkdir -p /app/backend/node_modules/@opencode-manager \
    && ln -s /app/shared /app/backend/node_modules/@opencode-manager/shared

COPY scripts/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

RUN mkdir -p /workspace /app/data \
    && chown -R bun:bun /workspace /app/data

EXPOSE 5003 5100 5101 5102 5103

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:5003/api/health || exit 1

USER bun

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["bun", "backend/src/index.ts"]
