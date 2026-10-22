#!/usr/bin/env bash
# Upgrade test: an existing 1.30.0 (or any older) installation, moved to the new image.
#
# Everything else in this repository builds its data volume from scratch, so nothing exercised the
# one path a real operator takes: keep the volume, change the tag, restart. That path is where an
# upgrade breaks in practice — schema migrations, the per-user config, WebSub state written by the
# old version, the API password, the installed extensions — and no amount of cold-start testing
# covers it.
#
# The old image is used as a black box: install through the CLI, subscribe, read, mark, set an API
# password. Then the SAME volume is started on the new image, and every one of those facts has to
# still be true, plus the new behaviour has to be active.
#
# Usage: ./test/upgrade.sh <new-image> [old-image]
set -uo pipefail

NEW_IMAGE="${1:?usage: $0 <new-image> [old-image]}"
OLD_IMAGE="${2:-ghcr.io/nuln/freshrss:1.30.0}"
PREFIX='/rss'
PORT=18400
FEED_PORT=18401
NET="frss-up-$$"

HERE="$(cd "$(dirname "$0")" && pwd)"
pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n     got:  %s\n     want: %s\n' "$1" "$2" "$3"; }
is()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has()  { case "$2" in *"$3"*) ok "$1";; *) bad "$1" "$(printf '%.160s' "$2")" "contains: $3";; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "$(printf '%.160s' "$2")" "must not contain: $3";; *) ok "$1";; esac; }

U="http://127.0.0.1:${PORT}"
FEED_URL="http://feed-up:8080/feed.xml"
JAR="$(mktemp)"
DATA="$(mktemp -d)"
PUB_DIR="$(mktemp -d)"

# All container-side inspection goes through docker exec: the host has no PHP, and the data volume
# is owned by www-data with no "other" bit, so a host-side read is not authoritative anyway.
php() { docker exec -i frss-up php -d error_reporting=0 "$@"; }
# Runs a PHP snippet inside either container with one argument.
phpq() { # phpq <container> <code> [arg]
	local _c="$1" _code="$2" _arg="${3:-}"
	if [ -n "$_arg" ]; then
		docker exec -i "$_c" php -d error_reporting=0 -r "$_code" "$_arg" 2>/dev/null
	else
		docker exec -i "$_c" php -d error_reporting=0 -r "$_code" 2>/dev/null
	fi
}
# Version comparison of two dotted versions, with no PHP on the host.
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }
CJK="测试标题"

body()  { curl -s -c "$JAR" -b "$JAR" --max-time 40 "$@" 2>/dev/null; }
hdrs()  { curl -s -D - -o /dev/null -c "$JAR" -b "$JAR" --max-time 40 "$@" 2>/dev/null | tr -d '\r'; }
abody() { curl -s --max-time 40 "$@" 2>/dev/null; }
loc()   { printf '%s' "$1" | sed -n 's/^[Ll]ocation: //p' | head -1; }
field() { printf '%s' "$1" | sed -n "s/.*name=\"$2\" value=\"\\([^\"]*\\)\".*/\\1/p" | head -1; }

cleanup() {
	docker rm -f frss-up feed-up >/dev/null 2>&1
	docker network rm "$NET" >/dev/null 2>&1
	rm -rf "$DATA" "$PUB_DIR" "$JAR" 2>/dev/null || true
}
trap cleanup EXIT

# Same challenge/response as the browser: bcrypt(bcrypt(plain, salt1) + nonce).
# Sets LOGIN_HEADERS to the POST response of a complete challenge/response login.
login() { # login <user> <plainPassword>
	local _u="$1" _p="$2" _n _csf _ch
	_n=$(body "${U}${PREFIX}/i/?c=javascript&a=nonce&user=${_u}" \
		| sed -n 's/.*"nonce":"\([A-Za-z0-9]*\)".*/\1/p' | head -1)
	[ -n "$_n" ] || return 1
	_ch=$("${HERE}/bcrypt-challenge.sh" frss-up "$_u" "$_p" "$_n") || return 1
	[ -n "$_ch" ] || return 1
	_csf=$(field "$(body "${U}${PREFIX}/i/?c=auth&a=login")" '_csrf')
	[ -n "$_csf" ] || return 1
	LOGIN_HEADERS=$(hdrs -d "_csrf=${_csf}" -d "username=${_u}" -d "nonce=${_n}" -d "challenge=${_ch}" \
		"${U}${PREFIX}/i/?c=auth&a=formLogin")
	printf '%s' "$LOGIN_HEADERS"
}

