#!/usr/bin/env bash
##############################################################################
# container-health - the Docker HEALTHCHECK probe.
#
# Checks the machinery that keeps agents alive, not the agents themselves.
# Supervising individual agents is AgentsMonitor's job: it relaunches a crashed
# agent within a minute, so one dead agent is not a container fault. Use
# `agentsmon status` for that view.
#
# What this catches is the machinery being broken:
#   1) the keepalive process is alive,
#   2) the shared tmux session 'main' exists,
#   3) cron is running - without it nothing would restart anything, and the
#      container would sit there looking healthy while doing nothing.
##############################################################################
set -uo pipefail

fail() { echo "UNHEALTHY: $*" >&2; exit 1; }

pgrep -u agent -f 'sleep infinity' >/dev/null 2>&1 \
  || fail "keepalive process is not running"

runuser -u agent -- env HOME=/home/agent tmux has-session -t main >/dev/null 2>&1 \
  || fail "tmux session 'main' does not exist"

if command -v cron >/dev/null 2>&1; then
  pgrep -x cron >/dev/null 2>&1 \
    || fail "cron is not running - nothing would restart a crashed agent"
fi

echo "healthy"
