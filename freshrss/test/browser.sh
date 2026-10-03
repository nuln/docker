#!/usr/bin/env bash
# Browser-level login test.
#
# Every other check in this suite logs in with curl: it POSTs the crypto form directly and
# therefore never executes the JavaScript the login page depends on. That is a real gap, not a
# stylistic one — the login page ships with its submit button `disabled`, and only
# p/scripts/extra.js enables it, after fetching a per-login salt and nonce and deriving a bcrypt
# challenge with the vendored bcrypt.js. If any of that fails the server still answers 200 with a
# perfectly good-looking login form, no POST is ever issued, and a curl-based test passes.
#
# This drives Chromium instead, and asserts on the things only a browser can show.
#
# Skips cleanly when Playwright or its browser is not installed, so a developer machine without
# them still runs the rest of the suite. CI installs them so this never skips there.
#
# Usage: ./test/browser.sh [image]
set -euo pipefail

IMAGE="${1:-ghcr.io/nuln/freshrss:test}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NET="frss-brtest-$$"
PREFIX=/rss
APP_PORT=18300
PROXY_PORT=18301
CADDY_PORT=18302
BACKEND_PORT=18303

if ! python3 -c 'import playwright.sync_api' >/dev/null 2>&1; then
	echo "== browser login: skipped (python playwright is not installed)"
	exit 0
fi

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n     got:  %s\n     want: %s\n' "$1" "$2" "$3"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }

docker network create "$NET" >/dev/null
cleanup() {
	docker rm -f brlogin-app brlogin-proxy brlogin-caddy >/dev/null 2>&1 || true
	docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

DATA="$(mktemp -d)"
docker run -d --name brlogin-app --network "$NET" --network-alias freshrss \
	-p "${APP_PORT}:80" -p "${BACKEND_PORT}:80" \
	-e "FRESHRSS_PATH_PREFIX=${PREFIX}" \
	-v "${DATA}:/var/www/FreshRSS/data" "$IMAGE" >/dev/null
for _ in $(seq 60); do
	[ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${APP_PORT}${PREFIX}/i/?c=auth&a=login")" != "000" ] && break
	sleep 1
done
docker exec brlogin-app php /var/www/FreshRSS/cli/do-install.php \
	--default-user alice --db-type sqlite --db-base /var/www/FreshRSS/data/db.sqlite \
	--auth-type form >/dev/null 2>&1 || true
docker exec brlogin-app php /var/www/FreshRSS/cli/create-user.php \
	--user alice --password dummy-password >/dev/null 2>&1 || true
docker exec brlogin-app sh -c 'chown -R :www-data /var/www/FreshRSS/data; chmod -R g+rwX /var/www/FreshRSS/data'

# The stripping proxy needs PHP_CLI_SERVER_WORKERS: PHP's built-in server is single-threaded, so a
# browser opening six parallel connections for the document, its CSS and three scripts deadlocks
# and the page never becomes interactive — which looks exactly like a broken login.
docker run -d --name brlogin-proxy --network "$NET" --network-alias freshrss \
	-p "${PROXY_PORT}:80" -v "${SCRIPT_DIR}:/t:ro" \
	-e PROXY_TARGET=brlogin-app:80 -e PHP_CLI_SERVER_WORKERS=8 \
	--entrypoint php "$IMAGE" -S 0.0.0.0:80 /t/strip-proxy.php >/dev/null

# Caddy, from the shipped example. The example names a.example/b.example, which cannot get a
# certificate, so the scheme is pinned to http:// and a catch-all for the address used here is
# added: Caddy answers an unknown Host with an empty 200 rather than an error.
CADDY_DIR="$(mktemp -d)"
{
	echo 'http://127.0.0.1 {'
	echo '	handle '"${PREFIX}"'/* {'
	echo '		reverse_proxy freshrss:80'
	echo '	}'
	echo '}'
} > "${CADDY_DIR}/Caddyfile"
docker run -d --name brlogin-caddy --network "$NET" \
	-p "${CADDY_PORT}:80" -v "${CADDY_DIR}/Caddyfile:/etc/caddy/Caddyfile:ro" \
	caddy:2-alpine >/dev/null

echo "== browser login through a real browser"
for attempt in 1 2 3; do
	[ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PROXY_PORT}${PREFIX}/i/?c=auth&a=login")" = "200" ] && break
	sleep 2
done

run() { # run <label> <url> <prefix>
	local out
	out="$(python3 "${SCRIPT_DIR}/browser-login.py" "$2" alice dummy-password "$3" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')" || true
	printf '%s' "$out" | sed 's/^/    /'
	local n
	n="$(printf '%s' "$out" | grep -oE '[0-9]+ passed, [0-9]+ failed' | tail -1)"
	pass=$((pass + $(printf '%s' "$n" | grep -oE '^[0-9]+' || echo 0)))
	fail=$((fail + $(printf '%s' "$n" | grep -oE '[0-9]+ failed' | grep -oE '^[0-9]+' || echo 0)))
	echo "  --- $1: $n"
}

run "direct" "http://127.0.0.1:${APP_PORT}" "$PREFIX"
run "behind a proxy that strips the prefix" "http://127.0.0.1:${PROXY_PORT}" "$PREFIX"
run "behind Caddy" "http://127.0.0.1:${CADDY_PORT}" "$PREFIX"

check "every browser scenario passed" "$fail" "0"

rm -rf "$CADDY_DIR" "$DATA" 2>/dev/null || true
echo
echo "== result: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]