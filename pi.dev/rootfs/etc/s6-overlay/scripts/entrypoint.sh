#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh — foreground command runner for the pi dev box image
#
# The image uses s6-overlay as PID 1 (/init). s6 handles the daemons via the
# user bundle in /etc/s6-overlay/s6-rc.d/:
#   - wire-plugins  (oneshot)  one-time plugin wiring on first boot
#   - pi-web        (oneshot)  the Web UI daemon (auto-start on boot)
#
# This script only runs the foreground command the user asked for. It never
# runs the full-screen `pi` TUI by default: that floods stdout with ANSI
# redraws, so `docker logs` never reaches EOF (hangs). The foreground stays a
# quiet supervisor via s6; open the TUI interactively with
# `docker compose exec -it pi pi` (or pass a command as an argument).
# =============================================================================
set -euo pipefail

# --- run the requested command (no args => quiet supervisor) ---
if [ "$#" -eq 0 ]; then
  exec /bin/sh -c 'while :; do sleep 60; done'
fi
exec "$@"