#!/command/with-contenv bash
# =============================================================================
# pi-web — s6 oneshot service: auto-start the Web UI daemon (pi --web --lan)
#
# Enabled by default; PI_AUTOSTART_WEB=false disables it (the service then just
# completes without doing anything). PI_WEB_ARGS can override the default --lan
# (space-separated, no quotes — e.g. "3100 --host 0.0.0.0" is written as
# PI_WEB_ARGS=3100 --host 0.0.0.0).
#
# s6's /init runs this as root, so we switch to the container user (pi, uid 1000)
# before launching (setpriv from util-linux — always present on Debian bookworm,
# unlike s6-setuidgid whose path differs between s6-overlay versions). pi --web is
# a daemon that returns immediately (it forks into the background and prints the
# URL); if a web instance is already running it just prints the URL again — safe
# to run on every start.
#
# with-contenv injects the container environment (PI_*) into this script.
# =============================================================================
set -euo pipefail

if [ "${PI_AUTOSTART_WEB:-true}" != "true" ]; then
  echo "[s6:pi-web] disabled (PI_AUTOSTART_WEB=false)"
  exit 0
fi

AGENT_DIR="${PI_CODING_AGENT_DIR:-/home/pi/.pi/agent}"
RUNTIME_UID="${PI_USER_UID:-1000}"
RUNTIME_GID="${PI_USER_GID:-1000}"
RUNTIME_HOME="${PI_USER_HOME:-/home/pi}"

if ! command -v pi >/dev/null 2>&1; then
  echo "[s6:pi-web] pi not found, skipping Web UI auto-start"
  exit 0
fi

read -r -a WEB_ARGS <<< "${PI_WEB_ARGS:---lan}"
mkdir -p "$AGENT_DIR"
# keep only the current boot's web output (relaunches append; no unbounded growth)
: > "$AGENT_DIR/pi-web.log"
chown "$RUNTIME_UID:$RUNTIME_GID" "$AGENT_DIR" "$AGENT_DIR/pi-web.log" 2>/dev/null || true

# Drop to the pi user, preserve the container environment, launch the Web UI daemon.
setpriv --reuid="$RUNTIME_UID" --regid="$RUNTIME_GID" --init-groups /usr/bin/env \
  HOME="$RUNTIME_HOME" \
  PI_CODING_AGENT_DIR="$AGENT_DIR" \
  nohup pi --web "${WEB_ARGS[@]}" > "$AGENT_DIR/pi-web.log" 2>&1 &

echo "[s6:pi-web] Web UI starting -> http://0.0.0.0:3141 (log: $AGENT_DIR/pi-web.log)"
exit 0