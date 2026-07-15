# syntax=docker/dockerfile:1
##############################################################################
# EvilAgent - běhové prostředí pro multiagentní systém (dle webináře P. Ludwig)
#
# Bezpečnostní filozofie:
#   Kontejner JE sandbox. Agenti uvnitř běží s vypnutými schvalováními
#   (--dangerously-*), ale jsou izolovaní od hostitele: neprivilegovaný
#   uživatel, zahozené capabilities, no-new-privileges, žádný přístup
#   k docker socketu, limity CPU/RAM/PID. Viz README.md.
#
#   Binárky nástrojů žijí v IMAGE (aktualizace = rebuild).
#   Konfigurace a data agentů žijí ve VOLUMES (přežijí restart i rebuild).
##############################################################################
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Europe/Prague

# --- Systémové závislosti ---------------------------------------------------
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

# --- Node.js 22 LTS (NodeSource) -> globální nástroje jdou do /usr, ne do home
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g npm@latest \
    && rm -rf /var/lib/apt/lists/*

# --- Uživatel 'agent' (uid 1000). Ubuntu 24.04 má výchozího uid 1000, smažeme.
ARG AGENT_UID=1000
ARG AGENT_GID=1000
RUN userdel -r ubuntu 2>/dev/null || true; \
    groupadd -g ${AGENT_GID} agent 2>/dev/null || true; \
    useradd -m -u ${AGENT_UID} -g ${AGENT_GID} -s /bin/bash agent

# --- Whisper (hlasové ovládání) v izolovaném venv ---------------------------
# Výchozí je lehký faster-whisper (CPU, int8). openai-whisper (torch, ~2 GB)
# je volitelný přes build-arg INSTALL_OPENAI_WHISPER=true.
ARG INSTALL_OPENAI_WHISPER=false
RUN python3 -m venv /opt/whisper-venv \
 && /opt/whisper-venv/bin/pip install --no-cache-dir -U pip \
 && /opt/whisper-venv/bin/pip install --no-cache-dir faster-whisper \
 && if [ "$INSTALL_OPENAI_WHISPER" = "true" ]; then \
        /opt/whisper-venv/bin/pip install --no-cache-dir openai-whisper; \
    fi

# --- Přesměrování konfigurace nástrojů do trvalých adresářů -----------------
ENV PATH="/home/agent/.local/bin:${PATH}" \
    CODEX_HOME=/home/agent/.codex \
    CLAUDE_CONFIG_DIR=/home/agent/.claude \
    CLOUDSDK_CONFIG=/home/agent/.config/gcloud \
    NPM_CONFIG_UPDATE_NOTIFIER=false

# --- Instalace agentních CLI (běží při buildu; každý krok je best-effort) ----
COPY scripts/install-tools.sh /usr/local/lib/evilagent/install-tools.sh
RUN chmod +x /usr/local/lib/evilagent/install-tools.sh \
 && /usr/local/lib/evilagent/install-tools.sh || true

# --- Pomocné skripty --------------------------------------------------------
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/voice2text.sh /usr/local/bin/voice2text
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/voice2text

# Prostředí pro login shelly (docker compose exec, tmux)
RUN printf '%s\n' \
      'export PATH="/home/agent/.local/bin:$PATH"' \
      'export CODEX_HOME=/home/agent/.codex' \
      'export CLAUDE_CONFIG_DIR=/home/agent/.claude' \
      'export CLOUDSDK_CONFIG=/home/agent/.config/gcloud' \
      > /etc/profile.d/evilagent.sh \
 && cat /etc/profile.d/evilagent.sh >> /home/agent/.bashrc \
 && chown agent:agent /home/agent/.bashrc

WORKDIR /home/agent/workspace

# tini = korektní PID 1 (reaping zombie procesů, kterých agenti plodí spoustu)
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["keepalive"]
