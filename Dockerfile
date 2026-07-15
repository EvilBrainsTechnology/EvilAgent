# syntax=docker/dockerfile:1
##############################################################################
# EvilAgent - container runtime for a multi-agent system
#
# Security philosophy:
#   The container IS the sandbox. Agents inside run with approval guards
#   disabled (--dangerously-*) but are isolated from the host: unprivileged
#   user, dropped capabilities, no-new-privileges, no Docker socket access,
#   CPU/RAM/PID limits. See README.md for details.
#
#   Tool binaries live in the IMAGE (update = rebuild).
#   Agent config and data live in VOLUMES (survive restart and rebuild).
##############################################################################
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Europe/Prague

# --- System dependencies -----------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg git openssh-client \
      tmux tini \
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
ARG AGENT_UID=1000
ARG AGENT_GID=1000
RUN userdel -r ubuntu 2>/dev/null || true; \
    groupadd -g ${AGENT_GID} agent 2>/dev/null || true; \
    useradd -m -u ${AGENT_UID} -g ${AGENT_GID} -s /bin/bash agent

# --- Tool selection (configured via .env -> build args) ----------------------
ARG INSTALL_CODEX=true
ARG INSTALL_CLAUDE_CODE=true
ARG INSTALL_AGENT2TELEGRAM=true
ARG INSTALL_HERMES=true
ARG INSTALL_OPENCLAW=true
ARG INSTALL_AGENTSMONITOR=true
ARG INSTALL_ANTIGRAVITY=true
ARG INSTALL_WHISPER=true
ARG INSTALL_OPENAI_WHISPER=false

# --- Whisper (voice control) in an isolated venv -----------------------------
# Default: lightweight faster-whisper (CPU, int8).
# Full openai-whisper (torch, ~2 GB) is opt-in via INSTALL_OPENAI_WHISPER=true.
RUN if [ "$INSTALL_WHISPER" = "true" ]; then \
        python3 -m venv /opt/whisper-venv \
     && /opt/whisper-venv/bin/pip install --no-cache-dir -U pip \
     && /opt/whisper-venv/bin/pip install --no-cache-dir faster-whisper \
     && if [ "$INSTALL_OPENAI_WHISPER" = "true" ]; then \
            /opt/whisper-venv/bin/pip install --no-cache-dir openai-whisper; \
        fi; \
    fi

# --- Route tool config dirs to persistent locations -------------------------
ENV PATH="/home/agent/.local/bin:${PATH}" \
    CODEX_HOME=/home/agent/.codex \
    CLAUDE_CONFIG_DIR=/home/agent/.claude \
    CLOUDSDK_CONFIG=/home/agent/.config/gcloud \
    NPM_CONFIG_UPDATE_NOTIFIER=false

# --- Install agent CLIs (runs at build time; each step is best-effort) ------
# INSTALL_* build args control which tools are installed (see .env.example).
COPY scripts/install-tools.sh /usr/local/lib/evilagent/install-tools.sh
RUN chmod +x /usr/local/lib/evilagent/install-tools.sh \
 && INSTALL_CODEX="$INSTALL_CODEX" \
    INSTALL_CLAUDE_CODE="$INSTALL_CLAUDE_CODE" \
    INSTALL_AGENT2TELEGRAM="$INSTALL_AGENT2TELEGRAM" \
    INSTALL_HERMES="$INSTALL_HERMES" \
    INSTALL_OPENCLAW="$INSTALL_OPENCLAW" \
    INSTALL_AGENTSMONITOR="$INSTALL_AGENTSMONITOR" \
    INSTALL_ANTIGRAVITY="$INSTALL_ANTIGRAVITY" \
    /usr/local/lib/evilagent/install-tools.sh || true

# --- Helper scripts ----------------------------------------------------------
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/voice2text.sh /usr/local/bin/voice2text
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/voice2text

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
