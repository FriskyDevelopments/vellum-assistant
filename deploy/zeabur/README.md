# Self-host: Docker Compose vs Zeabur

Two supported layouts. Pick one.

## When to use which

| Target | Layout | Why |
| --- | --- | --- |
| Single Docker host (local, VPS, dedicated node) | `docker-compose.yml` (this directory) | Shared named volumes plus `network_mode: service:assistant` match `vellum hatch --remote docker`. Unix sockets work. |
| Zeabur PaaS | `Dockerfile` + `entrypoint.sh` (this directory) | Zeabur does not deploy Compose YAML. Zeabur volumes are per-service and cannot be shared. Three Zeabur services cannot mount the same IPC volumes. |

Do not split assistant / gateway / credential-executor into three Zeabur services. Feature flags, trust rules, and signing-key bootstrap use shared socket volumes with no HTTP fallback on those paths.

## Compose topology (Docker host)

Mirrors `cli/src/lib/statefulset.ts`:

1. `volume-init` chowns UID 1001 on workspace and IPC volumes.
2. `assistant` owns the network namespace and publishes 7830 (gateway) and 7821 (assistant HTTP).
3. `gateway` and `credential-executor` use `network_mode: service:assistant` so `localhost:8090` and the Unix sockets work.

Volumes (least privilege):

| Volume | Mount | Who |
| --- | --- | --- |
| `assistant-workspace` | `/workspace` | assistant rw, gateway rw, CES ro |
| `gateway-security` | `/gateway-security` | gateway only |
| `ces-security` | `/ces-security` | CES only |
| `ces-bootstrap` | `/run/ces-bootstrap` | assistant + CES |
| `gateway-ipc` | `/run/gateway-ipc` | assistant + gateway (`gateway.sock`) |
| `assistant-ipc` | `/run/assistant-ipc` | assistant + gateway (`assistant.sock`) |

No `--privileged`, no host Docker socket, no avatar device. Video-bot / DinD is not enabled.

### Run

```bash
cd deploy/zeabur
cp .env.example .env
./gen-secrets.sh
# set at least one of ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY in .env
docker compose --env-file .env up --build -d
curl -fsS http://127.0.0.1:7830/readyz
```

Redeploy: `docker compose --env-file .env up --build -d`. Named volumes persist workspace, credentials, and IPC dirs across restarts. Destroy state: `docker compose down -v`.

## Zeabur (one service)

Build from `deploy/zeabur/Dockerfile`. Entrypoint runs `vellum hatch` then `vellum wake` as sibling OS processes in one container (same as `./setup.sh && vellum hatch` on a laptop).

Repo-root `zbpack.json` points zbpack at that Dockerfile. Template: `deploy/zeabur/template.yaml`.

### Dashboard

1. New project. Add Service, GitHub, this repo, branch `main`. Root directory: repository root (not `deploy/zeabur`).
2. Confirm `ZBPACK_DOCKERFILE_PATH=deploy/zeabur/Dockerfile` (or rely on `zbpack.json`).
3. Volumes tab: mount id `data` at `/data`.
4. Ports: HTTP `7830` (id `web`). Entrypoint also honors Zeabur `PORT` via `GATEWAY_PORT=${GATEWAY_PORT:-${PORT:-7830}}`.
5. Env (no secrets in git):

| Key | Value |
| --- | --- |
| `VELLUM_DATA_DIR` | `/data` |
| `GATEWAY_PORT` | `7830` |
| `GATEWAY_TRUST_PROXY` | `true` |
| `VELLUM_ASSISTANT_NAME` | `vellum` |
| `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` or `GEMINI_API_KEY` | set in the dashboard |
| `TELEGRAM_BOT_TOKEN` | optional |

6. Deploy. `GET https://<domain>/readyz` should succeed after the 180s start window.

### Template CLI

```bash
npx zeabur@latest template deploy -f deploy/zeabur/template.yaml
```

Connect the GitHub repo in the dashboard if the template does not bind a repo ID. Then set the LLM key on the service.

Zero-downtime restarts are off once a volume is attached. That is expected for a stateful assistant.

## Update

- Compose: rebuild images from the three official Dockerfiles, then `up -d`. Volumes stay.
- Zeabur: redeploy the git service. Volume at `/data` stays. Hatch runs only when `~/.vellum.lock.json` is missing.
