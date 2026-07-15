# EvilAgent – project instructions for AI agents

## Project overview
EvilAgent is a Dockerized runtime environment for running a multi-agent AI system.
A single container ships with several agent
CLIs pre-installed (Codex, Claude Code, Hermes, OpenClaw, Google Antigravity,
Agent2Telegram, AgentsMonitor, Whisper). The container acts as the security
sandbox — agents run with approval guards disabled but are isolated from the host
via dropped capabilities, resource limits, and no Docker socket access. Tool
binaries live in the image; all credentials and working data persist in named
Docker volumes. Which tools are installed is controlled by `INSTALL_*` flags in
`.env`. Keeping agents alive 24/7 is AgentsMonitor's job, not this project's: the
container runs cron, and `agentsmon setup` installs an `@reboot` + every-minute
crontab. See [README.md](README.md) for full setup and usage documentation.

## Scope of the sandbox — do not overstate it
The container contains **host damage**, not **data**. All agents share one home
directory as uid 1000, so each can read every other's credentials, and outbound
network access is unrestricted by default. A prompt-injected agent can exfiltrate
credentials without escaping the container. Keep documentation and comments
honest about this distinction; do not describe the container as protecting
secrets.

## Keep it simple
This is a container with pre-installed tools, not a platform. Prefer removing a
knob over adding one, and default to the behaviour most users want instead of
making it configurable. Specifically:
- **No API keys in `.env.example`.** Every tool authenticates interactively and
  stores credentials in its own volume; auth is set up once per tool.
- **No version pins or checksums in configuration.** Tools install at `@latest`.
- **Don't reimplement what a bundled tool already does.** Supervising agents is
  AgentsMonitor's job; the container just provides cron so it can do it the
  standard way. Prefer giving a tool what it expects over writing our own.
- New config options need a real use case, not a hypothetical one.

## Conventions
- All configuration goes through `src/.env` (see `.env.example`), never hardcoded.
- Shell scripts live in `src/scripts/` and must pass `shellcheck` (`make lint`).
- Remote install scripts are downloaded to a file and then executed — never pipe
  `curl` straight into a shell, which would run a half-downloaded script if the
  connection drops.
- Codex and Claude Code install via npm and are **required**: if an enabled one
  fails, the build fails. The third-party webinar installers are best-effort.
- The root-run entrypoint needs `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, and
  `SETGID`; `/home/agent` is mode 0750, so without `DAC_OVERRIDE` root cannot
  even traverse it and the container fails to boot. Agents themselves run as
  uid 1000 with an empty capability set.

## Language
All output must be in **English**: code comments, commit messages, documentation,
shell output strings, and all other text.

## Git discipline
- **Never stage or commit changes** unless the user explicitly asks you to.
- When asked to commit, always write a **meaningful English commit message**
  that describes *why* the change was made (not just what). Use the imperative
  mood and keep the subject line under 72 characters.
