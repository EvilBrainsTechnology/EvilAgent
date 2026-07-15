#!/usr/bin/env bash
##############################################################################
# evilagent-health – tool inventory.
#
# Checks that each enabled agent CLI can actually start. Used by `make health`
# and by the summary at the end of install-tools.sh. Exits non-zero when an
# enabled tool is missing or broken.
#
# INSTALL_* env vars are baked into the image at build time (Dockerfile ARG
# -> ENV), so a tool excluded via --build-arg shows as "disabled" rather
# than missing - a deliberate exclusion never looks like a broken build.
##############################################################################
set -uo pipefail

PATH="/home/agent/.local/bin:/home/agent/.npm-global/bin:$PATH"
export PATH

# Is the tool enabled? Anything other than "false" (including unset) = enabled.
enabled() {
  local var="INSTALL_$1"
  [ "${!var:-true}" != "false" ]
}

declare -A TOOL_FLAGS=(
  [codex]=CODEX
  [claude]=CLAUDE_CODE
  [agy]=ANTIGRAVITY
  [hermes]=HERMES
  [openclaw]=OPENCLAW
  [agent2telegram]=AGENT2TELEGRAM
  [agentsmon]=AGENTSMONITOR
)
TOOL_ORDER=(codex claude agy hermes openclaw agent2telegram agentsmon)

ok()       { printf '  \033[1;32m OK  \033[0m %s\n' "$1"; }
missing()  { printf '  \033[1;31mMISS \033[0m %s\n' "$1"; }
broken()   { printf '  \033[1;31mFAIL \033[0m %s (command does not run)\n' "$1"; }
disabled() { printf '  \033[1;90m  -  \033[0m %s (disabled)\n' "$1"; }

failures=0

for tool in "${TOOL_ORDER[@]}"; do
  flag="${TOOL_FLAGS[$tool]}"
  if ! enabled "$flag"; then
    disabled "$tool"
  elif ! command -v "$tool" >/dev/null 2>&1; then
    missing "$tool"
    failures=$((failures + 1))
  elif timeout 15 "$tool" --version >/dev/null 2>&1; then
    ok "$tool"
  else
    broken "$tool"
    failures=$((failures + 1))
  fi
done

# Whisper is not a CLI on PATH - it lives in its own venv and is driven by the
# voice2text wrapper.
if [ -x /opt/whisper-venv/bin/python ] \
   && /opt/whisper-venv/bin/python -c 'import faster_whisper' 2>/dev/null; then
  ok "whisper (voice2text)"
elif ! enabled WHISPER; then
  disabled "whisper (voice2text)"
else
  missing "whisper (voice2text)"
  failures=$((failures + 1))
fi

exit "$failures"
