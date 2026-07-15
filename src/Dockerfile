# syntax=docker/dockerfile:1
##############################################################################
# EvilAgent - container runtime for a multi-agent system
#
# Security philosophy:
#   The container IS the sandbox. Agents inside run with approval guards
#   disabled (--dangerously-*) but are isolated from the host: unprivileged
#   user, dropped capabilities, no-new-privileges, no Docker socket access,
#   CPU/RAM/PID limits.
#
#   This contains HOST DAMAGE. It does not contain DATA: agents share a home
#   directory, can read each other's credentials, and have unrestricted
#   outbound network access. See the security section in README.md.
#
#   Tool binaries live in the IMAGE (update = rebuild).
#   Agent config and data live in VOLUMES (survive restart and rebuild).
##############################################################################
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Europe/Prague

# pipefail matters here: without it a piped `curl ... | bash` that 404s still
# reports success, and the build silently produces an image missing the tool.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- System dependencies -----------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg git openssh-client \
      tmux tini cron \
      python3 python3-venv python3-pip \
      ffmpeg \
      bubblewrap \
      ripgrep jq unzip zip less nano \
      build-essential pkg-config \
      procps iproute2 iputils-ping \
      openssl tzdata \
    && rm -rf /var/lib/apt/lists/*

# --- Node.js 22 LTS (NodeSource) – global tools go to /usr, not home --------
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g npm@latest \
    && rm -rf /var/lib/apt/lists/*

# --- 'agent' user (uid 1000). Ubuntu 24.04 ships with uid 1000; remove it. --
# The uid is fixed: there are no host bind-mounts to match ownership with, and
# the entrypoint takes ownership of the named volumes on first use.
RUN userdel -r ubuntu 2>/dev/null || true; \
    groupadd -g 1000 agent 2>/dev/null || true; \
    useradd -m -u 1000 -g 1000 -s /bin/bash agent

# /usr/bin/crontab is setgid 'crontab', and no-new-privileges strips setgid on
# exec - so `crontab` would fail for the agent. Real membership of the group
# grants the same access to the spool directory without any escalation, which
# is what lets `agentsmon service` install its cron job the standard way.
RUN usermod -aG crontab agent

# --- Tool selection (all installed by default; override via --build-arg) -----
ARG INSTALL_CODEX=true
ARG INSTALL_CLAUDE_CODE=true
ARG INSTALL_AGENT2TELEGRAM=true
ARG INSTALL_HERMES=true
ARG INSTALL_OPENCLAW=true
ARG INSTALL_AGENTSMONITOR=true
ARG INSTALL_ANTIGRAVITY=true
ARG INSTALL_WHISPER=true

# Bake the build-time flags into the image so health.sh and `make tools` can
# distinguish "disabled at build time" from "install failed" without needing
# .env to be mounted. ARG values do not persist after build; ENV does.
ENV INSTALL_CODEX=${INSTALL_CODEX} \
    INSTALL_CLAUDE_CODE=${INSTALL_CLAUDE_CODE} \
    INSTALL_AGENT2TELEGRAM=${INSTALL_AGENT2TELEGRAM} \
    INSTALL_HERMES=${INSTALL_HERMES} \
    INSTALL_OPENCLAW=${INSTALL_OPENCLAW} \
    INSTALL_AGENTSMONITOR=${INSTALL_AGENTSMONITOR} \
    INSTALL_ANTIGRAVITY=${INSTALL_ANTIGRAVITY} \
    INSTALL_WHISPER=${INSTALL_WHISPER}

# --- Whisper (voice control) in an isolated venv -----------------------------
# faster-whisper: CPU, int8, no torch. Good enough for transcription and a
# fraction of the size of openai-whisper.
RUN if [ "$INSTALL_WHISPER" = "true" ]; then \
        python3 -m venv /opt/whisper-venv \
     && /opt/whisper-venv/bin/pip install --no-cache-dir -U pip \
     && /opt/whisper-venv/bin/pip install --no-cache-dir faster-whisper; \
    fi

# --- Route tool config dirs to persistent locations -------------------------
ENV PATH="/home/agent/.local/bin:${PATH}" \
    CODEX_HOME=/home/agent/.codex \
    CLAUDE_CONFIG_DIR=/home/agent/.claude \
    CLOUDSDK_CONFIG=/home/agent/.config/gcloud \
    NPM_CONFIG_UPDATE_NOTIFIER=false

# --- Helper scripts (health.sh is used by install-tools.sh, so copy it first) -
COPY scripts/health.sh /usr/local/bin/evilagent-health
COPY scripts/container-health.sh /usr/local/bin/container-health
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/voice2text.sh /usr/local/bin/voice2text
RUN chmod +x /usr/local/bin/evilagent-health /usr/local/bin/container-health \
             /usr/local/bin/entrypoint.sh /usr/local/bin/voice2text

# --- Install agent CLIs (runs at build time) ---------------------------------
# INSTALL_* build args control which tools are installed (default: all).
# Exit code is decided by install-tools.sh: Codex/Claude Code are required, the
# third-party installers are best-effort. No blanket `|| true` here - that would
# let a build in which every single tool failed still produce a usable-looking
# image.
COPY scripts/install-tools.sh /usr/local/lib/evilagent/install-tools.sh
RUN chmod +x /usr/local/lib/evilagent/install-tools.sh \
 && INSTALL_CODEX="$INSTALL_CODEX" \
    INSTALL_CLAUDE_CODE="$INSTALL_CLAUDE_CODE" \
    INSTALL_AGENT2TELEGRAM="$INSTALL_AGENT2TELEGRAM" \
    INSTALL_HERMES="$INSTALL_HERMES" \
    INSTALL_OPENCLAW="$INSTALL_OPENCLAW" \
    INSTALL_AGENTSMONITOR="$INSTALL_AGENTSMONITOR" \
    INSTALL_ANTIGRAVITY="$INSTALL_ANTIGRAVITY" \
    INSTALL_WHISPER="$INSTALL_WHISPER" \
    /usr/local/lib/evilagent/install-tools.sh

# Environment for login shells (docker compose exec, tmux sessions)
RUN printf '%s\n' \
      'export PATH="/home/agent/.local/bin:$PATH"' \
      'export CODEX_HOME=/home/agent/.codex' \
      'export CLAUDE_CONFIG_DIR=/home/agent/.claude' \
      'export CLOUDSDK_CONFIG=/home/agent/.config/gcloud' \
      > /etc/profile.d/evilagent.sh \
 && cat /etc/profile.d/evilagent.sh >> /home/agent/.bashrc \
 && chown agent:agent /home/agent/.bashrc

WORKDIR /home/agent/workspace

# tini = correct PID 1: reaps zombie processes that agents tend to produce
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["keepalive"]
