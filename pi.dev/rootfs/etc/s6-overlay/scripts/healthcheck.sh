#!/usr/bin/env bash
# =============================================================================
# healthcheck.sh — container HEALTHCHECK probe.
#
# Determines readiness for the pi.dev box:
#   * if the Web UI autostart is enabled (default), require the HTTP daemon to
#     answer on :3141 (that is when services + wiring are actually up);
#   * if the Web UI is disabled (PI_AUTOSTART_WEB=false), require the s6 supervisor
#     services pi-web/wire-plugins to have run and drop back to a liveness-only
#     check (container alive == healthy), so we never falsely mark sick just
#     because the UI was switched off.
#
# Uses bash's /dev/tcp so no curl is needed (node:24-bookworm ships bash 5+).
# Exit 0 = healthy, 1 = starting/not ready (Docker retries), 2 = unhealthy.
# =============================================================================
set -u

# liveness floor: the s6 supervisor (/init, pid 1) and the pi binary must exist.
if ! kill -0 1 2>/dev/null; then
  echo "unhealthy: no init (pid 1)"
  exit 2
fi
if ! command -v pi >/dev/null 2>&1; then
  echo "unhealthy: pi not on PATH"
  exit 2
fi

# 1) Web UI autostart enabled -> readiness: the HTTP daemon must answer :3141.
if [ "${PI_AUTOSTART_WEB:-true}" = "true" ]; then
  if exec 3<>"/dev/tcp/127.0.0.1/${PI_WEB_HEALTH_PORT:-3141}" 2>/dev/null; then
    exec 3>&- 3<&-
    echo "healthy: web UI up on :3141"
    exit 0
  fi
  echo "still starting: web UI not up on :3141 yet"
  exit 1
fi

# 2) Web autostart disabled: liveness-only (container alive == healthy), so we
#    never falsely mark the box sick just because the UI was switched off.
echo "healthy: liveness OK (Web UI autostart disabled)"
exit 0