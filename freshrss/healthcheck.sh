#!/bin/sh
# FreshRSS container healthcheck.
#
# Probes the public URL of the instance, honouring FRESHRSS_PATH_PREFIX, so that it detects a
# broken sub-directory mapping (which is exactly the failure this image exists to avoid).
#
# A 401/403 is healthy: it means Apache routed the request and PHP answered, i.e. the prefix,
# the Alias and the entry point all line up. Only a 404 or a connection failure is unhealthy.
#
# The probe uses PHP rather than wget: the image ships the PHP curl extension but no wget binary, so
# a wget-based probe could never succeed and every container reported `unhealthy`.
set -eu

PREFIX="${FRESHRSS_PATH_PREFIX:-}"
# Keep the probe on the installation wizard/login page rather than a redirect target.
URL="http://127.0.0.1${PREFIX}/i/?c=auth&a=login"

CODE="$(php -r '
	$url = $argv[1];
	$ch = curl_init($url);
	if ($ch === false) {
		echo "000";
		exit;
	}
	curl_setopt_array($ch, [
		CURLOPT_RETURNTRANSFER => true,
		CURLOPT_FOLLOWLOCATION => false,
		CURLOPT_CONNECTTIMEOUT => 3,
		CURLOPT_TIMEOUT => 5,
		CURLOPT_HTTPHEADER => ["Host: localhost", "Connection: close"],
	]);
	curl_exec($ch);
	echo (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
' "$URL" 2>/dev/null || echo 000)"

case "${CODE:-000}" in
	2*|3*|401|403) exit 0 ;;
	000) echo "FreshRSS is unreachable at ${URL}" >&2; exit 1 ;;
	404) echo "FreshRSS returns 404 at ${URL} — check FRESHRSS_PATH_PREFIX and the reverse proxy" >&2; exit 1 ;;
	*)  echo "FreshRSS returned HTTP ${CODE} at ${URL}" >&2; exit 1 ;;
esac