# EvilAgent

Docker runtime environment for a **multi-agent system** based on the webinar
by Petr Ludwig: *"AI Agents as the Future of Work"*. A single isolated container
ships with all tools pre-installed:

| Tool | Role | Command |
|---|---|---|
| **Codex** (OpenAI) | meta-agent, manages other agents | `codex` |
| **Claude Code** (Anthropic) | development / agent | `claude` |
| **Google Antigravity** | agent (API-only on servers) | `agy` |
| **Hermes Agent** (Nous Research) | agent + gateway | `hermes` |
| **OpenClaw** | full-stack agent solution | `openclaw` |
| **Agent2Telegram** | agent ↔ Telegram bridge | `agent2telegram` |
| **AgentsMonitor** | monitoring + automatic recovery | `agentsmon` |
| **Whisper** (OpenAI / faster-whisper) | voice control (Voice2Text) | `voice2text` |

---

## Security model – read this first

The webinar recommends running agents directly on a server with **all safety guards
disabled** (`--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`,
`sudo NOPASSWD` on `reboot`/`dd`, and a master agent with full server control
connected to Telegram). This is convenient, but **dangerous** on a bare server —
a misbehaving agent or a successful prompt-injection attack gains full control over
the machine.

**This project's approach: the container is the security boundary.**
Agents inside can run unconstrained because they are enclosed in isolation:

- ✅ runs as **unprivileged user `agent`** (not root),
- ✅ **`no-new-privileges`** + **all Linux capabilities dropped** (except the minimum needed) → cannot escalate to root inside; `sudo` is intentionally blocked,
- ✅ **no Docker socket**, **no host network**, **no `privileged` mode** → agent cannot reach the host or other containers,
- ✅ **CPU / RAM / PID limits** → a runaway or fork-bombing agent cannot take down the machine,
- ✅ **secrets (API keys, tokens) only in `.env`**, never in the image or git,
- ✅ dedicated **bridge network** isolated from the host,
- ✅ tool binaries in the image, data in separate **volumes** (easy to back up and audit).

**What this means in practice:** agents can operate fully automated (24/7, via
Telegram, with approval bypass), but the worst that can happen is damage to the
container's contents — which you can rebuild at any time and restore from a backup.

> **Additional recommendations:** run the container on a dedicated server/VM, give
> agents tokens with minimal permissions (not your primary account), and mount
> sensitive repositories read-only. Outbound network access can be further restricted
> (see *Network hardening* below).

---

## Quick start

Prerequisites: **Docker** + **Docker Compose** on the host.

```bash
# 1) Configuration
cp .env.example .env        # keys are optional – most tools authenticate interactively
                            # INSTALL_* flags choose which tools to install (default: all)

# 2) Build the image (downloads and installs all tools)
docker compose build        # or: make build

# 3) Start (runs in the background, restart-policy: unless-stopped)
docker compose up -d        # or: make up

# 4) Enter the container as agent
make shell                  # or: docker compose exec -u agent evilagent bash -l
```

After start the container simply keeps the tmux session `main` alive. You
**configure and start agents manually** — see below.

### Choosing which tools to install

You don't have to install (and configure) everything. Each tool has an
`INSTALL_*` flag in `.env` (default `true`):

```bash
# example: only Claude Code + Telegram bridge + monitoring
INSTALL_CODEX=false
INSTALL_CLAUDE_CODE=true
INSTALL_AGENT2TELEGRAM=true
INSTALL_HERMES=false
INSTALL_OPENCLAW=false
INSTALL_AGENTSMONITOR=true
INSTALL_ANTIGRAVITY=false
INSTALL_WHISPER=false
```

The flags apply at image build time — after changing them, run
`docker compose build && docker compose up -d` (or `make update`).
`make health` shows which tools are present; disabled tools are listed
as `disabled` instead of missing.

---

## First-time tool setup (manual, after first start)

Enter the container (`make shell`) and set up what you need. Credentials and
config are saved to persistent volumes, so **you only need to do this once**.

### Codex (meta-agent)
```bash
codex                      # interactive login (device flow / API key)
# run as a persistent agent inside tmux:
tmux new -s master 'codex --dangerously-bypass-approvals-and-sandbox'
#   detach: Ctrl+B then D        reattach: tmux attach -t master
```
> `--dangerously-*` is safe here – the boundary is the container, not your machine.

### Agent2Telegram (connect Codex to Telegram)
```bash
# add TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID to .env (from @BotFather), then:
agent2telegram connect
```

### Claude Code
```bash
claude                     # login (subscription) or set ANTHROPIC_API_KEY in .env
claude --dangerously-skip-permissions
```

### Hermes Agent
```bash
hermes config set API_SERVER_KEY "$(openssl rand -hex 24)"
hermes config set API_SERVER_ENABLED true
nohup hermes gateway run --replace > ~/hermes.log 2>&1 &
```

