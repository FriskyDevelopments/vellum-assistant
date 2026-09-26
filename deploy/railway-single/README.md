<div align="center">

```
██╗   ██╗███████╗██╗     ██╗     ██╗   ██╗███╗   ███╗██████╗ ██╗   ██╗██████╗
██║   ██║██╔════╝██║     ██║     ██║   ██║████╗ ████║██╔══██╗██║   ██║██╔══██╗
██║   ██║█████╗  ██║     ██║     ██║   ██║██╔████╔██║██████╔╝██║   ██║██████╔╝
╚██╗ ██╔╝██╔══╝  ██║     ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██║   ██║██╔═══╝
 ╚████╔╝ ███████╗███████╗███████╗╚██████╔╝██║ ╚═╝ ██║██║     ╚██████╔╝██║
  ╚═══╝  ╚══════╝╚══════╝╚══════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝      ╚═════╝ ╚═╝
```

### *Three engines. One hull. Zero excuses.*

**Vellum Assistant, self-hosted on Railway — in a single container.**

![Vellum](https://img.shields.io/badge/vellum-v0.12.5-7d56f3?style=for-the-badge)
![Railway](https://img.shields.io/badge/deploy-railway-0b0d0e?style=for-the-badge&logo=railway)
![Container](https://img.shields.io/badge/containers-1-black?style=for-the-badge)
![Port](https://img.shields.io/badge/port-7830-ff4d6d?style=for-the-badge)

</div>

---

## 🎬 Act I — The Problem

Vellum ships as **three** containers — `assistant`, `gateway`, `credential-executor` — that must share **one** localhost.
Railway gives every service its own network namespace. Split them, and the gateway stares into the void, the domain hangs in provisioning, and nothing answers.

## ⚡ Act II — The Fusion

This repo doesn't compile a single line. It pulls the **official** Vellum images and fuses them into one hull:

```
                    ┌──────────────────── one Railway container ────────────────────┐
   internet ──▶ :7830│  gateway  ──▶  :7821 assistant daemon  ──▶  :8090 credential- │
                    │  (public)       (runtime, LLM, skills)        executor (CES)   │
                    │                                                                │
                    │              /data  ←  Railway volume (workspace, keys)        │
                    └────────────────────────────────────────────────────────────────┘
```

`railway-start.sh` is the director: it wires the same env the upstream StatefulSet uses, boots CES → assistant → gateway, and if any one of them falls, the whole cast restarts together.

## 🚀 Act III — Launch

1. **New service** on Railway → *Deploy from GitHub* → this repo. Railway detects the `Dockerfile`.
2. **Volume** → mount at **`/data`**. This is the assistant's memory. Skip it and every restart is amnesia.
3. **Variables** → at least one model key:

   | Variable | Required | Notes |
   |---|---|---|
   | `ANTHROPIC_API_KEY` | ✅ one LLM key | or `OPENAI_API_KEY`, `GEMINI_API_KEY`, `OPENROUTER_API_KEY`… |
   | `PORT` | recommended | `7830` — the gateway listens here |
   | `CES_SERVICE_TOKEN` / `ACTOR_TOKEN_SIGNING_KEY` / `GUARDIAN_BOOTSTRAP_SECRET` | optional | auto-generated once and kept in `/data/secrets` |

4. **Networking** → *Generate Domain* on port `7830`.
5. **Roll camera:**

   ```bash
   curl https://<your-domain>/healthz   # gateway alive
   curl https://<your-domain>/readyz    # assistant ready
   ```

## 🔁 Sequel — Upgrading

Change one line in the `Dockerfile`:

```dockerfile
ARG VELLUM_VERSION=v0.12.5
```

Commit. Railway rebuilds. Your `/data` volume carries the story forward.

## 🗂️ What lives on the volume

```
/data
├── workspace/          IDENTITY.md · SOUL.md · USER.md · NOW.md · config.json · skills/ · data/db/assistant.db
├── gateway-security/   gateway keys
├── ces-security/       credential store (encrypted)
└── secrets/            generated service tokens
```

## 🎞️ Credits

Built on [vellum-ai/vellum-assistant](https://github.com/vellum-ai/vellum-assistant) (official images `vellumai/*`).
Fused and deployed by **TheForgepup**.

<div align="center">

**— FIN —**

</div>
