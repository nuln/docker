#!/usr/bin/env bash
# =============================================================================
# verify-plugins.sh — CI verification for the baked plugin wiring
#
# Runs inside the pi container (ENTRYPOINT bypassed via --entrypoint bash) with
# ~/.pi bind-mounted to an empty dir. Verifies:
#   1. The s6 wire-plugins service wrote settings.json into the mounted agent dir
#      referencing the baked plugin store (/home/pi/.pi-plugins) by absolute path.
#   2. Every referenced dir exists (the baked store is truly in the image layer).
#   3. `pi list` actually resolves those local packages (>= 14 baked dirs).
#   4. Settings are NOT rewritten on a second boot (user config preserved) —
#      exercised by the caller re-running this script against the same volume.
#
# Exit non-zero on the first failure; prints PASS/FAIL per step.
# =============================================================================
set -euo pipefail

AGENT=/home/pi/.pi/agent
BAKED=/home/pi/.pi-plugins

echo "== [1] settings.json wired by wire-plugins =="
test -e "$AGENT/settings.json" || { echo "FAIL: $AGENT/settings.json missing"; exit 1; }
echo "PASS: $AGENT/settings.json exists"

echo "== [2] all packages are absolute paths into the baked store (no copy) =="
COUNT="$(jq '.packages | length' "$AGENT/settings.json")"
[ "$COUNT" -ge 14 ] || { echo "FAIL: only $COUNT packages"; exit 1; }
while IFS= read -r p; do
    case "$p" in
      /home/pi/.pi-plugins/*) ;;
      *) echo "FAIL: not a baked path: $p"; exit 1 ;;
    esac
    [ -d "$p" ] || { echo "FAIL: missing baked dir: $p"; exit 1; }
done < <(jq -r '.packages[]' "$AGENT/settings.json")
echo "PASS: $COUNT packages -> absolute paths, all dirs exist"

echo "== [3] pi list resolves the baked local packages =="
# docker exec runs as root (HOME=/root); point pi at the mounted agent dir explicitly
# so it reads the wire-plugins settings.json (pi list resolves $PI_CODING_AGENT_DIR).
PI_CODING_AGENT_DIR="$AGENT" pi list >/tmp/pilist.txt 2>&1
COUNT="$(grep -c '^  /home/pi/.pi-plugins/' /tmp/pilist.txt || true)"
[ "$COUNT" -ge 14 ] || { echo "FAIL: pi resolved only $COUNT baked dirs"; exit 1; }
echo "PASS: pi resolved $COUNT baked plugin dirs"

echo "ALL PLUGIN CHECKS OK"
