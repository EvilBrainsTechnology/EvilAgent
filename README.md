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
| **Whisper** (faster-whisper) | voice control (Voice2Text) | `voice2text` |

---

## Security model – read this first

The webinar recommends running agents directly on a server with **all safety guards
disabled** (`--dangerously-skip-permissions`, `--dangerously-bypass-approvals-and-sandbox`,
`sudo NOPASSWD` on `reboot`/`dd`, and a master agent with full server control
connected to Telegram). This is convenient, but **dangerous** on a bare server —
a misbehaving agent or a successful prompt-injection attack gains full control over
the machine.

**This project's approach: the container is the security boundary.**

### What this actually protects you from

The container contains **damage to the host**:

- ✅ runs as **unprivileged user `agent`** (not root),
- ✅ **`no-new-privileges`** + **all Linux capabilities dropped** (except the minimum the entrypoint needs) → agents hold no capabilities at all; `sudo` is intentionally blocked,
- ✅ **no Docker socket**, **no host network**, **no `privileged` mode**, **no host bind-mounts** → agent cannot touch the host filesystem or control Docker,
- ✅ **CPU / RAM / PID limits** → a runaway or fork-bombing agent cannot take down the machine,
- ✅ **no credentials in the image or in git** — tools log in interactively and store their credentials in volumes,
- ✅ tool binaries in the image, data in separate **volumes** (easy to back up and audit).

If an agent goes wrong, you rebuild the container and restore from backup. Your
host stays intact.

### What it does NOT protect you from

Be clear-eyed about this — the container boundary contains **host damage, not data**:

- ❌ **Agents can read each other's credentials.** Every agent runs as the same
  uid 1000 and shares one home directory, so any agent — running with approval
  guards disabled — can read `~/.codex`, `~/.claude`, and the SSH keys in
  `~/.ssh`. A successful prompt injection does not need to escape the container
  to hurt you.
- ❌ **Outbound network access is unrestricted by default.** The container can
  reach the whole internet, your **LAN**, and any host service listening on
  `0.0.0.0` (via the Docker gateway, typically `172.17.0.1`). Nothing stops an
  agent from sending those credentials somewhere.
- ❌ **The agents' own actions are not sandboxed.** That's the point — they run
  with `--dangerously-*`. Everything inside the container is fair game to them.

**In short: this is a good containment story for a compromised agent wrecking a
machine, and no containment at all for a compromised agent stealing credentials.**
Plan accordingly:

- Give agents accounts with **minimal permissions** — never your primary account.
  Assume any credential inside the container may leak.
- Run the container on a **dedicated server/VM**, not on your workstation and not
  on a network with sensitive internal services.
- Restrict egress with a **proxy allowlist** — see *Network hardening* below.
  This is the single highest-value hardening step and it is not enabled by default.
- Keep API keys out of `.env` where you can. Interactive login stores credentials
  in a volume, which at least keeps them out of the process environment and out
  of `docker inspect`. It does not hide them from the agents themselves.

---

## Quick start

Prerequisites: **Docker** + **Docker Compose** on the host.

```bash
# 1) Configuration
cd src
cp .env.example .env        # no keys needed – tools authenticate interactively
                            # INSTALL_* flags choose which tools to install (default: all)

# 2) Build the image (downloads and installs all tools)
docker compose build        # or: make build

# 3) Start (runs in the background, restart-policy: unless-stopped)
docker compose up -d        # or: make up

# 4) Enter the container as agent
make shell                  # or: docker compose exec -u agent evilagent bash -l
```

> All `make` and `docker compose` commands must be run from the `src/` directory.
> From the project root use `make -C src <target>` or `cd src` once at the start of a session.

After start the container brings up the shared tmux session `main` and starts any
agents you configured via `AUTOSTART_*` (see *Running agents 24/7*). With no
autostart configured, you **configure and start agents manually** — see below.

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
as `disabled` rather than missing, so a deliberately-skipped tool never looks
like a broken build.

---

## First-time tool setup (manual, after first start)

Enter the container (`make shell`) and set up what you need. **Each tool handles
its own authentication** and saves credentials to a persistent volume, so
**you only need to do this once** — there are no API keys to put in `.env`.

