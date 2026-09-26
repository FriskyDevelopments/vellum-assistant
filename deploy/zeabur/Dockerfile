# syntax=docker/dockerfile:1.20@sha256:26147acbda4f14c5add9946e2fd2ed543fc402884fd75146bd342a7f6271dc1d
#
# Single-container image for self-hosting vellum-assistant on Zeabur.
#
# Zeabur volumes are scoped to a single service and cannot be shared between
# services, but the official 3-container split (assistant/Dockerfile,
# gateway/Dockerfile, credential-executor/Dockerfile) relies on Unix-domain
# sockets on *shared* volumes for inter-container IPC. Instead, this image
# runs the CLI's plain "local" hatch mode (the same code path used for a
# `./setup.sh && vellum hatch` install on a laptop or VPS) so the daemon,
# gateway, and credential-executor run as sibling OS processes inside ONE
# container, sharing one filesystem. No cross-container volume sharing is
# required. See deploy/zeabur/README.md for details and trade-offs.
FROM debian:trixie-slim@sha256:4ffb3a1511099754cddc70eb1b12e50ffdb67619aa0ab6c13fcd800a78ef7c7a

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    unzip \
    xz-utils \
    python3 \
    make \
    g++ \
    sqlite3 \
    procps \
    tini \
    socat \
    && rm -rf /var/lib/apt/lists/*

# Pinned bun version — keep in sync with .tool-versions.
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v1.3.11"
ENV BUN_INSTALL="/root/.bun"
ENV PATH="${BUN_INSTALL}/bin:${PATH}"

# Full monorepo source needed to run the CLI's local (non-Docker) hatch mode:
# cli/, assistant/, gateway/, credential-executor/, packages/*, meta/, plus
# every workspace member's package.json for the frozen-lockfile install.
# See .dockerignore for exactly what's allowed into this context.
COPY . .

# Install the workspace and link the CLI globally, mirroring setup.sh's
# steps (skipping git hooks / shell completions / rc-file edits, which don't
# apply in a container). --ignore-scripts matches the official Dockerfiles
# and avoids triggering postinstall browser downloads etc. during the build.
# The generated bundled-plugin-packages.json is git-ignored, so run the
# generator explicitly (mirrors assistant/Dockerfile) — the daemon crashes
# on startup without it.
RUN bun install --ignore-scripts \
    && bun run meta/sync-bundled-copies.ts --plugins-only \
    && bun run assistant/scripts/generate-bundled-plugin-packages.ts \
    && for dir in cli gateway assistant credential-executor; do \
         (cd "$dir" && bun link); \
       done \
    && (cd meta && bun link @vellumai/cli @vellumai/assistant @vellumai/vellum-gateway @vellumai/credential-executor) \
    && (cd meta && bun link)

COPY deploy/zeabur/entrypoint.sh /usr/local/bin/vellum-zeabur-entrypoint.sh
RUN chmod +x /usr/local/bin/vellum-zeabur-entrypoint.sh

# The gateway is the only service that needs public ingress (public ingress
# is gateway-only; see ARCHITECTURE.md's cross-cutting invariants). Local
# hatch probe-allocates the legacy 7830 port, and the entrypoint forwards
# Zeabur's $PORT to it at boot, so both are exposed here for documentation.
EXPOSE 7830

HEALTHCHECK --interval=30s --timeout=5s --start-period=180s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:7830/readyz" >/dev/null || exit 1

# tini reaps the entrypoint's background socat forwarder so nothing lingers
# as a zombie; vellum hatch/wake --keep-alive/--foreground remains PID 1's
# supervisor for the daemon/gateway/CES sibling processes.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/vellum-zeabur-entrypoint.sh"]
