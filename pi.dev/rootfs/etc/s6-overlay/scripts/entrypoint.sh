#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh — foreground command runner for the pi dev box image
#
# The image uses s6-overlay as PID 1 (/init). s6 handles the daemons via the
# user bundle in /etc/s6-overlay/s6-rc.d/:
#   - wire-plugins  (oneshot)  one-time plugin wiring on first boot
#   - pi-web        (oneshot)  the Web UI daemon (auto-start on boot)
#
# This script only runs the foreground command the user asked for (no args =>
# the pi TUI), keeping the original `docker compose up` / `exec` UX intact.
# The entrypoint is NOT responsible for daemons anymore (s6 is).
# =============================================================================
set -euo pipefail

# --- run the requested command (no args => the pi TUI) ---
if [ "$#" -eq 0 ]; then
  set -- pi
fi
exec "$@"