### Codex (meta-agent)
```bash
codex                      # interactive login (device flow / API key)
# run as a persistent agent inside tmux:
tmux new -s master 'codex --dangerously-bypass-approvals-and-sandbox'
#   detach: Ctrl+B then D        reattach: tmux attach -t master
```
> `--dangerously-*` is safe for your **host** here – the boundary is the
> container. It is not safe for your **credentials**; see the security model.

### Claude Code
```bash
claude                     # interactive login (subscription or API key)
claude --dangerously-skip-permissions
```

### Agent2Telegram (connect Codex to Telegram)
```bash
agent2telegram connect     # follow the prompts; create the bot with @BotFather
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
> **Subscription does not work on servers.** Log in with a Google Cloud project,
> or add `GEMINI_API_KEY=...` to `.env` yourself if you want API mode.
> Google Cloud offers $300 of free credit for 3 months.

### Voice control (Whisper)
The container has no microphone. Copy audio into `~/workspace` and transcribe it:
```bash
voice2text ~/workspace/recording.m4a small cs
```
Then pass the text to an agent. Models are downloaded once to `~/.cache/whisper`.
For languages other than English, ElevenLabs Scribe via their API generally
transcribes better than local Whisper models.

---

## Running agents 24/7

Interactive setup is one-time, but a hand-started agent lives only as long as the
container process does. A restart, a host reboot, or an OOM kill would otherwise
bring the container back **healthy and empty** — with no agents running at all.

Once a tool is configured, list it in `.env` and it starts with the container:

```bash
AUTOSTART_MASTER=codex --dangerously-bypass-approvals-and-sandbox
AUTOSTART_CLAUDE=claude --dangerously-skip-permissions
```

Each `AUTOSTART_<NAME>` becomes a tmux window named `<name>` in the shared
session `main`:

```bash
make attach            # attach to the session (Ctrl+B then W lists windows)
                       # detach with Ctrl+B then D
```

Restart the container to apply changes: `docker compose up -d`.

### Health and recovery

The container healthcheck watches **exactly these agents**. If one exits, the
window is kept (`remain-on-exit`) so you can read its last output, and the
container is reported **unhealthy**:

```bash
docker compose ps                       # STATUS column shows (unhealthy)
docker inspect --format '{{json .State.Health}}' evilagent | jq
```

Docker's `restart: unless-stopped` does not act on health status. For automatic
recovery either configure **AgentsMonitor** (which is what it's for) or run a
watchdog such as `willfarrell/autoheal` alongside the container.

### Agent logs (audit trail)

Every autostarted agent's output is captured to a log file — worth having, since
these agents run with approvals disabled and you would otherwise have no record
of what they did:

```bash
make agent-logs                                    # list logs
make shell
tail -f ~/.local/state/evilagent/logs/master.log   # follow one agent
```

Logs live in the `localstate` volume and are included in backups. They are **not
rotated** — if you run agents continuously, add a `logrotate` entry or truncate
them periodically.

---

## Data persistence

Everything important lives in named Docker **volumes** and **survives restarts and
image rebuilds**:

| Volume | Contents |
|---|---|
| `codex`, `claude`, `hermes`, `openclaw`, `agent2telegram`, `agentsmon` | per-tool config and credentials |
| `config` | XDG config, `gcloud` |
| `cache` | downloaded Whisper models, etc. |
| `localstate` | agent logs (`~/.local/state`) |
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

A failed backup **aborts** the update rather than rebuilding on a backup that
didn't happen. Override deliberately with `FORCE=1 ./scripts/update.sh`.

Manual equivalent:
```bash
docker compose build --pull && docker compose up -d
```

All tool sources are defined in [`src/scripts/install-tools.sh`](src/scripts/install-tools.sh) –
update URLs in one place. Tools install at their latest version; to refresh them
without a full rebuild:
```bash
make tools     # runs install-tools.sh inside the running container
```

> `make tools` installs into the **running container**, not the image. Those
> updates are lost the next time the container is recreated (`docker compose up -d`
> after a build). Use it for a quick fix; use `make update` to make it stick.

---

## Backup and restore

```bash
make backup                                      # -> src/backups/<timestamp>/agent-data.tar.gz
./src/scripts/restore.sh src/backups/2026.../agent-data.tar.gz
```

Backs up all config, credentials, agent logs, and `workspace` into a single
archive. The backup **verifies the archive** and fails loudly if anything went
wrong — it never reports success for an archive it couldn't read. `restore.sh`
accepts both absolute and relative paths.

> Backups are written to `src/backups/` and are gitignored.

---

## Common commands (`make help`)

| Command | Description |
|---|---|
| `make up` / `make down` | start / stop (volumes kept) |
| `make shell` | shell as `agent` |
| `make root-shell` | shell as `root` (administration) |
| `make attach` | attach to shared tmux session `main` |
| `make logs` | follow container logs |
| `make agent-logs` | list captured agent output logs |
| `make health` | show tool availability |
| `make tools` | reinstall / update tools |
| `make update` | full update |
| `make backup` | back up agent data |
| `make lint` | run shellcheck + hadolint (same checks as CI) |

---

## Network hardening (recommended, not default)

Agents need outbound internet access for model APIs, so the network cannot be
fully closed — but leaving it wide open means any agent can exfiltrate every
credential it can read, which is all of them. This is the most valuable hardening
step available.

Place an **egress proxy** (e.g. Squid with a domain allowlist) in front of the
container and point the agents at it via `HTTP_PROXY` / `HTTPS_PROXY` in `.env`.
An allowlist of just your model API endpoints (`api.openai.com`,
`api.anthropic.com`, …) removes most of the exfiltration surface.

Full network isolation (`networks: internal: true`) is available as a
commented-out option in [`src/docker-compose.yml`](src/docker-compose.yml) — usable
only for agents that do not need internet access.

---

## Development

```bash
make lint          # shellcheck + hadolint + compose validation
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs the same linters, builds
the image with the reliable tools only, and smoke-tests that the container boots,
that `evilagent-health` respects the `INSTALL_*` flags, that an autostarted agent
runs, that the healthcheck goes red when that agent dies, and that a backup
produces a verifiable archive.

