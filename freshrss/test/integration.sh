#!/usr/bin/env bash
# Integration test for the FreshRSS multi-domain + sub-directory image.
#
# Verifies, against a real Apache + PHP + mod_auth_openidc stack:
#   1. the sub-directory is served and the public prefix survives redirects
#   2. no duplicated `/i/i` in generated paths (the upstream regression)
#   3. the session cookie is scoped to the public prefix
#   4. absolute URLs follow the request host, so several domains share one instance
#   5. WebSub callback entry-point is reachable under the prefix
#   6. OIDC advertises `<prefix>/i/oidc/` as redirect_uri, per domain, without looping
#   7. a domain-root deployment keeps the upstream behaviour
#
# Usage: ./test/integration.sh [image]
set -euo pipefail

IMAGE="${1:-ghcr.io/nuln/freshrss:test}"
NET="${NETWORK:-frss-itest-$$}"
IDP="mock-idp:9500"
PREFIX='/rss'
HTTP_PORT=18099
HTTPS_PORT=18100
OIDC_PORT=18101
IDP_PORT=19500
ENV_PORT=18102
ENV2_PORT=18103
STRIP_PORT=18112
WSUB_PORT=18104
CLI_PORT=18105
I_PORT=18106
OIDC2_PORT=18107
MAIL_PORT=18113
FLAG_PORT=18111
ALLOW_PORT=18114

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
pass=0
fail=0

cleanup() {
	docker rm -f frss-sub frss-root frss-oidc frss-oidc2 frss-env frss-env2 frss-strip frss-wsub frss-wsub2 frss-cli frss-i mock-idp websub-hub publisher smtp-sink frss-mail frss-hosts >/dev/null 2>&1 || true
	docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ok()   { pass=$((pass+1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n     got:  %s\n     want: %s\n' "$1" "$2" "$3"; }
is()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has()  { case "$2" in *"$3"*) ok "$1";; *) bad "$1" "$2" "contains: $3";; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "$2" "must not contain: $3";; *) ok "$1";; esac; }

# Print exactly one HTTP status code. curl already writes 000 for a connection failure, so the
# `|| echo 000` fallback must not append a second one (which would defeat the wait loops).
status() {
	local _c
	_c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$@" 2>/dev/null) || true
	printf '%s' "${_c:-000}"
}
header() { curl -s -D - -o /dev/null --max-time 15 "$@" 2>/dev/null | tr -d '\r' || true; }
# First Location header of a response, or the empty string.
loc() { printf '%s' "$1" | sed -n 's/^[Ll]ocation: //p' | head -1; }
get()    { curl -s --max-time 15 "$@" 2>/dev/null || true; }

echo "== image: $IMAGE"
docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "image not found: $IMAGE" >&2; exit 1; }

cleanup
docker network create "$NET" >/dev/null
BASE="http://127.0.0.1:${HTTP_PORT}"

# The two reverse-proxied domains. X-Forwarded-Host is what FreshRSS builds absolute URLs from, and
# it is also what the host-only session cookie is bound to.
# shellcheck disable=SC2034  # read through `declare -n` further down, which shellcheck cannot see
H1=(-H 'Host: a.example' -H 'X-Forwarded-Host: a.example')
# shellcheck disable=SC2034
H2=(-H 'Host: b.example' -H 'X-Forwarded-Host: b.example')


# ---------------------------------------------------------------------------------------------
echo
echo "== 1. mock OpenID Connect provider"
# The provider generates an RSA key pair and keeps pending codes on disk, so its document root has
# to be writable; only the script itself comes from the repository. It is also reachable under the
# name `idp`, because that is the issuer the discovery document advertises and FreshRSS calls the
# token endpoint server-side.
IDP_STATE="$(mktemp -d)"
cp "${SCRIPT_DIR}/mock-idp.php" "${IDP_STATE}/index.php"
docker run -d --name mock-idp --network "$NET" --network-alias idp -p "${IDP_PORT}:9500" \
	-v "${IDP_STATE}":/srv php:8.3-cli php -S 0.0.0.0:9500 -t /srv /srv/index.php >/dev/null
for _ in $(seq 30); do
	disc="$(get "http://127.0.0.1:${IDP_PORT}/.well-known/openid-configuration")"
	case "$disc" in *issuer*) break;; esac
	sleep 1
done
has "provider discovery reachable" "$(get "http://127.0.0.1:${IDP_PORT}/.well-known/openid-configuration")" '"issuer"'

OIDC_ENV=(
	-e OIDC_ENABLED=1
	-e "OIDC_PROVIDER_METADATA_URL=http://${IDP}/.well-known/openid-configuration"
	-e OIDC_CLIENT_ID=freshrss
	-e OIDC_CLIENT_SECRET=secret
	-e OIDC_CLIENT_CRYPTO_KEY=0123456789abcdef0123456789abcdef
	-e 'OIDC_SCOPES=openid profile'
)

# ---------------------------------------------------------------------------------------------
echo
echo "== 2. sub-directory deployment (${PREFIX}/)"
docker run -d --name frss-sub --network "$NET" -p "${HTTP_PORT}:80" \
	-e "FRESHRSS_PATH_PREFIX=${PREFIX}" "$IMAGE" >/dev/null
docker run -d --name frss-oidc --network "$NET" -p "${OIDC_PORT}:80" \
	-e "FRESHRSS_PATH_PREFIX=${PREFIX}" "${OIDC_ENV[@]}" "$IMAGE" >/dev/null
docker run -d --name frss-root --network "$NET" -p "${HTTPS_PORT}:80" \
	"${OIDC_ENV[@]}" "$IMAGE" >/dev/null

wait_http() { # wait_http <url>
	local _c
	for _ in $(seq 60); do
		_c=$(status "$1")
		[ "$_c" != 000 ] && return 0
		sleep 1
	done
	echo "timed out waiting for $1 (last status: ${_c:-none})" >&2
	return 1
}
wait_http "${BASE}${PREFIX}/i/?c=auth&a=login" || { echo "sub-directory container never came up" >&2; docker logs frss-sub >&2; exit 1; }
sleep 2


is "landing page serves"            "$(status "${BASE}${PREFIX}/")" 302
is "web UI under prefix"            "$(status "${BASE}${PREFIX}/i/?c=auth&a=login")" 200
# a well-formed but unknown key => 410 Gone: the endpoint is reached, not 404
is "WebSub endpoint under prefix"   "$(status "${BASE}${PREFIX}/api/pshb.php?k=deadbeef")" 410
is "WebSub rejects a malformed key"  "$(status "${BASE}${PREFIX}/api/pshb.php?k=zz")" 422
is "no double prefix"               "$(status "${BASE}${PREFIX}${PREFIX}/i/")" 404

