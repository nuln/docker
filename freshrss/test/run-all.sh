#!/usr/bin/env bash
# Run the repository's own test suites. This is the authoritative check.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
IMG="${1:-ghcr.io/nuln/freshrss:1.30.4}"
OLD="${2:-ghcr.io/nuln/freshrss:1.30.0}"
rc=0

echo "== functional"
./test/functional.sh "$IMG" > /tmp/official-functional.log 2>&1 || rc=1
tail -3 /tmp/official-functional.log

echo "== browser"
./test/browser.sh "$IMG" > /tmp/official-browser.log 2>&1 || rc=1
tail -3 /tmp/official-browser.log

echo "== upgrade ($OLD -> $IMG)"
./test/upgrade.sh "$IMG" "$OLD" > /tmp/official-upgrade.log 2>&1 || rc=1
tail -3 /tmp/official-upgrade.log

exit $rc
