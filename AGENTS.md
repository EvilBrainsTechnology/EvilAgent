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
`.env`. See [README.md](README.md) for full setup and usage documentation.

## Language
All output must be in **English**: code comments, commit messages, documentation,
shell output strings, and all other text.

## Git discipline
- **Never stage or commit changes** unless the user explicitly asks you to.
- When asked to commit, always write a **meaningful English commit message**
  that describes *why* the change was made (not just what). Use the imperative
  mood and keep the subject line under 72 characters.