### OpenClaw
```bash
openclaw onboard           # copy the code to a browser, paste the URL back
nohup openclaw gateway > ~/openclaw.log 2>&1 &
```

### AgentsMonitor (monitoring + automatic recovery)
```bash
agentsmon add              # register running agents for monitoring
agentsmon new              # create a new monitored agent
```

### Google Antigravity
```bash
agy --dangerously-skip-permissions
```
> **Subscription does not work on servers.** Use a Google Cloud project or set
> `GEMINI_API_KEY` in `.env`. Google Cloud offers $300 of free credit for 3 months.

### Voice control (Whisper)
The container has no microphone. Copy audio into `~/workspace` and transcribe it:
```bash
voice2text ~/workspace/recording.m4a small cs
```
Then pass the text to an agent. Models are downloaded once to `~/.cache/whisper`.
For best results with languages other than English, consider **ElevenLabs Scribe**
via the API (`ELEVENLABS_API_KEY` in `.env`; also supports Text2Voice).

---

## Data persistence

Everything important lives in named Docker **volumes** and **survives restarts and
image rebuilds**:

| Volume | Contents |
|---|---|
| `codex`, `claude`, `hermes`, `openclaw`, `agent2telegram`, `agentsmon` | per-tool config and credentials |
| `config` | XDG config, `gcloud` |
| `cache` | downloaded Whisper models, etc. |
| `ssh` | agent SSH keys |
| `workspace` | working directory / repositories / agent data |

Tool binaries are in the image, **not** in volumes. This means `docker compose down`
**does not delete data** and an image update does not overwrite credentials.

> To explicitly delete all data: `docker compose down -v` (irreversible).

---

## Updating

Tools and the OS are updated by **rebuilding the image**; volume data is preserved:

```bash
make update
# = backup  →  docker compose build --pull  →  up -d  →  tool refresh inside container
```

Manual equivalent:
```bash
docker compose build --pull && docker compose up -d
```

All tool sources are defined in [`scripts/install-tools.sh`](scripts/install-tools.sh) –
update URLs and versions in one place. To refresh tools without a full rebuild:
```bash
make tools     # runs install-tools.sh inside the running container
```

---

## Backup and restore

```bash
make backup                                      # -> backups/<date>/agent-data.tar.gz
./scripts/restore.sh backups/2026.../agent-data.tar.gz
```
Backs up all config, credentials, and `workspace` into a single archive.

---

## Common commands (`make help`)

| Command | Description |
|---|---|
| `make up` / `make down` | start / stop (volumes kept) |
| `make shell` | shell as `agent` |
| `make root-shell` | shell as `root` (administration) |
| `make attach` | attach to shared tmux session `main` |
| `make logs` | follow container logs |
| `make health` | show tool availability |
| `make tools` | reinstall / update tools |
| `make update` | full update |
| `make backup` | back up agent data |

---

## Network hardening (optional, advanced)

Agents need outbound internet access for model APIs, so the network cannot be
fully closed. To restrict outbound traffic to allowed domains, place an
**egress proxy** (e.g. Squid with an allowlist) in front of the container and
set `HTTP(S)_PROXY`. Full network isolation (`networks: internal: true`) is
available as a commented-out option in `docker-compose.yml` — usable only for
agents that do not need internet access.

---

## Troubleshooting

- **Tool shows `MISS` after build.** The installers for Agent2Telegram, Hermes,
  OpenClaw, AgentsMonitor, and Antigravity come from the webinar and their URLs
  may differ or be temporarily unavailable. The build **intentionally lets them
  fail silently** so other tools still install. Verify/update the URLs in
  [`scripts/install-tools.sh`](scripts/install-tools.sh) and run `make tools`.
  Codex and Claude Code install via npm and should always be available.
- **`sudo` doesn't work inside the container.** Correct — it is intentionally
  blocked by `no-new-privileges`. Use `make root-shell` for administration, or
  add permanent changes to the `Dockerfile` and rebuild.
- **Agent can't access a file from the host.** The container has no host
  bind-mounts (by design, for security). Copy files into the `workspace` volume:
  `docker compose cp myfile evilagent:/home/agent/workspace/`.

---

## Project structure

```
.
├── Dockerfile                 # image: Ubuntu + Node + Python + tools
├── docker-compose.yml         # service, security, volumes, limits
├── .env.example               # secrets/config template
├── Makefile                   # shortcuts
├── README.md
└── scripts/
    ├── install-tools.sh       # install/update CLI tools (build-time and runtime)
    ├── entrypoint.sh          # volume init + drop to agent user
    ├── voice2text.sh          # Whisper audio -> text transcription
    ├── update.sh              # backup + rebuild + refresh
    ├── backup.sh              # back up agent data
    └── restore.sh             # restore from backup
```
