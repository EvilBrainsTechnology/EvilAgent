#!/usr/bin/env bash
##############################################################################
# container-health - the Docker HEALTHCHECK probe.
#
# Reports unhealthy when the thing that actually matters is broken: an agent
# that was configured to autostart is no longer running. Probing only the
# keepalive process would stay green with zero agents alive, which is exactly
# the failure this is meant to catch.
#
# Checks:
#   1) the keepalive process is alive,
#   2) the shared tmux session 'main' exists,
#   3) every AUTOSTART_<NAME> agent has a live tmux window.
#
# With no AUTOSTART_* configured, only 1) and 2) apply.
##############################################################################
set -uo pipefail

fail() { echo "UNHEALTHY: $*" >&2; exit 1; }

pgrep -u agent -f 'sleep infinity' >/dev/null 2>&1 \
  || fail "keepalive process is not running"

as_agent() { runuser -u agent -- env HOME=/home/agent "$@"; }

as_agent tmux has-session -t main >/dev/null 2>&1 \
  || fail "tmux session 'main' does not exist"

problems=()
for var in $(compgen -e); do
  case "$var" in
    AUTOSTART_*) ;;
    *) continue ;;
  esac
  [ -n "${!var:-}" ] || continue

  name=$(echo "${var#AUTOSTART_}" | tr '[:upper:]_' '[:lower:]-')

  if ! as_agent tmux has-session -t "main:$name" >/dev/null 2>&1; then
    problems+=("$name: window missing")
    continue
  fi

  # remain-on-exit keeps dead windows around precisely so we can see this.
  dead=$(as_agent tmux list-panes -t "main:$name" -F '#{pane_dead}' 2>/dev/null | head -n1)
  if [ "$dead" = "1" ]; then
    problems+=("$name: agent exited")
  fi
done

if [ ${#problems[@]} -gt 0 ]; then
  fail "${problems[*]}"
fi

echo "healthy"
