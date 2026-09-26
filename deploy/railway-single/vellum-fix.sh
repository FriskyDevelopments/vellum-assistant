#!/usr/bin/env bash
# vellum-fix.sh — run on your Mac (Warp). Secrets are read silently and never printed.
# 1) pushes clean Dockerfile + railway-start.sh to TheForgepup/Vellumpup (fixes the duplicated script, adds cloudflared)
# 2) sets TUNNEL_TOKEN on Railway (and optionally a model key) with the Railway CLI
# 3) shows your local Vellum inference settings (no keys) so you can mirror them
set -euo pipefail

REPO="${REPO:-https://github.com/TheForgepup/Vellumpup.git}"
RAILWAY_PROJECT="${RAILWAY_PROJECT:-grand-joy}"
RAILWAY_SERVICE="${RAILWAY_SERVICE:-Vellumpup}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say(){ printf '\n\033[1;33m▸ %s\033[0m\n' "$*"; }
need(){ command -v "$1" >/dev/null || { echo "Missing: $1 ($2)"; exit 1; }; }
need git "xcode-select --install"
need railway "brew install railway"

# ── 1. Repo ────────────────────────────────────────────────
say "Cloning $REPO"
git clone --depth 1 "$REPO" "$WORK/repo" >/dev/null
cd "$WORK/repo"

cat > Dockerfile <<'VELLUM_EOF'
# Vellum Assistant — single-container build for Railway.
# Railway can't share localhost between services, so the three official
# images (gateway, credential-executor, assistant) are merged into one and
# supervised by railway-start.sh. Bump VELLUM_VERSION to upgrade.
ARG VELLUM_VERSION=v0.12.5

FROM vellumai/vellum-gateway:${VELLUM_VERSION} AS gateway
FROM vellumai/vellum-credential-executor:${VELLUM_VERSION} AS ces

FROM vellumai/vellum-assistant:${VELLUM_VERSION}
USER root

COPY --from=gateway /app /opt/gateway-app
COPY --from=ces /app /opt/ces-app
COPY railway-start.sh /usr/local/bin/railway-start
RUN chmod +x /usr/local/bin/railway-start

# Cloudflare Tunnel connector (runs when TUNNEL_TOKEN is set).
RUN arch="$(dpkg --print-architecture)" && \
    curl -fsSL -o /usr/local/bin/cloudflared \
      "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" && \
    chmod +x /usr/local/bin/cloudflared && cloudflared --version

ENV IS_CONTAINERIZED=true \
    DEBUG_STDOUT_LOGS=1 \
    VELLUM_CLOUD=docker \
    VELLUM_DATA_DIR=/data \
    GATEWAY_PORT=7830 \
    RUNTIME_HTTP_PORT=7821

EXPOSE 7830
CMD ["/usr/local/bin/railway-start"]
VELLUM_EOF

cat > railway-start.sh <<'VELLUM_EOF'
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
VELLUM_EOF
chmod +x railway-start.sh

grep -c "set -euo pipefail" railway-start.sh | grep -qx 1 || { echo "railway-start.sh still duplicated, aborting"; exit 1; }
if git diff --quiet; then
  say "Repo already clean — nothing to push"
else
  git add Dockerfile railway-start.sh
  git commit -qm "Fix duplicated start script; add cloudflared tunnel connector"
  say "Pushing"
  git push -q origin HEAD
fi

# ── 2. Railway variables ───────────────────────────────────
say "Railway: linking $RAILWAY_PROJECT / $RAILWAY_SERVICE"
railway whoami >/dev/null 2>&1 || railway login
railway link --project "$RAILWAY_PROJECT" --service "$RAILWAY_SERVICE" >/dev/null

if [ -z "${TUNNEL_TOKEN:-}" ]; then
  printf "Paste TUNNEL_TOKEN (Zero Trust → Tunnels → vellumpup-railway), hidden: "
  read -rs TUNNEL_TOKEN; echo
fi
[ -n "$TUNNEL_TOKEN" ] && railway variables --service "$RAILWAY_SERVICE" --set "TUNNEL_TOKEN=$TUNNEL_TOKEN" --skip-deploys >/dev/null && echo "TUNNEL_TOKEN set"

# Optional: an env-driven model key (Vellum reads these directly).
for k in LITELLM_API_KEY OPENROUTER_API_KEY ANTHROPIC_API_KEY; do
  if [ -n "${!k:-}" ]; then
    printf "Found %s in this shell. Send it to Railway? [y/N] " "$k"; read -r a
    [ "$a" = "y" ] && railway variables --service "$RAILWAY_SERVICE" --set "$k=${!k}" --skip-deploys >/dev/null && echo "$k set"
  fi
done

say "Redeploying"
railway redeploy --service "$RAILWAY_SERVICE" --yes >/dev/null && echo "Redeploy triggered"

# ── 3. Local Vellum inference settings (no secrets) ────────
CFG="$HOME/.vellum/workspace/config.json"
if [ -f "$CFG" ] && command -v jq >/dev/null; then
  say "Your local Vellum inference settings (keys excluded)"
  jq 'walk(if type=="object" then with_entries(select(.key|test("key|token|secret|password";"i")|not)) else . end)
      | [paths(type!="object" and type!="array") as $p | {path:($p|map(tostring)|join(".")),value:getpath($p)}]
      | map(select(.path|test("provider|model|base|inference|llm";"i")))' "$CFG"
else
  echo "(no $CFG or jq missing — brew install jq)"
fi

cat <<'NEXT'

Next, in the Railway Vellum (vellum.friskydev.com once the tunnel is up):
  Settings → Inference → openai-compatible
    Base URL : https://api.meta.ai/v1   (or your metered gateway /v1)
    Model    : muse-spark-1.3
    Key      : paste your Muse / gateway key
NEXT
