#!/usr/bin/env bash
#
# Entrypoint for the Zeabur single-container vellum-assistant image.
#
# Persists all vellum state (lockfile, instance dirs, workspace, credentials)
# under $HOME, which is pointed at the Zeabur Volume mount so it survives
# restarts. On first boot (no lockfile yet) this hatches a new local
# assistant; on subsequent boots it wakes the existing one instead.
set -euo pipefail

# Zeabur mounts the persistent Volume at this path (configured on the
# service's Volumes tab; see deploy/zeabur/README.md).
export HOME="${VELLUM_DATA_DIR:-/data}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

# Keep the assistant hermetic: never call the Vellum cloud platform from
# this container. This matches the self-hosted posture of the official
# Docker images (VELLUM_CLOUD=docker in deploy/zeabur/docker-compose.yml).
export VELLUM_DISABLE_PLATFORM="${VELLUM_DISABLE_PLATFORM:-true}"

# Zeabur's edge proxies every request. Trust X-Forwarded-For for client
# IP resolution / rate limiting instead of treating the proxy hop as the peer.
export GATEWAY_TRUST_PROXY="${GATEWAY_TRUST_PROXY:-true}"

# Production env keeps the legacy 7821/7830/6333/8090 port set and the
# canonical lockfile path. Non-prod envs get separate port blocks and an
# env-scoped lockfile; either works here, production matches the docs.
export VELLUM_ENVIRONMENT="${VELLUM_ENVIRONMENT:-production}"

# Zeabur injects PORT for HTTP ingress, but local hatch probe-allocates
# ports and ignores GATEWAY_PORT, so remap PORT 1:1 onto the container's
# loopback at boot: if PORT is set and differs from 7830, listen there too.
FORWARD_PORT="${PORT:-}"
DEFAULT_GATEWAY_PORT="7830"
FORWARD_PID=""

cleanup() {
  if [ -n "$FORWARD_PID" ] && kill -0 "$FORWARD_PID" 2>/dev/null; then
    kill "$FORWARD_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

LOCKFILE="${HOME}/.vellum.lock.json"
NAME="${VELLUM_ASSISTANT_NAME:-vellum}"

if [ -n "$FORWARD_PORT" ] && [ "$FORWARD_PORT" != "$DEFAULT_GATEWAY_PORT" ]; then
  echo "==> PORT=${FORWARD_PORT}: forwarding to gateway on ${DEFAULT_GATEWAY_PORT} at boot"
  (
    for _ in $(seq 1 120); do
      if (exec 3<>/dev/tcp/127.0.0.1/${DEFAULT_GATEWAY_PORT}) 2>/dev/null; then
        exec 3>&- 3<&-
        break
      fi
      sleep 2
    done
    exec socat "TCP-LISTEN:${FORWARD_PORT},bind=0.0.0.0,fork,reuseaddr" "TCP:127.0.0.1:${DEFAULT_GATEWAY_PORT}"
  ) &
  FORWARD_PID="$!"
fi

echo "==> HOME=${HOME} name=${NAME}"

if [ -f "$LOCKFILE" ]; then
  echo "==> Existing assistant found at ${LOCKFILE}; waking..."
  exec vellum wake --foreground
else
  echo "==> No existing assistant; hatching a new one..."
  # --keep-alive: hatchLocal's own foreground supervisor. It polls the
  # gateway health endpoint and handles SIGTERM/SIGINT gracefully, which is
  # what a container's PID 1 needs to stay up and shut down cleanly.
  exec vellum hatch --name "$NAME" --keep-alive
fi