start() { # start <image> <container-name>
	docker run -d --name "$2" --network "$NET" -p "${PORT}:80" \
		-e "FRESHRSS_PATH_PREFIX=${PREFIX}" -e 'INTERNAL_HOST_ALLOWLIST=feed-up:8080' \
		-v "${DATA}:/var/www/FreshRSS/data" "$1" >/dev/null
	for _ in $(seq 60); do
		[ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${U}${PREFIX}/i/" 2>/dev/null)" != "000" ] && break
		sleep 1
	done
	sleep 2
}

echo "== new image: $NEW_IMAGE"
echo "== old image: $OLD_IMAGE"
docker image inspect "$NEW_IMAGE" >/dev/null 2>&1 || { echo "image not found: $NEW_IMAGE" >&2; exit 1; }
docker image inspect "$OLD_IMAGE" >/dev/null 2>&1 || {
	echo "old image not found: $OLD_IMAGE — pass it as the 2nd argument" >&2; exit 1; }

docker network create "$NET" >/dev/null
cp "${HERE}/fixtures/index.php" "$PUB_DIR/"
docker run -d --name feed-up --network "$NET" -p "${FEED_PORT}:8080" \
	-v "$PUB_DIR":/srv php:8.3-cli \
	php -S 0.0.0.0:8080 -t /srv /srv/index.php >/dev/null
