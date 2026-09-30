#!/bin/sh
# FreshRSS container healthcheck.
#
# Probes the public URL of the instance, honouring FRESHRSS_PATH_PREFIX, so that it detects a
# broken sub-directory mapping (which is exactly the failure this image exists to avoid).
#
# A 401/403 is healthy: it means Apache routed the request and PHP answered, i.e. the prefix,
# the Alias and the entry point all line up. Only a 404 or a connection failure is unhealthy.
set -eu

PREFIX="${FRESHRSS_PATH_PREFIX:-}"
# Keep the probe on the installation wizard/login page rather than a redirect target.
URL="http://127.0.0.1${PREFIX}/i/?c=auth&a=login"

# shellcheck disable=SC2086
CODE="$(wget --spider --server-response --tries=1 --timeout=5 \
	--header='Host: localhost' "$URL" 2>&1 | awk '/^  HTTP\//{c=$2} END{print c}')"

case "${CODE:-000}" in
	2*|3*|401|403) exit 0 ;;
	000) echo "FreshRSS is unreachable at ${URL}" >&2; exit 1 ;;
	404) echo "FreshRSS returns 404 at ${URL} — check FRESHRSS_PATH_PREFIX and the reverse proxy" >&2; exit 1 ;;
	*)  echo "FreshRSS returned HTTP ${CODE} at ${URL}" >&2; exit 1 ;;
esac