loc=$(header "${BASE}${PREFIX}/" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p')
is "redirect keeps the prefix"      "$loc" "${PREFIX}/i/?rid=$(printf '%s' "$loc" | sed -n 's/.*rid=//p')"
hasnt "redirect is not /rss/i/i"    "$loc" '/i/i'

cookie=$(header "${BASE}${PREFIX}/i/?c=auth&a=login" | tr -d '\r' | sed -n 's/^[Ss]et-[Cc]ookie: FreshRSS=[^;]*; *//p')
has "cookie scoped to prefix"       "$cookie" "path=${PREFIX}/"

body=$(get "${BASE}${PREFIX}/i/?c=auth&a=login")
hasnt "page has no /rss/i/i link"   "$body" '/rss/i/i'
has "assets are relative"           "$body" 'src="../scripts/'

# ---------------------------------------------------------------------------------------------
echo
echo "== 3. several domains, one instance"
for host in a.example b.example cn.example.org; do
	url=$(get -H "Host: ${host}" -H "X-Forwarded-Host: ${host}" -H 'X-Forwarded-Proto: https' \
		"${BASE}${PREFIX}/api/" | grep -oE 'https?://[a-z0-9.:-]+/rss/api/greader\.php' | head -1)
	is "absolute URL follows ${host}" "$url" "https://${host}${PREFIX}/api/greader.php"
done

# ---------------------------------------------------------------------------------------------
echo
echo "== 4. OIDC under the sub-directory"
for _ in $(seq 40); do
	[ "$(status "http://127.0.0.1:${OIDC_PORT}${PREFIX}/api/")" != 000 ] && break
	sleep 1
done
sleep 2

for host in a.example b.example; do
	loc=$(header -H "Host: ${host}" -H "X-Forwarded-Host: ${host}" -H 'X-Forwarded-Proto: https' \
		"http://127.0.0.1:${OIDC_PORT}${PREFIX}/i/?c=auth&a=login" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p')
	ru=$(printf '%s' "$loc" | sed -n 's/.*redirect_uri=\([^&]*\).*/\1/p' \
		| python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.stdin.read().strip()))' 2>/dev/null || echo '')
	is "OIDC redirect_uri for ${host}" "$ru" "https://${host}${PREFIX}/i/oidc/"
done

# The callback must be recognised by mod_auth_openidc: it must NOT bounce back to the IdP
# (that loop is what a path-stripping reverse proxy causes).
state=$(header -H 'Host: a.example' -H 'X-Forwarded-Host: a.example' -H 'X-Forwarded-Proto: https' \
	"http://127.0.0.1:${OIDC_PORT}${PREFIX}/i/?c=auth&a=login" | tr -d '\r' \
	| sed -n 's/^[Ll]ocation: //p' | sed -n 's/.*state=\([^&]*\).*/\1/p')
cb=$(header -H 'Host: a.example' -H 'X-Forwarded-Host: a.example' -H 'X-Forwarded-Proto: https' \
	"http://127.0.0.1:${OIDC_PORT}${PREFIX}/i/oidc/?state=${state}&session_state=x&code=bogus" \
	| tr -d '\r' | sed -n 's/^[Ll]ocation: //p')
hasnt "callback does not loop to the IdP" "$cb" "${IDP}/authorize"
has "callback lands on OIDCDefaultURL"      "$cb" "${PREFIX}/i/"

# ---------------------------------------------------------------------------------------------
echo
echo "== 5. FRESHRSS_PATH_PREFIX is the only setting needed"
docker rm -f frss-env >/dev/null 2>&1
DATA_DIR="$(mktemp -d)"
docker run -d --name frss-env -p "${ENV_PORT}:80" \
	-e "FRESHRSS_PATH_PREFIX=${PREFIX}" -v "${DATA_DIR}:/var/www/FreshRSS/data" "$IMAGE" >/dev/null
wait_http "http://127.0.0.1:${ENV_PORT}${PREFIX}/i/?step=2" || true
sleep 1

# Walk the installation wizard, then read what it wrote.
JAR="$(mktemp)"
curl -s -c "$JAR" -b "$JAR" --max-time 15 "http://127.0.0.1:${ENV_PORT}${PREFIX}/i/?step=2" >/dev/null
curl -s -c "$JAR" -b "$JAR" --max-time 15 "http://127.0.0.1:${ENV_PORT}${PREFIX}/i/?step=2" \
	-d 'title=Test' -d 'type=sqlite' -d "base=${DATA_DIR}/db.sqlite" -d 'prefix=' \
	-d 'user=admin' -d 'pass=adminadmin' -d 'host=' -d 'step=2' -d 'submit=Submit' >/dev/null
if [ -f "${DATA_DIR}/config.php" ]; then
	written=$(sed -n "s/^[[:space:]]*'base_url' => \\(.*\\),\$/\\1/p" "${DATA_DIR}/config.php" | tr -d "'")
	is "wizard stored the path only" "$written" "$PREFIX"
else
	bad "wizard wrote no config.php" "<missing>" "'base_url' => '${PREFIX}'"
fi
rm -f "$JAR"
docker rm -f frss-env >/dev/null 2>&1
rm -rf "$DATA_DIR" 2>/dev/null || true

# FRESHRSS_BASE_URL must win over whatever the wizard wrote, so that the data volume never has
# to be edited by hand.
docker rm -f frss-env2 >/dev/null 2>&1
DATA_DIR2="$(mktemp -d)"
docker run -d --name frss-env2 -p "${ENV2_PORT}:80" \
	-e "FRESHRSS_PATH_PREFIX=${PREFIX}" -e 'FRESHRSS_BASE_URL=https://pinned.example/rss' \
	-v "${DATA_DIR2}:/var/www/FreshRSS/data" "$IMAGE" >/dev/null
wait_http "http://127.0.0.1:${ENV2_PORT}${PREFIX}/i/?step=2" || true
sleep 1
JAR2="$(mktemp)"
curl -s -c "$JAR2" -b "$JAR2" --max-time 15 "http://127.0.0.1:${ENV2_PORT}${PREFIX}/i/?step=2" >/dev/null
curl -s -c "$JAR2" -b "$JAR2" --max-time 15 "http://127.0.0.1:${ENV2_PORT}${PREFIX}/i/?step=2" \
	-d 'title=Test' -d 'type=sqlite' -d "base=${DATA_DIR2}/db.sqlite" -d 'prefix=' \
	-d 'user=admin' -d 'pass=adminadmin' -d 'host=' -d 'step=2' -d 'submit=Submit' >/dev/null
written2=$(sed -n "s/^[[:space:]]*'base_url' => \\(.*\\),\$/\\1/p" "${DATA_DIR2}/config.php" 2>/dev/null | tr -d "'")
is "FRESHRSS_BASE_URL overrides the wizard" "$written2" 'https://pinned.example/rss'
rm -f "$JAR2"

echo "== 5a2. the container reports itself healthy and actually refreshes"
# Two defects that no earlier check could see, because the suites always probed with their own
# curl and never looked at the container's own health or at cron. Both made the image report itself
# broken while serving perfectly well.
#
# 1. The healthcheck used wget, which the image does not ship: every container was `unhealthy`.
hc=$(docker exec frss-env2 /usr/local/bin/freshrss-healthcheck >/dev/null 2>&1 && echo 0 || echo 1)
is "the shipped healthcheck reports healthy on a working instance" "$hc" "0"
has "…and it does not depend on a wget binary" \
	"$(docker exec frss-env2 sh -c 'command -v wget >/dev/null && echo present || echo absent')" "absent"

# 2. Upstream's crontab template already carries the schedule, and its sed replaces only the first
# field, so cron rejected the result and no refresh job was ever installed — with CRON_MIN set *and*
# unset. A container with no refresh job still looks perfectly healthy, which is why this went
# unnoticed.
cron_line=$(docker exec frss-env2 crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$' | head -1 || true)
if [ -z "$cron_line" ]; then
	bad "the feed refresh cron is installed" "no crontab" "a crontab entry"
else
	ok "the feed refresh cron is installed"
	# cron needs exactly five schedule fields before the command. Counting *all* whitespace-separated
	# words would count the command too, so the first five are compared as a schedule.
	is "…with exactly the requested five-field schedule" \
		"$(printf '%s' "$cron_line" | awk '{print $1" "$2" "$3" "$4" "$5}')" "7,37 * * * *"
	has "…followed by the command, not more schedule fields" "$cron_line" "* . /var/www/FreshRSS/Docker/env.txt"
	has "…running the FreshRSS refresh script" "$cron_line" "actualize_script.php"
fi
has "the cron template survives the substitution" \
	"$(docker exec frss-env2 sh -c 'cat /etc/crontab.freshrss.default')" "actualize_script.php"
docker rm -f frss-env2 >/dev/null 2>&1
docker rm -f frss-env2 >/dev/null 2>&1
rm -rf "$DATA_DIR2" 2>/dev/null || true

echo
echo "== 5a. X-Forwarded-Prefix: a proxy that strips the prefix"
# Some proxies (Caddy's `handle_path`, nginx `proxy_pass …/`) do remove the prefix before forwarding.
# The container then has no Alias to serve it, and `X-Forwarded-Prefix` is what tells the application
# where the public root is, so the generated URLs still have to carry the prefix. This is the only
# supported alternative to FRESHRSS_PATH_PREFIX, and it is checked end to end.
docker rm -f frss-strip >/dev/null 2>&1
DATA_STRIP="$(mktemp -d)"
docker run -d --name frss-strip -p "${STRIP_PORT}:80" \
	-v "${DATA_STRIP}:/var/www/FreshRSS/data" "$IMAGE" >/dev/null
wait_http "http://127.0.0.1:${STRIP_PORT}/i/?step=1" || true
sleep 1
docker exec frss-strip php /var/www/FreshRSS/cli/do-install.php \
	--default-user alice --db-type sqlite --db-base /var/www/FreshRSS/data/db.sqlite \
	--auth-type none --api-enabled=true >/dev/null 2>&1 || true
docker exec frss-strip php /var/www/FreshRSS/cli/create-user.php \
	--user alice --password dummy-password >/dev/null 2>&1 || true
docker exec frss-strip sh -c 'chown -R :www-data /var/www/FreshRSS/data; chmod -R g+rwX /var/www/FreshRSS/data'

# No FRESHRSS_PATH_PREFIX: the container is at the domain root, as a stripping proxy requires.
is "the application is served without any prefix" \
	"$(status "http://127.0.0.1:${STRIP_PORT}/i/")" "200"
is "the public root is read from X-Forwarded-Prefix" \
	"$(docker exec frss-strip php -d error_reporting=0 -r '
		$_SERVER["HTTP_X_FORWARDED_PREFIX"] = "'"$PREFIX"'";
		require "/var/www/FreshRSS/constants.php"; require LIB_PATH . "/lib_rss.php";
		$_SERVER["SCRIPT_NAME"] = "/i/index.php";
		echo Minz_Request::applicationPath();
	' 2>/dev/null)" "$PREFIX"
# A request that arrives unprefixed but announces the prefix must still produce prefixed links, both
# in the page and in any redirect it emits.
strip_login=$(header -H 'X-Forwarded-Prefix: '"$PREFIX" "http://127.0.0.1:${STRIP_PORT}/i/?c=auth&a=login")
has "the redirect keeps the announced prefix" "$(loc "$strip_login")" "${PREFIX}/i/"
strip_html=$(get -H 'X-Forwarded-Prefix: '"$PREFIX" "http://127.0.0.1:${STRIP_PORT}/i/")
has "links in the page keep the announced prefix" "$strip_html" "${PREFIX}/i/"
hasnt "…and the prefix is not doubled"            "$strip_html" "${PREFIX}${PREFIX}"
is "without the header the application is at the root" \
	"$(get "http://127.0.0.1:${STRIP_PORT}/i/" | grep -c "${PREFIX}/i/" || true)" "0"
docker rm -f frss-strip >/dev/null 2>&1
rm -rf "$DATA_STRIP" 2>/dev/null || true

echo
echo "== 5b. configuration surfaces the patch introduced"
# Install non-interactively: do-install.php writes the configuration, create-user.php the account,
# and the group ownership has to be restored because both run as root while Apache runs as www-data.
docker exec frss-sub php /var/www/FreshRSS/cli/do-install.php \
	--default-user alice --db-type sqlite --db-base /var/www/FreshRSS/data/db.sqlite \
	--auth-type form --title Integration >/dev/null 2>&1
docker exec frss-sub php /var/www/FreshRSS/cli/create-user.php \
	--user alice --password sup3rsecret >/dev/null 2>&1 || true
docker exec frss-sub sh -c 'chown -R :www-data /var/www/FreshRSS/data; chmod -R g+rwX /var/www/FreshRSS/data' 2>/dev/null
is "CLI install stored the public path as base_url" \
	"$(docker exec frss-sub php -d error_reporting=0 -r \
		'$c = include "/var/www/FreshRSS/data/config.php"; echo $c["base_url"];' 2>/dev/null)" "$PREFIX"
is "admin account created" \
	"$(docker exec frss-sub sh -c '[ -f /var/www/FreshRSS/data/users/alice/config.php ] && echo yes || echo no' 2>/dev/null)" "yes"

# The admin pages are not anonymous: log in first, on domain 1.
login() { # login <jar> <host> <user> <password>
	local _jar="$1" _host="$2" _user="$3" _pass="$4" _n _c _h
	_n=$(curl -s -c "$_jar" -b "$_jar" --max-time 20 -H "Host: ${_host}" -H "X-Forwarded-Host: ${_host}" \
		"${BASE}${PREFIX}/i/?c=javascript&a=nonce&user=${_user}" \
		| sed -n 's/.*"nonce":"\([A-Za-z0-9]*\)".*/\1/p' | head -1)
	[ -n "$_n" ] || return 1
	_c=$("${SCRIPT_DIR}/bcrypt-challenge.sh" frss-sub "$_user" "$_pass" "$_n") || return 1
	_csf=$(curl -s -c "$_jar" -b "$_jar" --max-time 20 -H "Host: ${_host}" -H "X-Forwarded-Host: ${_host}" \
		"${BASE}${PREFIX}/i/?c=auth&a=login" \
		| sed -n 's/.*name="_csrf" value="\([a-f0-9]*\)".*/\1/p' | head -1)
	[ -n "$_csf" ] || return 1
	curl -s -o /dev/null -c "$_jar" -b "$_jar" --max-time 20 -H "Host: ${_host}" -H "X-Forwarded-Host: ${_host}" \
		-d "_csrf=${_csf}" -d "username=${_user}" -d "nonce=${_n}" -d "challenge=${_c}" \
		"${BASE}${PREFIX}/i/?c=auth&a=formLogin"
}
LOGIN_JAR_A="$(mktemp)"
LOGIN_JAR_B="$(mktemp)"
session_open() { # session_open <jar> <host>
	local _jar="$1" _host="$2" _body
	login "$_jar" "$_host" alice sup3rsecret || return 1
	_body="$(curl -s -c "$_jar" -b "$_jar" --max-time 20 \
		-H "Host: ${_host}" -H "X-Forwarded-Host: ${_host}" "${BASE}${PREFIX}/i/")"
	case "$_body" in *logged_in*) return 0;; esac
	return 1
}
if session_open "$LOGIN_JAR_A" a.example; then SESSION_A=1; else SESSION_A=0; fi
if session_open "$LOGIN_JAR_B" b.example; then SESSION_B=1; else SESSION_B=0; fi
is "logged in on domain 1 for the administration pages" "$SESSION_A" "1"
is "logged in on domain 2 (separate, host-only session)"   "$SESSION_B" "1"
# The admin pages changed (base URL wording, a new WebSub field, a privacy page that used to
# crash on a path-only base_url). Load every page the patch touched, on both domains.
for host in 1 2; do
	# `declare -n` is the way to indirect-reference an array: "${!_h[@]}" would only expand the
	# *name* stored in element 0, not the array it points at.
	declare -n hh="H${host}"
	dom=$([ "$host" = 1 ] && echo a.example || echo b.example)
	jar="$LOGIN_JAR_A"; [ "$host" = 2 ] && jar="$LOGIN_JAR_B"
	# Only HTML pages that really exist and are reachable by a plain user (see the
	# *Controller.php of each area). Excluded on purpose:
	#   - `index&a=rss`, `index&a=opml`  → XML output, no layout (covered by functional.sh)
	#   - `user&a=manage`, `category&a=update` → administrator-only / needs a parameter
	for page in "configure&a=system" "configure&a=privacy" "configure&a=display" "configure&a=reading" \
	            "configure&a=integration" "configure&a=archiving" "configure&a=shortcut" \
	            "configure&a=queries" "subscription&a=index" "subscription&a=bookmarklet" \
	            "index&a=normal" "index&a=global" "index&a=reader" "index&a=about" \
	            "user&a=profile"; do
		page_body=$(get "${hh[@]}" -c "$jar" -b "$jar" "${BASE}${PREFIX}/i/?c=${page}")
		# The reader views use <main id="stream">, the administration ones <main class="post">;
		# only the presence of a <main> region and a real payload is asserted.
		has "page renders on ${dom}: ${page}" "$page_body" '<main'
		hasnt "no /i/i on ${dom}: ${page}" "$page_body" '/rss/i/i'
	done
	# The new WebSub field and the resolved base URL must be visible to an administrator.
	sysof=$(get "${hh[@]}" -c "$jar" -b "$jar" "${BASE}${PREFIX}/i/?c=configure&a=system")
	has "WebSub base URL field present on ${dom}" "$sysof" 'id="websub-base-url"'
	has "resolved base URL shown on ${dom}"        "$sysof" "${dom}${PREFIX}"
done

echo
echo "== 5c. FRESHRSS_WEBSUB_BASE_URL pins the WebSub address"
# WebSub needs one stable public address; the callback is built by the refresh cron job, which
# runs with no HTTP request, so it must come from configuration or the environment.
docker rm -f frss-wsub >/dev/null 2>&1
DATA_W="$(mktemp -d)"
docker run -d --name frss-wsub -p "${WSUB_PORT}:80" \
	-e "FRESHRSS_PATH_PREFIX=${PREFIX}" -e 'FRESHRSS_WEBSUB_BASE_URL=https://rss.example.net/rss' \
	-v "${DATA_W}:/var/www/FreshRSS/data" "$IMAGE" >/dev/null
wait_http "http://127.0.0.1:${WSUB_PORT}${PREFIX}/i/?step=1" || true
sleep 1
# Install non-interactively, then read back the values the application itself uses.
# The CLI may legitimately exit non-zero (e.g. it warns that no user was created); what matters
# is the resulting configuration, which is asserted below.
docker exec frss-wsub php /var/www/FreshRSS/cli/do-install.php \
	--default-user alice --db-type sqlite --db-base /var/www/FreshRSS/data/db.sqlite \
	--auth-type none --api-enabled true >/dev/null 2>&1 || true
is "the instance is really installed before reading it" \
	"$(docker exec frss-wsub sh -c '[ -f /var/www/FreshRSS/data/config.php ] && echo yes || echo no' 2>/dev/null)" "yes"
ws=$(docker exec frss-wsub php -d error_reporting=0 -r '
	require "/var/www/FreshRSS/constants.php";
	require LIB_PATH . "/lib_rss.php";
	FreshRSS_Context::initSystem();
	echo Minz_Request::canonicalBaseUrl();
' 2>/dev/null)
is "WebSub address pinned by the environment" "$ws" 'https://rss.example.net/rss'
is "…and it is considered public (WebSub enabled)" \
	"$(docker exec frss-wsub php -d error_reporting=0 -r '
		require "/var/www/FreshRSS/constants.php";
		require LIB_PATH . "/lib_rss.php";
		FreshRSS_Context::initSystem();
		echo Minz_Request::serverIsPublic(Minz_Request::canonicalBaseUrl()) ? "yes" : "no";
	' 2>/dev/null)" "yes"
is "the callback URL is built from it" \
	"$(docker exec frss-wsub php -d error_reporting=0 -r '
		require "/var/www/FreshRSS/constants.php";
		require LIB_PATH . "/lib_rss.php";
		FreshRSS_Context::initSystem();
		echo Minz_Request::canonicalBaseUrl() . "/api/pshb.php?k=deadbeef";
	' 2>/dev/null)" 'https://rss.example.net/rss/api/pshb.php?k=deadbeef'
is "the callback endpoint answers on that path" \
	"$(status "http://127.0.0.1:${WSUB_PORT}${PREFIX}/api/pshb.php?k=deadbeef")" "410"
docker rm -f frss-wsub >/dev/null 2>&1
rm -rf "$DATA_W" 2>/dev/null || true

echo
echo "== 5d. CLI: --websub-base-url and --base-url"
DATA_C="$(mktemp -d)"
docker rm -f frss-cli >/dev/null 2>&1
docker run -d --name frss-cli -p "${CLI_PORT}:80" \
	-e "FRESHRSS_PATH_PREFIX=${PREFIX}" -v "${DATA_C}:/var/www/FreshRSS/data" "$IMAGE" >/dev/null
wait_http "http://127.0.0.1:${CLI_PORT}${PREFIX}/i/?step=1" || true
sleep 1
docker exec frss-cli php /var/www/FreshRSS/cli/do-install.php \
	--default-user alice --db-type sqlite --db-base /var/www/FreshRSS/data/db.sqlite --auth-type none \
	--base-url https://pinned.example/rss --websub-base-url https://hub.example/rss \
	--api-enabled true >/dev/null 2>&1 || true
is "do-install --base-url stored" \
	"$(sed -n "s/^[[:space:]]*'base_url' => \(.*\),\$/\1/p" "${DATA_C}/config.php" | tr -d "'")" 'https://pinned.example/rss'
is "do-install --websub-base-url stored" \
	"$(sed -n "s/^[[:space:]]*'websub_base_url' => \(.*\),\$/\1/p" "${DATA_C}/config.php" | tr -d "'")" 'https://hub.example/rss'
# reconfigure must be able to change them afterwards, without touching the file by hand.
docker exec frss-cli php /var/www/FreshRSS/cli/reconfigure.php \
	--base-url /rss --websub-base-url https://other.example/rss >/dev/null 2>&1
is "reconfigure --base-url applied" \
	"$(sed -n "s/^[[:space:]]*'base_url' => \(.*\),\$/\1/p" "${DATA_C}/config.php" | tr -d "'")" '/rss'
is "reconfigure --websub-base-url applied" \
	"$(sed -n "s/^[[:space:]]*'websub_base_url' => \(.*\),\$/\1/p" "${DATA_C}/config.php" | tr -d "'")" 'https://other.example/rss'
docker rm -f frss-cli >/dev/null 2>&1
rm -rf "$DATA_C" 2>/dev/null || true

# Pinned upstream limitation, asserted rather than left as a landmine. `getopt()` reads the value of
# a long option declared with `::` only when it is attached with `=`, and it stops scanning at the
# first bare argument. A boolean option written as `--api-enabled true` therefore loses both its own
# value and every option that comes after it, with no error at all. Since `--base-url` and
# `--websub-base-url` are exactly what this image is about, both spellings are asserted here: the
# `=` form must work, and the space-separated form must be known to drop what follows.
# The environment variables this image documents (FRESHRSS_PATH_PREFIX, FRESHRSS_BASE_URL,
# FRESHRSS_WEBSUB_BASE_URL) do not go through the CLI parser and are unaffected.
install_flags() { # install_flags <data-dir> <flags...>
	local _dir="$1"; shift
	docker run -d --name frss-flagtest -p "${FLAG_PORT}:80" -e "FRESHRSS_PATH_PREFIX=${PREFIX}" \
		-v "${_dir}:/var/www/FreshRSS/data" "$IMAGE" >/dev/null
	wait_http "http://127.0.0.1:${FLAG_PORT}${PREFIX}/i/?step=1" || true
	sleep 1
	docker exec frss-flagtest php /var/www/FreshRSS/cli/do-install.php \
		--default-user alice --db-type sqlite --db-base /var/www/FreshRSS/data/db.sqlite \
		--auth-type none "$@" >/dev/null 2>&1 || true
	docker rm -f frss-flagtest >/dev/null 2>&1
}
DATA_D="$(mktemp -d)"
install_flags "$DATA_D" --base-url https://pinned.example/rss --api-enabled=true
is "a boolean written as --flag=value keeps the options that follow" \
	"$(sed -n "s/^[[:space:]]*'base_url' => \(.*\),\$/\1/p" "${DATA_D}/config.php" | tr -d "'")" 'https://pinned.example/rss'
is "…and takes the value it was given" \
	"$(sed -n "s/^[[:space:]]*'api_enabled' => \(.*\),\$/\1/p" "${DATA_D}/config.php" | tr -d "'")" 'true'
rm -rf "$DATA_D" 2>/dev/null || true
DATA_D="$(mktemp -d)"
install_flags "$DATA_D" --api-enabled true --base-url https://pinned.example/rss
is "a boolean written as --flag value is documented to swallow what follows" \
	"$(sed -n "s/^[[:space:]]*'base_url' => \(.*\),\$/\1/p" "${DATA_D}/config.php" | tr -d "'")" "${PREFIX}"
rm -rf "$DATA_D" 2>/dev/null || true

echo
echo "== 5e. a sub-directory named /i is unambiguous"
docker rm -f frss-i >/dev/null 2>&1
docker run -d --name frss-i -p "${I_PORT}:80" -e 'FRESHRSS_PATH_PREFIX=/i' "$IMAGE" >/dev/null
wait_http "http://127.0.0.1:${I_PORT}/i/i/?c=auth&a=login" || true
sleep 1
# SCRIPT_NAME alone cannot tell `/i/i/index.php` (prefix `/i`) from the `/i/` entry-point, which
# is why the container also states the prefix. Verify the entry point really answers.
is "a /i sub-directory is served correctly" \
	"$(status "http://127.0.0.1:${I_PORT}/i/i/?c=auth&a=login")" "200"
# `/i/` is now the landing page: it must redirect to the application under `/i/i/`, and the two
# paths must not be confused with each other.
iloc=$(curl -s -D - -o /dev/null --max-time 15 "http://127.0.0.1:${I_PORT}/i/" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p')
has "the /i landing page redirects into the app" "$iloc" "/i/i/"
has "…and /i/i serves the application" \
	"$(status "http://127.0.0.1:${I_PORT}/i/i/?c=auth&a=login")" "200"
# `/i/` is the landing page and ignores the query string, so it must NOT behave like the app.
jloc=$(curl -s -D - -o /dev/null --max-time 15 "http://127.0.0.1:${I_PORT}/i/?c=auth&a=login" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p')
has "…while /i/ itself stays the landing page" "$jloc" "/i/i/"
is "…and the application page is served only one level deeper" \
	"$(status "http://127.0.0.1:${I_PORT}/i/i/?c=auth&a=login")" "200"

echo
echo "== 5f. a complete OIDC login (authorize -> token -> session) =="
# The whole authorisation-code flow, driven the way a browser would. This is the only check that
# proves mod_auth_openidc can actually establish a session under a sub-directory, rather than just
# advertising the right redirect_uri.
OIDC_JAR="$(mktemp)"
docker rm -f frss-oidc2 >/dev/null 2>&1
docker run -d --name frss-oidc2 --network "$NET" -p "${OIDC2_PORT}:80" \
	-e "FRESHRSS_PATH_PREFIX=${PREFIX}" "${OIDC_ENV[@]}" "$IMAGE" >/dev/null
wait_http "http://127.0.0.1:${OIDC2_PORT}${PREFIX}/i/?c=auth&a=login" || true
sleep 1

# FreshRSS maps REMOTE_USER to an account; HTTP auth is the mode an OIDC deployment uses.
docker exec frss-oidc2 php /var/www/FreshRSS/cli/do-install.php \
	--default-user alice --db-type sqlite --db-base /var/www/FreshRSS/data/db.sqlite \
	--auth-type http_auth --title OIDC >/dev/null 2>&1 || true
docker exec frss-oidc2 php /var/www/FreshRSS/cli/create-user.php \
	--user alice --password dummy-password >/dev/null 2>&1 || true
docker exec frss-oidc2 sh -c 'chown -R :www-data /var/www/FreshRSS/data; chmod -R g+rwX /var/www/FreshRSS/data' 2>/dev/null

# 1. An anonymous visitor is bounced to the provider.
# NOTE: no X-Forwarded-Proto here. mod_auth_openidc marks its `state` cookie `Secure`, and the test
# speaks plain HTTP to the container, so a "secure" cookie would never be sent back and the flow
# could not complete. Section 4 already asserts the https form of the redirect_uri.
first=$(header -c "$OIDC_JAR" -b "$OIDC_JAR" -H 'Host: a.example' -H 'X-Forwarded-Host: a.example' \
	"http://127.0.0.1:${OIDC2_PORT}${PREFIX}/i/?c=auth&a=login")
auth_url=$(loc "$first")
has "anonymous access is sent to the IdP" "$auth_url" 'authorize'
ru=$(printf '%s' "$auth_url" | sed -n 's/.*redirect_uri=\([^&]*\).*/\1/p' \
	| python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.stdin.read().strip()))' 2>/dev/null || echo '')
is "the advertised redirect_uri keeps the prefix" "$ru" "http://a.example${PREFIX}/i/oidc/"
idp_state=$(printf '%s' "$auth_url" | sed -n 's/.*[?&]state=\([^&]*\).*/\1/p')
[ -n "$idp_state" ] && ok "state parameter present" || bad "state parameter present" "<empty>" "value"
idp_nonce=$(printf '%s' "$auth_url" | sed -n 's/.*[?&]nonce=\([^&]*\).*/\1/p')
[ -n "$idp_nonce" ] && ok "nonce parameter present" || bad "nonce parameter present" "<empty>" "value"

# 2. The provider authenticates and redirects back with a code. It is reachable from the host
#    through its published port, so the browser leg is reproduced here. The nonce has to be the one
#    mod_auth_openidc challenged with, because a real provider echoes it into the id_token and the
#    module rejects the login when the two differ.
ru_enc=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$ru")
back=$(curl -s -D - -o /dev/null --max-time 20 \
	"http://127.0.0.1:${IDP_PORT}/authorize?response_type=code&client_id=freshrss&scope=openid%20profile&redirect_uri=${ru_enc}&state=${idp_state}&nonce=${idp_nonce}" || true)
cb=$(loc "$back")
has "the IdP redirects back to the callback" "$cb" "${PREFIX}/i/oidc/"
code=$(printf '%s' "$cb" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')
[ -n "$code" ] && ok "authorisation code issued" || bad "authorisation code issued" "<empty>" "value"

# 3. FreshRSS exchanges the callback for tokens and must accept the RS256 id_token.
final=$(header -c "$OIDC_JAR" -b "$OIDC_JAR" -H 'Host: a.example' -H 'X-Forwarded-Host: a.example' \
	"http://127.0.0.1:${OIDC2_PORT}${PREFIX}/i/oidc/?code=${code}&state=${idp_state}" || true)
hasnt "the callback is not rejected"   "$(printf '%s' "$final" | tr -d '\r' | grep -iE '^HTTP' | head -1)" ' 400 '
hasnt "…and does not bounce back to the IdP" "$(loc "$final")" 'authorize'

# 4. The session is authenticated, resolved from the `preferred_username` claim.
reader=$(curl -s -c "$OIDC_JAR" -b "$OIDC_JAR" --max-time 20 -H 'Host: a.example' \
	-H 'X-Forwarded-Host: a.example' "http://127.0.0.1:${OIDC2_PORT}${PREFIX}/i/" || true)
has "OIDC login establishes a session"   "$reader" 'logged_in'
hasnt "…and it is not the login form"     "$reader" 'name="challenge"'
has "…resolved to the user alice"         "$reader" 'alice'
hasnt "no /i/i in the authenticated HTML" "$reader" '/rss/i/i'
# The provider must have seen a real token exchange, with the prefixed redirect_uri and nonce.
toklog=$(curl -s --max-time 20 "http://127.0.0.1:${IDP_PORT}/token-log" || true)
has "the IdP received a token request"      "$toklog" '"grant_type":"authorization_code"'
has "…authenticated the client"             "$toklog" '"client_id":"freshrss"'
has "…with the prefixed redirect_uri"       "$toklog" "${PREFIX}/i/oidc/"
last=$(curl -s --max-time 20 "http://127.0.0.1:${IDP_PORT}/last" || true)
has "the IdP saw the token exchange"      "$last" '"client_id":"freshrss"'
has "…with the prefixed redirect_uri"     "$last" "${PREFIX}/i/oidc/"
has "…and the nonce that was challenged"  "$last" "\"nonce\":\"${idp_nonce}\""
has "…and the mapped claim"               "$last" '"preferred_username":"alice"'
rm -f "$OIDC_JAR"
docker rm -f frss-oidc2 >/dev/null 2>&1

echo
echo "== 5g. a real WebSub subscription behind a prefix-preserving reverse proxy =="
# The complete WebSub round trip: the feed advertises a hub, FreshRSS subscribes with a callback
# built from the pinned public base URL, the hub verifies that callback, pushes new content to it,
# and the article is stored with no pull refresh at all. Then the feed "moves", which is the only
# path that makes FreshRSS unsubscribe.
#
# The public address is served by a reverse proxy that does NOT strip the prefix. That is not a
# stylistic choice: the WebSub callback is `<public base>/api/pshb.php`, and the same holds for
# OIDC, so a stripping proxy would make both unsolvable.
HUB_PORT=18108
WSUB2_PORT=18110
HUB_STATE="$(mktemp -d)"
PUB_STATE="$(mktemp -d)"
DATA_G="$(mktemp -d)"
cp "${SCRIPT_DIR}/mock-websub-hub.php" "${HUB_STATE}/index.php"
cp "${SCRIPT_DIR}/fixtures/index.php" "${PUB_STATE}/index.php"

# The topic, the hub and the reader application all live on `websub.example`, served by a reverse
# proxy that does NOT strip the prefix. Both choices are load-bearing: the WebSub callback is
# `<public base>/api/pshb.php`, and FreshRSS only pairs a hub with an address it considers reachable,
# falling back to a same-host comparison when the name resolves to a private address — which is
# exactly the case for any name that exists only inside a container network.
HUB_PORT=18108
WSUB2_PORT=18110
HUB_STATE="$(mktemp -d)"
PUB_STATE="$(mktemp -d)"
DATA_G="$(mktemp -d)"
cp "${SCRIPT_DIR}/mock-websub-hub.php" "${HUB_STATE}/index.php"
cp "${SCRIPT_DIR}/fixtures/index.php" "${PUB_STATE}/index.php"

PUBLIC="http://websub.example:9600"
TOPIC="${PUBLIC}/feed.xml"
HUB_ADVERTISED="${PUBLIC}/hub"

docker run -d --name frss-wsub2 --network "$NET" -p "${WSUB2_PORT}:80" \
	-e "FRESHRSS_PATH_PREFIX=${PREFIX}" \
	-e "FRESHRSS_WEBSUB_BASE_URL=${PUBLIC}${PREFIX}" \
	-e "INTERNAL_HOST_ALLOWLIST=websub.example:9600 websub.example:80" \
	-v "${DATA_G}":/var/www/FreshRSS/data "$IMAGE" >/dev/null
docker run -d --name publisher --network "$NET" \
	-e "PUBLISHER_SELF_URL=${TOPIC}" -e "PUBLISHER_HUB_URL=${HUB_ADVERTISED}" \
	-v "${PUB_STATE}":/srv php:8.3-cli php -S 0.0.0.0:8080 -t /srv /srv/index.php >/dev/null
docker run -d --name websub-hub --network "$NET" --network-alias websub.example -p "${HUB_PORT}:9600" \
	-e "FRSS_UPSTREAM=http://frss-wsub2" -e "PUBLISHER_UPSTREAM=http://publisher:8080" \
	-e "PHP_CLI_SERVER_WORKERS=8" \
	-v "${HUB_STATE}":/srv php:8.3-cli php -S 0.0.0.0:9600 -t /srv /srv/index.php >/dev/null
wait_http "http://127.0.0.1:${WSUB2_PORT}${PREFIX}/i/?step=1" || true
sleep 2

docker exec frss-wsub2 php /var/www/FreshRSS/cli/do-install.php \
	--default-user alice --db-type sqlite --db-base /var/www/FreshRSS/data/db.sqlite \
	--auth-type none --websub-base-url "${PUBLIC}${PREFIX}" --api-enabled true >/dev/null 2>&1 || true
docker exec frss-wsub2 php /var/www/FreshRSS/cli/create-user.php \
	--user alice --password dummy-password >/dev/null 2>&1 || true
docker exec frss-wsub2 sh -c 'chown -R :www-data /var/www/FreshRSS/data; chmod -R g+rwX /var/www/FreshRSS/data'
# `do-install.php` enables WebSub when the pinned address looks public. Here the name resolves only
# inside the container network, i.e. to a private IP, so the check declines and the flag is set
# explicitly — which an operator with a real public DNS name gets for free.
docker exec frss-wsub2 php -r '
	$f = "/var/www/FreshRSS/data/config.php";
	$c = file_get_contents($f);
	$c = str_replace("array (", "array (\n\x27pubsubhubbub_enabled\x27 => true,", $c);
	file_put_contents($f, $c);
' >/dev/null 2>&1
is "WebSub is enabled in the stored configuration" \
	"$(docker exec frss-wsub2 php -r '$c=include "/var/www/FreshRSS/data/config.php";echo !empty($c["pubsubhubbub_enabled"]) ? "yes" : "no";' 2>/dev/null)" "yes"
is "the pinned WebSub address was persisted" \
	"$(docker exec frss-wsub2 php -r '$c=include "/var/www/FreshRSS/data/config.php";echo $c["websub_base_url"] ?? "";' 2>/dev/null)" "${PUBLIC}${PREFIX}"

# The proxy must not strip the prefix, otherwise the callback the hub verifies cannot resolve.
is "the reverse proxy serves the prefixed reader page" \
	"$(status -H 'Host: websub.example' "http://127.0.0.1:${HUB_PORT}${PREFIX}/i/?c=auth&a=login")" "200"
is "…and the publisher is reachable on the same host" \
	"$(status "http://127.0.0.1:${HUB_PORT}/feed.xml")" "200"
has "…advertising itself and a hub" "$(get "http://127.0.0.1:${HUB_PORT}/feed.xml")" 'rel="hub"'

# Subscribe the feed through the OPML importer, then actualise, which is when FreshRSS notices the
# hub link and enrols the feed. The attribute is `xmlUrl`, not `xml:url`: that is the spelling
# LibOpml — and therefore FreshRSS's own exporter — uses, and a namespaced one is silently ignored.
OPML="$(mktemp)"
cat > "$OPML" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<opml version="1.0"><head><title>websub test</title></head><body>
<outline type="rss" xmlUrl="${TOPIC}" text="Functional Test"/>
</body></opml>
XML
docker cp "$OPML" frss-wsub2:/tmp/websub.opml >/dev/null 2>&1
rm -f "$OPML"
docker exec frss-wsub2 php /var/www/FreshRSS/cli/import-for-user.php \
	--user alice --filename /tmp/websub.opml >/dev/null 2>&1 || true
docker exec frss-wsub2 php /var/www/FreshRSS/cli/actualize-user.php --user alice >/dev/null 2>&1 || true

subs=$(get "http://127.0.0.1:${HUB_PORT}/subs")
has "the hub received a subscription for the feed topic" "$subs" "$TOPIC"
has "…whose callback is the prefixed pshb endpoint"       "$subs" "${PREFIX}/api/pshb.php?k="
hasnt "…and the callback did not lose the prefix"         "$subs" '"callback":"http://websub.example:9600/api/pshb.php'
hublog=$(get "http://127.0.0.1:${HUB_PORT}/hub-log")
has "the hub was asked to subscribe"        "$hublog" "hub mode=subscribe topic=${TOPIC}"
has "…and it verified the callback itself" "$hublog" 'echoed=yes'

# The key ties the callback to the topic; `lease_end` is only written when a hub re-announces the
# intent with `hub_mode=subscribe`, which a specification-compliant hub does not do, so the signal
# to assert is that FreshRSS itself now considers the feed WebSub-enabled.
hubjson=$(docker exec frss-wsub2 sh -c \
	'cat "$(find /var/www/FreshRSS/data/PubSubHubbub -name "!hub.json" | head -1)"' 2>/dev/null || echo '')
has "FreshRSS recorded the topic key on disk" "$hubjson" "\"key\":\""
is "FreshRSS considers the feed WebSub-enabled" \
	"$(docker exec frss-wsub2 php -d error_reporting=0 -r '
		require "/var/www/FreshRSS/constants.php"; require LIB_PATH . "/lib_rss.php";
		FreshRSS_Context::initSystem(); FreshRSS_Context::initUser("alice");
		foreach (FreshRSS_Factory::createFeedDao("alice")->listFeeds() as $f) {
			if ($f->url() === "'"$TOPIC"'") { echo $f->pubSubHubbubEnabled() ? "yes" : "no"; break; }
		}
	' 2>/dev/null)" "yes"
# The WebSub state lives on disk, written by root (the CLI and the refresh cron run as root) and
# read by the Apache workers (www-data). That only works if those directories are group-accessible
# to www-data. Docker Desktop's file sharing bypasses permission checks, so a macOS run cannot
# observe a regression here at all; the probe below detects that and skips instead of pretending.
PSHB_KEY=$(docker exec frss-wsub2 sh -c \
	'ls /var/www/FreshRSS/data/PubSubHubbub/keys/*.txt 2>/dev/null | head -1' || true)
perm_enforced=$(docker exec frss-wsub2 sh -c '
	p=/var/www/FreshRSS/data/.permprobe
	rm -rf "$p" 2>/dev/null
	mkdir -p "$p" 2>/dev/null
	chown :www-data "$p" 2>/dev/null
	g=$(stat -c %G "$p" 2>/dev/null)
	rm -rf "$p" 2>/dev/null
	[ "$g" = "www-data" ] && echo yes || echo no' 2>/dev/null || echo no)
if [ "$perm_enforced" != "yes" ]; then
	ok "WebSub state permissions not enforceable on this filesystem (Docker Desktop) — check skipped"
elif [ -n "$PSHB_KEY" ]; then
	ws_mode=$(docker exec frss-wsub2 stat -c '%a %G' "$(dirname "${PSHB_KEY}")" 2>/dev/null || echo '?')
	has "the WebSub key directory is group-owned by the Apache group" "$ws_mode" "www-data"
	if docker exec frss-wsub2 sh -c "setpriv --reuid=33 --regid=33 --clear-groups cat '${PSHB_KEY}'" >/dev/null 2>&1; then
		ok "the Apache worker (www-data) can read the WebSub key file"
	else
		bad "the Apache worker (www-data) can read the WebSub key file" "permission denied" "readable"
	fi
else
	bad "the WebSub key directory is group-owned by the Apache group" "<no key file>" "a key file"
fi

# Content distribution: publish, then let the hub push. No pull refresh is issued in between.
count_entries() {
	docker exec frss-wsub2 php -d error_reporting=0 -r '
		require "/var/www/FreshRSS/constants.php"; require LIB_PATH . "/lib_rss.php";
		FreshRSS_Context::initSystem(); FreshRSS_Context::initUser("alice");
		echo FreshRSS_Factory::createEntryDao("alice")->count();
	' 2>/dev/null || true
}
before=$(count_entries || true)
if [ -n "$before" ]; then ok "the entry count is readable before the push"; else bad "the entry count is readable before the push" "<empty>" "value"; fi
curl -s --max-time 20 -X POST "http://127.0.0.1:${HUB_PORT}/publish" >/dev/null || true
topic_enc=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$TOPIC")
notify=$(get "http://127.0.0.1:${HUB_PORT}/notify?topic=${topic_enc}")
has "the hub pushed the new content to the callback" "$notify" '"status": 200'
has "…and FreshRSS accepted it"                     "$notify" 'Done:'
after=$(count_entries || true)
is "the pushed article was stored without any pull refresh" "$after" "$((before + 1))"

# Unsubscription. Upstream only reaches it from `actualizeFeedsAndCommit`, and only for a feed whose
# pushed `self` link differs from its stored URL — a chain that depends on its own cache/304
# handling. What this patch actually changes there is the *callback URL*, so the unsubscribe is driven
# through the same application API instead, against the same live hub. That pins the part that is
# ours: the hub must receive `hub.mode=unsubscribe` pointing at the same prefixed callback, and the
# verification must succeed. FreshRSS expires its own lease first, which is what makes
# `p/api/pshb.php` accept the request and echo the challenge back.
is "the application reports the unsubscription as accepted" \
	"$(docker exec frss-wsub2 php -d error_reporting=0 -r "
		require '/var/www/FreshRSS/constants.php'; require LIB_PATH . '/lib_rss.php';
		FreshRSS_Context::initSystem();
		\$feed = new FreshRSS_Feed('${TOPIC}');
		echo \$feed->pubSubHubbubSubscribe(false) ? 'ok' : 'failed';
	" 2>/dev/null || true)" "ok"
pshb_log=$(docker exec frss-wsub2 sh -c 'tail -4 /var/www/FreshRSS/data/users/_/log_pshb.txt 2>/dev/null' || true)
has "FreshRSS sent the unsubscribe with the prefixed callback" \
	"$pshb_log" "WebSub unsubscribe to ${TOPIC}"
has "…and the callback kept the sub-directory" "$pshb_log" "${PREFIX}/api/pshb.php?k="
hublog=$(get "http://127.0.0.1:${HUB_PORT}/hub-log")
has "the hub was asked to unsubscribe" "$hublog" "hub mode=unsubscribe topic=${TOPIC}"
has "…and it completed the verification" "$hublog" 'echoed=yes'
subs=$(get "http://127.0.0.1:${HUB_PORT}/subs")
hasnt "the hub dropped the topic" "$subs" "\"${TOPIC}\""
docker rm -f frss-wsub2 websub-hub publisher >/dev/null 2>&1
rm -rf "$HUB_STATE" "$PUB_STATE" "$DATA_G" 2>/dev/null || true

echo
echo
echo "== 5h. email validation under the sub-directory =="
# `force_email_validation` makes FreshRSS sign a token, mail a link to it, and keep the account
# restricted until that link is followed. The link is built with `Minz_Url::display()`, i.e. through
# the very code this patch rewrites, so under a sub-directory it used to point at the domain root and
# could not be followed at all. A real SMTP sink receives the mail, so the path is exercised for
# real: address → token → SMTP → link → follow → token cleared.
MAIL_PORT=18113
FLAG_PORT=18111
MAIL_STATE="$(mktemp -d)"
DATA_M="$(mktemp -d)"

docker run -d --name smtp-sink --network "$NET" -v "${MAIL_STATE}:/sink" \
	-v "${SCRIPT_DIR}/smtp-sink.php":/sink.php:ro \
	--entrypoint php "$IMAGE" /sink.php /sink 1025 >/dev/null
docker run -d --name frss-mail --network "$NET" -p "${MAIL_PORT}:80" \
	-e "FRESHRSS_PATH_PREFIX=${PREFIX}" -e "INTERNAL_HOST_ALLOWLIST=smtp-sink" \
	-v "${DATA_M}:/var/www/FreshRSS/data" "$IMAGE" >/dev/null
wait_http "http://127.0.0.1:${MAIL_PORT}${PREFIX}/i/?step=1" || true
sleep 2

docker exec frss-mail php /var/www/FreshRSS/cli/do-install.php \
	--default-user alice --db-type sqlite --db-base /var/www/FreshRSS/data/db.sqlite \
	--auth-type form --api-enabled=true >/dev/null 2>&1 || true
# Neither `force_email_validation` nor the SMTP settings have an environment variable or a CLI flag,
# so they are written the way the administration page writes them.
docker exec frss-mail php -r '
	$f = "/var/www/FreshRSS/data/config.php";
	$c = file_get_contents($f);
	$c = str_replace("array (", "array (
\x27force_email_validation\x27 => true,
\x27mailer\x27 => \x27smtp\x27,
\x27smtp\x27 => [
\x27hostname\x27 => \x27a.example\x27,
\x27host\x27 => \x27smtp-sink\x27,
\x27port\x27 => 1025,
\x27auth\x27 => false,
\x27auto_tls\x27 => false,
\x27secure\x27 => \x27\x27,
\x27from\x27 => \x27freshrss@a.example\x27,
],", $c);
	file_put_contents($f, $c);
' >/dev/null 2>&1
is "email validation is forced" \
	"$(docker exec frss-mail php -r '$c=include "/var/www/FreshRSS/data/config.php";echo !empty($c["force_email_validation"]) ? "yes" : "no";' 2>/dev/null)" "yes"

# The account is created without an address on purpose: `create-user.php --email` stores
# `mail_login` before calling the updater, so the "the address changed" branch — the one that signs
# the token and sends the mail — never fires. The function below is the one the profile form calls.
docker exec frss-mail php /var/www/FreshRSS/cli/create-user.php \
	--user alice --password dummy-password >/dev/null 2>&1 || true
docker exec frss-mail sh -c 'chown -R :www-data /var/www/FreshRSS/data; chmod -R g+rwX /var/www/FreshRSS/data'
docker exec frss-mail php -d error_reporting=0 -r '
	require "/var/www/FreshRSS/constants.php"; require LIB_PATH . "/lib_rss.php";
	FreshRSS_Context::initSystem();
	Minz_Translate::init("en");
	FreshRSS_user_Controller::updateUser("alice", "alice@example.invalid", "");
' >/dev/null 2>&1 || true

is "a validation mail reached the SMTP sink" \
	"$(docker exec smtp-sink sh -c 'test -s /sink/last-mail.txt && echo yes || echo no' 2>/dev/null)" "yes"
mail=$(docker exec smtp-sink sh -c 'cat /sink/last-mail.txt' 2>/dev/null || true)
has "it is addressed to the account" "$mail" 'alice@example.invalid'
hasnt "…and is not left untranslated"  "$mail" 'user.mailer.email_need_validation'
# The message is CRLF-delimited, so the extracted URL has to be stripped of the trailing CR.
validation_url=$(printf '%s' "$mail" | grep -oE 'https?://[^[:space:]"<]+validateEmail[^[:space:]"<]+' | head -1 | tr -d '\r' || true)
[ -n "$validation_url" ] && ok "it carries a validation link" || bad "it carries a validation link" "<empty>" "a URL"
# The assertion the sub-directory requirement is really about: the mailed link has to keep the
# prefix, or following it lands outside the application.
has "the validation link keeps the sub-directory" "$validation_url" "${PREFIX}/i/?c=user&a=validateEmail"
has "…and names the account"                        "$validation_url" 'username=alice'
has "…and carries a token"                          "$validation_url" 'token='
token=$(printf '%s' "$validation_url" | sed -n 's/.*token=\([^&]*\).*/\1/p' || true)
[ -n "$token" ] && ok "the token could be extracted" || bad "the token could be extracted" "<empty>" "a value"
is "the token is stored on the account" \
	"$(docker exec frss-mail php -d error_reporting=0 -r '
		require "/var/www/FreshRSS/constants.php"; require LIB_PATH . "/lib_rss.php";
		$c = FreshRSS_UserConfiguration::getForUser("alice");
		echo $c !== null && $c->email_validation_token === "'"$token"'" ? "yes" : "no";
	' 2>/dev/null || true)" "yes"

# From a browser the link is built during a request, so the host is the one that was used. This is
# the same call the mailer makes, with the same arguments, in a request context.
is "the mailed link follows the domain of the request" \
	"$(docker exec frss-mail php -d error_reporting=0 -r '
		require "/var/www/FreshRSS/constants.php"; require LIB_PATH . "/lib_rss.php";
		FreshRSS_Context::initSystem();
		$_SERVER["HTTP_HOST"] = "a.example";
		$_SERVER["HTTP_X_FORWARDED_HOST"] = "a.example";
		$_SERVER["HTTP_X_FORWARDED_PROTO"] = "https";
		$_SERVER["SCRIPT_NAME"] = "/i/index.php";
		$_SERVER["REQUEST_URI"] = "/i/";
		$_GET = []; $_POST = [];
		echo Minz_Url::display([
			"c" => "user", "a" => "validateEmail",
			"params" => ["username" => "alice", "token" => "tok"],
		], "txt", true);
	' 2>/dev/null || true)" 'https://a.example/rss/i/?c=user&a=validateEmail&username=alice&token=tok'

# Following the link is what clears the token. A wrong token must not.
MAIL_H=(-H 'Host: a.example' -H 'X-Forwarded-Host: a.example' -H 'X-Forwarded-Proto: https')
# Keep only the path: `${v#*://*}` would strip the shortest prefix, i.e. just "http://".
MAIL_PATH=$(printf '%s' "$validation_url" | sed -E 's#^[a-z]+://[^/]+##' || true)
wrong_loc=$(loc "$(header "${MAIL_H[@]}" "http://127.0.0.1:${MAIL_PORT}${PREFIX}/i/?c=user&a=validateEmail&username=alice&token=deadbeef")")
has "a wrong token is refused and bounces back to the validation page" "$wrong_loc" 'validateEmail'
is "…and leaves the token pending" \
	"$(docker exec frss-mail php -d error_reporting=0 -r '
		require "/var/www/FreshRSS/constants.php"; require LIB_PATH . "/lib_rss.php";
		$c = FreshRSS_UserConfiguration::getForUser("alice");
		echo $c !== null && $c->email_validation_token !== "" ? "yes" : "no";
	' 2>/dev/null || true)" "yes"
# Success is a redirect to the reader, not a 200: `Minz_Request::good()` forwards. What matters is
# that the reader it forwards to is inside the sub-directory.
good_loc=$(loc "$(header "${MAIL_H[@]}" "http://127.0.0.1:${MAIL_PORT}${MAIL_PATH}")")
has "following the mailed link forwards into the application" "$good_loc" "${PREFIX}/i/"
is "the token is cleared once the link is followed" \
	"$(docker exec frss-mail php -d error_reporting=0 -r '
		require "/var/www/FreshRSS/constants.php"; require LIB_PATH . "/lib_rss.php";
		$c = FreshRSS_UserConfiguration::getForUser("alice");
		echo $c !== null && $c->email_validation_token === "" ? "yes" : "no";
	' 2>/dev/null || true)" "yes"
is "the address itself is kept" \
	"$(docker exec frss-mail php -d error_reporting=0 -r '
		require "/var/www/FreshRSS/constants.php"; require LIB_PATH . "/lib_rss.php";
		$c = FreshRSS_UserConfiguration::getForUser("alice");
		echo $c !== null && $c->mail_login === "alice@example.invalid" ? "yes" : "no";
	' 2>/dev/null || true)" "yes"
# Once validated, following the same link again is a no-op rather than an error.
again_loc=$(loc "$(header "${MAIL_H[@]}" "http://127.0.0.1:${MAIL_PORT}${MAIL_PATH}")")
has "following it a second time is harmless" "$again_loc" "${PREFIX}/i/"

docker rm -f frss-mail smtp-sink >/dev/null 2>&1
rm -rf "$MAIL_STATE" "$DATA_M" 2>/dev/null || true

echo
echo
echo
echo "== 5i. allowed_hosts: refusing a spoofed Host header =="
# `allowed_hosts` is the Host-header-injection defence this patch adds. When it is set, a request
# that claims a host outside the list is still served, but every absolute URL it produces is built
# from an allowed host instead — so a poisoned link cannot make the application emit a URL pointing
# at the attacker's domain. It is opt-in and read from `data/config.php`; there is no environment
# variable for it.
#
# The RSS view is used as the probe because it is the page that emits an absolute URL built from the
# request (`<link>`); the reader page itself is entirely relative and would prove nothing.
ALLOW_PORT=18114
DATA_H="$(mktemp -d)"
ALLOW_TOKEN="testtoken123"
docker rm -f frss-hosts >/dev/null 2>&1
docker run -d --name frss-hosts --network "$NET" -p "${ALLOW_PORT}:80" \
	-e "FRESHRSS_PATH_PREFIX=${PREFIX}" -v "${DATA_H}:/var/www/FreshRSS/data" "$IMAGE" >/dev/null
wait_http "http://127.0.0.1:${ALLOW_PORT}${PREFIX}/i/?step=1" || true
sleep 1
docker exec frss-hosts php /var/www/FreshRSS/cli/do-install.php \
	--default-user alice --db-type sqlite --db-base /var/www/FreshRSS/data/db.sqlite \
	--auth-type none --api-enabled=true >/dev/null 2>&1 || true
docker exec frss-hosts php /var/www/FreshRSS/cli/create-user.php \
	--user alice --password dummy-password --token "$ALLOW_TOKEN" >/dev/null 2>&1 || true
docker exec frss-hosts sh -c 'chown -R :www-data /var/www/FreshRSS/data; chmod -R g+rwX /var/www/FreshRSS/data'
docker exec frss-hosts php -r '
	$f = "/var/www/FreshRSS/data/config.php";
	$c = file_get_contents($f);
	$c = str_replace("array (", "array (\x27allowed_hosts\x27 => [\x27a.example\x27, \x27b.example\x27],", $c);
	file_put_contents($f, $c);
' >/dev/null 2>&1
is "allowed_hosts was stored" \
	"$(docker exec frss-hosts php -r '$c=include "/var/www/FreshRSS/data/config.php";echo implode(",", $c["allowed_hosts"] ?? []);' 2>/dev/null)" 'a.example,b.example'

rss_for() { # rss_for <host>
	get -H "Host: $1" -H "X-Forwarded-Host: $1" -H 'X-Forwarded-Proto: https' \
		"http://127.0.0.1:${ALLOW_PORT}${PREFIX}/i/?a=rss&user=alice&token=${ALLOW_TOKEN}"
}
has "an allowed host is used to build the absolute URL" "$(rss_for a.example)" "<link>https://a.example${PREFIX}</link>"
has "…and so is the second allowed host"               "$(rss_for b.example)" "<link>https://b.example${PREFIX}</link>"

# A host that is not on the list is neither echoed nor used.
spoof=$(rss_for evil.example)
hasnt "a spoofed Host never reaches the output" "$spoof" 'evil.example'
has   "…absolute URLs fall back to an allowed host" "$spoof" "<link>https://a.example${PREFIX}</link>"

# With the list emptied the behaviour is the permissive default again.
docker exec frss-hosts php -r '
	$f = "/var/www/FreshRSS/data/config.php";
	$c = file_get_contents($f);
	$c = str_replace("\x27allowed_hosts\x27 => [\x27a.example\x27, \x27b.example\x27],", "\x27allowed_hosts\x27 => [],", $c);
	file_put_contents($f, $c);
' >/dev/null 2>&1
has "…and the spoofed host is used again over HTTP" "$(rss_for evil.example)" "<link>https://evil.example${PREFIX}</link>"

docker rm -f frss-hosts >/dev/null 2>&1
rm -rf "$DATA_H" 2>/dev/null || true

echo
echo "== 6. domain-root deployment keeps upstream behaviour"
ru=$(header -H 'Host: a.example' -H 'X-Forwarded-Host: a.example' -H 'X-Forwarded-Proto: https' \
	"http://127.0.0.1:${HTTPS_PORT}/i/?c=auth&a=login" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p' \
	| sed -n 's/.*redirect_uri=\([^&]*\).*/\1/p' \
	| python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.stdin.read().strip()))' 2>/dev/null || echo '')
is "root redirect_uri has no prefix"  "$ru" "https://a.example/i/oidc/"
is "root landing serves"              "$(status "http://127.0.0.1:${HTTPS_PORT}/")" 302

# ---------------------------------------------------------------------------------------------
echo
echo "== result: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
