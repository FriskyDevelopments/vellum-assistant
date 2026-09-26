#!/usr/bin/env bash
# Fill CES_SERVICE_TOKEN, ACTOR_TOKEN_SIGNING_KEY, and GUARDIAN_BOOTSTRAP_SECRET
# in deploy/zeabur/.env if they are empty. Does not print secret values.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${DIR}/.env"
EXAMPLE="${DIR}/.env.example"

if [ ! -f "$ENV_FILE" ]; then
  cp "$EXAMPLE" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

hex32() {
  openssl rand -hex 32
}

set_if_empty() {
  local key="$1"
  local current
  current="$(grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
  if [ -z "$current" ]; then
    local value
    value="$(hex32)"
    if grep -qE "^${key}=" "$ENV_FILE"; then
      awk -v k="$key" -v v="$value" 'BEGIN{FS=OFS="="} $1==k {$0=k"="v} {print}' "$ENV_FILE" > "${ENV_FILE}.tmp"
      mv "${ENV_FILE}.tmp" "$ENV_FILE"
    else
      printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
    fi
    echo "set ${key} (length $(printf '%s' "$value" | wc -c | tr -d ' '))"
  else
    echo "${key} already set (length ${#current})"
  fi
}

set_if_empty CES_SERVICE_TOKEN
set_if_empty ACTOR_TOKEN_SIGNING_KEY
set_if_empty GUARDIAN_BOOTSTRAP_SECRET
chmod 600 "$ENV_FILE"
echo "wrote ${ENV_FILE}"
