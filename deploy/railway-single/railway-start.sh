#!/usr/bin/env bash
# Runs credential-executor, assistant daemon and gateway in one container,
# mirroring the env of the official 3-container StatefulSet. Exits when any
# process dies so Railway restarts the whole group.
set -euo pipefail

DATA="${VELLUM_DATA_DIR:-/data}"
mkdir -p "$DATA/workspace" "$DATA/gateway-security" "$DATA/ces-security" "$DATA/secrets" \
         /run/ces-bootstrap /run/assistant-ipc /run/gateway-ipc
chmod 777 /run/ces-bootstrap

# Persist state on the Railway volume via the paths the images expect.
for pair in "workspace:/workspace" "gateway-security:/gateway-security" "ces-security:/ces-security"; do
  src="$DATA/${pair%%:*}"; dst="${pair#*:}"
  if [ ! -L "$dst" ]; then rm -rf "$dst"; ln -s "$src" "$dst"; fi
done

# Shared secrets: env var wins, otherwise generate once and keep on the volume.
secret() {
  local name="$1" file="$DATA/secrets/$1"
  if [ -n "${!name:-}" ]; then return; fi
  [ -s "$file" ] || openssl rand -hex 32 > "$file"
  export "$name=$(cat "$file")"
}
secret CES_SERVICE_TOKEN
secret ACTOR_TOKEN_SIGNING_KEY
secret GUARDIAN_BOOTSTRAP_SECRET

# Railway injects PORT; the gateway is the public entrypoint.
export GATEWAY_PORT="${PORT:-${GATEWAY_PORT:-7830}}"
export RUNTIME_HTTP_PORT="${RUNTIME_HTTP_PORT:-7821}"
export VELLUM_WORKSPACE_DIR=/workspace
export VELLUM_BACKUP_DIR=/workspace/.backups
export VELLUM_BACKUP_KEY_PATH=/workspace/.backup.key
export CES_CREDENTIAL_URL=http://localhost:8090
export CES_BOOTSTRAP_SOCKET_DIR=/run/ces-bootstrap
export GATEWAY_IPC_SOCKET_DIR=/run/gateway-ipc
export ASSISTANT_IPC_SOCKET_DIR=/run/assistant-ipc
export ASSISTANT_HOST=localhost
export GATEWAY_SECURITY_DIR=/gateway-security

echo "[railway] starting credential-executor"
( cd /opt/ces-app/credential-executor && \
  CES_MODE=managed CES_HEALTH_PORT=8090 CREDENTIAL_SECURITY_DIR=/ces-security \
  exec bun run src/main.ts ) &

echo "[railway] starting assistant daemon on :$RUNTIME_HTTP_PORT"
( cd /app/assistant && RUNTIME_HTTP_HOST=127.0.0.1 exec /app/assistant/docker-entrypoint.sh ) &

echo "[railway] starting gateway on :$GATEWAY_PORT"
( cd /opt/gateway-app/gateway && exec bun --smol run src/index.ts ) &

if [ -n "${TUNNEL_TOKEN:-}" ]; then
  echo "[railway] starting cloudflared tunnel"
  cloudflared tunnel --no-autoupdate run &
fi

wait -n
echo "[railway] a process exited; stopping container" >&2
exit 1