---

## Troubleshooting

- **Tool shows `MISS` after build.** The installers for Agent2Telegram, Hermes,
  OpenClaw, AgentsMonitor, and Antigravity come from the webinar and their URLs
  may differ or be temporarily unavailable. Those are best-effort, so the build
  continues without them. Verify/update the URLs in
  [`src/scripts/install-tools.sh`](src/scripts/install-tools.sh) and run `make tools`.
  Codex and Claude Code install via npm and are **required** — if one of them
  fails, the build fails rather than handing you an image without it.
- **Container is `unhealthy`.** An autostarted agent exited. Find out which:
  `docker inspect --format '{{json .State.Health}}' evilagent | jq`, then read its
  last output — the dead tmux window is kept on purpose (`make attach`, `Ctrl+B` `W`)
  and its log is in `~/.local/state/evilagent/logs/`.
- **`sudo` doesn't work inside the container.** Correct — it is intentionally
  blocked by `no-new-privileges`. Use `make root-shell` for administration, or
  add permanent changes to `src/Dockerfile` and rebuild.
- **Agent can't access a file from the host.** The container has no host
  bind-mounts (by design, for security). Copy files into the `workspace` volume:
  `docker compose cp myfile evilagent:/home/agent/workspace/`.
- **First start is slow.** The entrypoint takes ownership of freshly created
  volumes. It only does this for volumes whose ownership is actually wrong, so
  this cost is paid once per volume, not on every start.

---

## Project structure

```
.
├── README.md
├── LICENSE
├── .gitignore
├── .gitattributes
├── .github/
│   └── workflows/
│       └── ci.yml                # lint + build + smoke test
└── src/
    ├── Dockerfile                # image: Ubuntu + Node + Python + tools
    ├── docker-compose.yml        # service, security, volumes, limits
    ├── .env.example              # configuration template
    ├── Makefile                  # shortcuts
    └── scripts/
        ├── install-tools.sh      # install/update CLI tools
        ├── entrypoint.sh         # volume init + autostart agents + drop to agent user
        ├── health.sh             # tool inventory (`make health`)
        ├── container-health.sh   # Docker healthcheck probe
        ├── voice2text.sh         # Whisper audio -> text transcription
        ├── update.sh             # backup + rebuild + refresh
        ├── backup.sh             # back up agent data
        └── restore.sh            # restore from backup
```

---

## License

[MIT](LICENSE).