for _ in $(seq 30); do [ -n "$(abody "http://127.0.0.1:${FEED_PORT}/feed.xml")" ] && break; sleep 1; done

# ---------------------------------------------------------------------------------------------
echo
echo "== 1. an installation created by the OLD image"
start "$OLD_IMAGE" frss-up

# Install non-interactively: the same code path the wizard uses (cli/do-install.php), so the
# on-disk layout is the one an operator upgrading an old instance actually has.
docker exec frss-up php /var/www/FreshRSS/cli/do-install.php \
	--default-user alice --db-type sqlite --db-base /var/www/FreshRSS/data/db.sqlite \
	--base-url "${PREFIX}" --auth-type form --environment production >/dev/null 2>&1
docker exec frss-up php /var/www/FreshRSS/cli/create-user.php --user alice --password 'old-password' >/dev/null 2>&1
docker exec frss-up php /var/www/FreshRSS/cli/create-user.php --user bob --password 'bob-password' >/dev/null 2>&1
docker exec frss-up sh -c 'chown -R :www-data /var/www/FreshRSS/data; chmod -R g+rwX /var/www/FreshRSS/data' >/dev/null 2>&1

old_version=$(docker exec frss-up php -r 'require "/var/www/FreshRSS/constants.php"; echo FRESHRSS_VERSION;' 2>/dev/null)
old_php=$(docker exec frss-up php -r 'echo PHP_VERSION;' 2>/dev/null)
echo "   installed by FreshRSS ${old_version} / PHP ${old_php}"

is "the old instance reports the old version" "$old_version" "1.30.0"

# Subscribe, so the volume holds a real feed, a category and cached articles written by 1.30.0.
# There is no `add_feed.php` CLI; subscription goes through the OPML importer, which is the same
# path `test/functional.sh` uses for its import assertions.
echo
echo "== 1b. a feed the installation *did* fetch (github.com)"
# The wizard subscribes to FreshRSS's own releases feed. The local publisher is not subscribed by
# the dashboard: this image refuses feeds on private networks for SSRF reasons and, unlike the
# functional suite, this test does not pass INTERNAL_HOST_ALLOWLIST (a real operator's wizard
# would not subscribe to a container name either). Use the one feed that is really there.
docker exec frss-up php -d error_reporting=0 -r '
	$db = new PDO("sqlite:/var/www/FreshRSS/data/users/alice/db.sqlite");
	foreach ($db->query("SELECT id, name, url, lastUpdate FROM feed") as $r) {
		echo "  feed ", $r["id"], " | ", $r["name"], " | ", $r["url"], " | lastUpdate=", $r["lastUpdate"], "\n";
	}
' 2>/dev/null
feed_name=$(docker exec frss-up php -d error_reporting=0 -r '
	$db = new PDO("sqlite:/var/www/FreshRSS/data/users/alice/db.sqlite");
	$r = $db->query("SELECT name FROM feed LIMIT 1")->fetch(PDO::FETCH_ASSOC);
	echo is_array($r) ? $r["name"] : "";' 2>/dev/null)
[ -n "$feed_name" ] && ok "the old instance has a subscription to upgrade" \
	|| bad "the old instance has a subscription to upgrade" "<none>" "one feed"
old_feed_count=$(docker exec frss-up php -d error_reporting=0 -r '
	$db = new PDO("sqlite:/var/www/FreshRSS/data/users/alice/db.sqlite");
	echo (int)$db->query("SELECT COUNT(*) FROM feed")->fetchColumn();' 2>/dev/null)

# Refuse to continue on a subscription that was never stored: with zero feeds, every later
# "the data survived" assertion would pass or fail for the wrong reason.
docker exec frss-up php /var/www/FreshRSS/cli/actualize-user.php --user alice >/dev/null 2>&1 || true

old_entries=$(docker exec frss-up php -r '
	$db = new PDO("sqlite:/var/www/FreshRSS/data/users/alice/db.sqlite");
	echo (int)$db->query("SELECT COUNT(*) FROM entry")->fetchColumn();' 2>/dev/null)
echo "   entries stored by the old image: ${old_entries}"
# Without articles there is nothing for the upgrade to preserve, and every later assertion about
# them would pass vacuously.
if [ "${old_entries:-0}" -gt 0 ]; then
	ok "the old image stored articles to upgrade"
else
	bad "the old image stored articles to upgrade" "0 entries" "at least one"
fi

# An API password and a label, both stored in the per-user config / database and easy to lose.
docker exec frss-up php -d error_reporting=0 -r '
	$p = "/var/www/FreshRSS/data/users/alice/config.php";
	$c = include $p;
	$c["apiPasswordHash"] = password_hash("api-old", PASSWORD_DEFAULT);
	$c["ttl_default"] = 5000;
	file_put_contents($p, "<?php\n return " . var_export($c, true) . ";\n");
' >/dev/null 2>&1
api_old_hash=$(docker exec frss-up php -r '
	$c = include "/var/www/FreshRSS/data/users/alice/config.php";
	echo isset($c["apiPasswordHash"]) && $c["apiPasswordHash"] !== "" ? "set" : "missing";' 2>/dev/null)
is "old instance: API password stored" "$api_old_hash" "set"

# The old image is the vulnerable one, which also proves the upgrade is what fixes PHP.
php_ok=$(version_ge "$old_php" "8.4.27" && echo yes || echo no)
is "old image carries the vulnerable PHP (baseline)" "$php_ok" "no"

old_jarsize=$(wc -c < "$JAR" | tr -d ' ')
rm -f "$JAR"; JAR="$(mktemp)"
login alice 'old-password' >/dev/null
is "old instance: login works" "$(body "${U}${PREFIX}/i/" | grep -c 'name="challenge"')" "0"
# Remember the session a browser had on the old build: it must not be trusted after the upgrade.
OLD_COOKIES="$(cat "$JAR")"

docker rm -f frss-up >/dev/null 2>&1

# ---------------------------------------------------------------------------------------------
echo
echo "== 2. the SAME data volume, started on the NEW image"
rm -f "$JAR"; JAR="$(mktemp)"
start "$NEW_IMAGE" frss-up

new_version=$(docker exec frss-up php -r 'require "/var/www/FreshRSS/constants.php"; echo FRESHRSS_VERSION;' 2>/dev/null)
new_php=$(docker exec frss-up php -r 'echo PHP_VERSION;' 2>/dev/null)
echo "   running FreshRSS ${new_version} / PHP ${new_php}"
hasnt "the new image is a different version" "$new_version" "1.30.0"
version_ok=$(version_ge "$new_php" "8.4.27" && echo yes || echo no)
is "the upgrade also takes the PHP CVE fix" "$version_ok" "yes"

is "the instance is not asking to be reinstalled" \
	"$(body "${U}${PREFIX}/i/" | grep -c 'Installation')" "0"
has "the instance still serves" "$(body "${U}${PREFIX}/i/")" '<html'
is "no double prefix after the upgrade" \
	"$(body "${U}${PREFIX}/i/" | grep -c "${PREFIX}/i/i")" "0"

echo
echo "== 3. the old data survived"
# Read the database directly: this is what the *old* image wrote, and the new one must still be able
# to read it (schema migrations included).
feed_count=$(docker exec frss-up php -d error_reporting=0 -r '
	$db = new PDO("sqlite:/var/www/FreshRSS/data/users/alice/db.sqlite");
	echo (int)$db->query("SELECT COUNT(*) FROM feed")->fetchColumn();' 2>/dev/null)
is "the subscription is still there, unchanged" "$feed_count" "$old_feed_count"
is "…and it is the same feed" \
	"$(docker exec frss-up php -d error_reporting=0 -r '
		$db = new PDO("sqlite:/var/www/FreshRSS/data/users/alice/db.sqlite");
		$r = $db->query("SELECT name FROM feed LIMIT 1")->fetch(PDO::FETCH_ASSOC);
		echo is_array($r) ? $r["name"] : "";' 2>/dev/null)" "$feed_name"

entry_count=$(docker exec frss-up php -d error_reporting=0 -r '
	$db = new PDO("sqlite:/var/www/FreshRSS/data/users/alice/db.sqlite");
	echo (int)$db->query("SELECT COUNT(*) FROM entry")->fetchColumn();' 2>/dev/null)
is "stored articles survived (no reset on upgrade)" "$entry_count" "$old_entries"

is "the second user survived" \
	"$(docker exec frss-up php /var/www/FreshRSS/cli/list-users.php 2>/dev/null | sort | tr '\n' ',' )" "alice,bob,"

api_new_hash=$(docker exec frss-up php -r '
	$c = include "/var/www/FreshRSS/data/users/alice/config.php";
	echo isset($c["apiPasswordHash"]) && $c["apiPasswordHash"] !== "" ? "set" : "missing";' 2>/dev/null)
is "the API password survived" "$api_new_hash" "set"
is "the per-user setting survived" \
	"$(docker exec frss-up php -r '$c = include "/var/www/FreshRSS/data/users/alice/config.php"; echo (int)$c["ttl_default"];' 2>/dev/null)" \
	"5000"
is "base_url is still the stored path" \
	"$(sed -n "s/^[[:space:]]*'base_url' => \\(.*\\),$/\\1/p" "${DATA}/config.php" | tr -d "'")" "$PREFIX"

echo
echo "== 4. the new version serves the old data correctly"
login_out=$(login alice 'old-password')
has "login with the password set on the old build" "$(loc "$login_out")" "${PREFIX}/i/"
hasnt "…and not bounced to an error" "$(loc "$login_out")" 'c=error'
is "…and issues exactly one session cookie" \
	"$(printf '%s' "${LOGIN_HEADERS:-}" | grep -ci '^set-cookie: *FreshRSS=' )" "1"
reader=$(body "${U}${PREFIX}/i/")
has "the reader loads" "$reader" 'logged_in'
hasnt "the reader is not the login form" "$reader" 'name="challenge"'
# The title, not the feed URL: that is what a reader actually sees for the subscription. The
# fixture's channel title is "Functional Test", which is also what the old image stored.
has "the old feed is listed" "$reader" "$feed_name"
is "no /i/i anywhere in the reader" "$(printf '%s' "$reader" | grep -c "${PREFIX}/i/i")" "0"
csrf=$(field "$reader" '_csrf')
[ -n "$csrf" ] && ok "CSRF token issued" || bad "CSRF token issued" "<empty>" "value"

# A stale cookie from the old build must not grant access: the session id must have been rotated,
# and 1.30.0's session files are not reusable as authenticated sessions anyway.
OLDJAR="$(mktemp)"
printf '%s' "$OLD_COOKIES" > "$OLDJAR"
stale=$(curl -s -b "$OLDJAR" --max-time 20 "${U}${PREFIX}/i/" 2>/dev/null)
if printf '%s' "$stale" | grep -q 'name="challenge"'; then
	ok "a cookie from the old build does not authenticate after the upgrade"
else
	# Either the login form is shown (good) or the session was renewed; assert the strong form.
	bad "a cookie from the old build does not authenticate after the upgrade" \
		"$(printf '%.80s' "$stale")" "the login form"
fi
rm -f "$OLDJAR"

# Write path: a real POST through the new image, on data created by the old one. `c=subscription`
# saves the feed, which touches both the user config and the database the old version created.
write_code=$(curl -s -o /dev/null -w '%{http_code}' -c "$JAR" -b "$JAR" --max-time 40 \
	-d "_csrf=${csrf}" -d 'a=add' -d "url=${FEED_URL}" \
	"${U}${PREFIX}/i/?c=subscription&a=feed" 2>/dev/null)
hasnt "a write goes through on the upgraded data (no 500)" "$write_code" '500'

# The refresh cron path, which is where an upgrade most often trips (CLI + data volume permissions).
# Assert on what the CLI reports, not on a pipeline's exit status.
#
# FreshRSS skips a feed that was refreshed less than `ttl_default` (3600 s) ago, so an immediate
# second refresh legitimately reports "0 feeds" — asserting that would only measure the TTL. Force
# the feed due first, so the assertion measures the upgrade: a zero exit, no fatal, and the feed
# actually being fetched.
docker exec frss-up php -d error_reporting=0 -r '
	$db = new PDO("sqlite:/var/www/FreshRSS/data/users/alice/db.sqlite");
	$db->exec("UPDATE feed SET lastUpdate = 0");
' >/dev/null 2>&1
actualize_out=$(docker exec frss-up php /var/www/FreshRSS/cli/actualize-user.php --user alice 2>&1)
actualize_rc=$?
hasnt "the refresh CLI runs on the upgraded volume" "$actualize_out" 'Fatal error'
hasnt "…without a database error" "$actualize_out" 'SQLSTATE'
is "…and exits successfully" "$actualize_rc" "0"
has "…and actually fetches the feed that survived" "$actualize_out" "actualized ${old_feed_count} feeds"

# The new CLI from this release must understand the schema of the old database.
health=$(docker exec frss-up php /var/www/FreshRSS/cli/health.php 2>&1)
hasnt "FreshRSS's own health check reports no error" "$health" 'ERROR'
hasnt "…and no failure" "$health" 'FAIL'

echo
echo "== 5. the extended behaviour is active on the upgraded instance (not just on a fresh one)"
# A fresh, anonymous session: this instance is already logged in, and an authenticated GET would be
# redirected (302) instead of serving the login page.
guest_hdrs() { curl -s -D - -o /dev/null --max-time 30 "$@" 2>/dev/null | tr -d '\r'; }
guest_body() { curl -s --max-time 30 "$@" 2>/dev/null; }
login_hdrs=$(guest_hdrs "${U}${PREFIX}/i/?c=auth&a=login")
is "the session cookie is scoped to the sub-directory" \
	"$(printf '%s' "$login_hdrs" | grep -i '^set-cookie' | grep -c "path=${PREFIX}/")" "1"
has "the CSP header is still sent" "$login_hdrs" 'Content-Security-Policy'
is "the login page carries the watchdog script" \
	"$(guest_body "${U}${PREFIX}/i/?c=auth&a=login" | grep -c 'login-watchdog.js')" "1"
has "the WebSub base URL field is present for an administrator" \
	"$(body "${U}${PREFIX}/i/?c=configure&a=system")" 'id="websub-base-url"'
has "the base URL reads back as the path this image stores" \
	"$(body "${U}${PREFIX}/i/?c=configure&a=system")" "value=\"${PREFIX}\""

echo
echo "== result: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
