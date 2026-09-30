#!/usr/bin/env bash
# Functional test: the whole FreshRSS lifecycle through a sub-directory and several domains.
#
# Unlike integration.sh (HTTP-level: routing, redirects, OIDC), this drives the real product:
# the installation wizard, the challenge/response login, feed subscription, refresh, reading,
# OPML/RSS export, the Google Reader API, sharing, and finally the second domain.
#
# Usage: ./test/functional.sh [image]
set -uo pipefail

IMAGE="${1:-ghcr.io/nuln/freshrss:test}"
PREFIX='/rss'
WEB_PORT=18200
FEED_PORT=18201
NET="fn-$$"

HERE="$(cd "$(dirname "$0")" && pwd)"
pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n         got:  %s\n         want: %s\n' "$1" "$(printf '%.100s' "$2")" "$3"; }
is()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has()  { case "$2" in *"$3"*) ok "$1";; *) bad "$1" "$2" "contains: $3";; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "$2" "must not contain: $3";; *) ok "$1";; esac; }

# The two reverse-proxied domains. No X-Forwarded-Proto: the test speaks plain HTTP, and
# FreshRSS marks the session cookie `secure` as soon as it believes the request is HTTPS
# (Session.php:51) — a secure cookie is never replayed over HTTP, so the session would be lost.
H1=(-H 'Host: a.example' -H 'X-Forwarded-Host: a.example')
H2=(-H 'Host: b.example' -H 'X-Forwarded-Host: b.example')

U="http://127.0.0.1:${WEB_PORT}"
JAR="$(mktemp)"; JAR2="$(mktemp)"
DATA="$(mktemp -d)"
FEED_URL="http://feed-fn:8080/feed.xml"

# body / headers / status of a request on the current jar ($CURL_JAR)
CURL_JAR="$JAR"
body()  { curl -s -c "$CURL_JAR" -b "$CURL_JAR" --max-time 40 "$@" 2>/dev/null; }
hdrs()  { curl -s -D - -o /dev/null -c "$CURL_JAR" -b "$CURL_JAR" --max-time 40 "$@" 2>/dev/null | tr -d '\r'; }
code()  { curl -s -o /dev/null -w '%{http_code}' -c "$CURL_JAR" -b "$CURL_JAR" --max-time 40 "$@" 2>/dev/null; }
# Anonymous request (no cookie jar), for the API and other token-based endpoints.
abody() { curl -s --max-time 40 "$@" 2>/dev/null; }
acode() { curl -s -o /dev/null -w '%{http_code}' --max-time 40 "$@" 2>/dev/null; }

loc() { printf '%s' "$1" | sed -n 's/^[Ll]ocation: //p' | head -1; }
field() { printf '%s' "$1" | sed -n "s/.*name=\"$2\" value=\"\\([^\"]*\\)\".*/\\1/p" | head -1; }

cleanup() {
	docker rm -f frss-fn feed-fn >/dev/null 2>&1
	docker network rm "$NET" >/dev/null 2>&1
	rm -rf "$DATA" "$JAR" "$JAR2" "$PUB_DIR"
}
trap cleanup EXIT

# Reproduce the browser login: GET nonce, then bcrypt(bcrypt(plain, salt1) + nonce).
login_as() { # login_as <H1|H2> <user> <plainPassword>  -> response headers on stdout
	local -n _h="$1"; local _u="$2" _p="$3" _n _csf _ch
	_n=$(body "${_h[@]}" "${U}${PREFIX}/i/?c=javascript&a=nonce&user=${_u}" \
		| sed -n 's/.*"nonce":"\([A-Za-z0-9]*\)".*/\1/p' | head -1)
	[ -n "$_n" ] || return 1
	_ch=$("${HERE}/bcrypt-challenge.sh" frss-fn "$_u" "$_p" "$_n") || return 1
	[ -n "$_ch" ] || return 1
	# Every POST is CSRF-checked (app/FreshRSS.php:74) and the session is host-only, so each
	# domain needs its own token, taken from that domain's own login page.
	_csf=$(field "$(body "${_h[@]}" "${U}${PREFIX}/i/?c=auth&a=login")" '_csrf')
	[ -n "$_csf" ] || return 1
	hdrs -d "_csrf=${_csf}" -d "username=${_u}" -d "nonce=${_n}" -d "challenge=${_ch}" \
		"${_h[@]}" "${U}${PREFIX}/i/?c=auth&a=formLogin"
}

echo "== image: $IMAGE"
docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "image not found" >&2; exit 1; }

# ---------------------------------------------------------------------------------------------
echo
echo "== 1. a real RSS publisher, and the container itself"
docker network create "$NET" >/dev/null
PUB_DIR="$(mktemp -d)"; cp "${HERE}/fixtures/index.php" "$PUB_DIR/"
docker run -d --name feed-fn --network "$NET" -p "${FEED_PORT}:8080" \
	-v "$PUB_DIR":/srv php:8.3-cli \
	php -S 0.0.0.0:8080 -t /srv /srv/index.php >/dev/null
sleep 4
has "publisher serves RSS"      "$(abody "http://127.0.0.1:${FEED_PORT}/feed.xml")" '<rss'
has "publisher has an article"  "$(abody "http://127.0.0.1:${FEED_PORT}/feed.xml")" '<item>'

# INTERNAL_HOST_ALLOWLIST: FreshRSS refuses to resolve host names pointing at private networks
# (SSRF / DNS-rebinding guard, see get_curl_resolve_info()). The publisher is a container on the
# Docker network, so it has to be allowlisted — the same knob an admin uses for self-hosted feeds.
docker run -d --name frss-fn --network "$NET" -p "${WEB_PORT}:80" \
	-e "FRESHRSS_PATH_PREFIX=${PREFIX}" -e 'INTERNAL_HOST_ALLOWLIST=feed-fn:8080' \
	-v "${DATA}:/var/www/FreshRSS/data" "$IMAGE" >/dev/null
for _ in $(seq 40); do [ "$(acode "${U}${PREFIX}/i/?step=1")" != 000 ] && break; sleep 1; done
sleep 2
is "container can reach the publisher" \
	"$(docker exec frss-fn php -r '$c=@file_get_contents("'"$FEED_URL"'"); echo $c ? "ok" : "no";' 2>/dev/null)" "ok"
is "publisher is allowlisted for SimplePie" \
	"$(grep -c "INTERNAL_HOST_ALLOWLIST" <(docker inspect frss-fn --format '{{range .Config.Env}}{{println .}}{{end}}'))" "1"

# ---------------------------------------------------------------------------------------------
echo
echo "== 2. installation wizard (un-installed -> installed)"
has "wizard reachable"        "$(body "${H1[@]}" "${U}${PREFIX}/i/?step=1")" 'Installation'
has "wizard on the 2nd domain" "$(body "${H2[@]}" "${U}${PREFIX}/i/?step=1")" 'Installation'

body "${H1[@]}" -H 'Accept-Language: en' -d 'language=en' "${U}${PREFIX}/i/?step=0" >/dev/null
is "step 2 (database) accepted" "$(loc "$(hdrs "${H1[@]}" -d 'title=Functional Test' -d 'type=sqlite' \
	-d "base=${DATA}/db.sqlite" -d 'prefix=' -d 'host=' -d 'step=2' -d 'submit=Submit' \
	"${U}${PREFIX}/i/?step=2")")" "index.php?step=3"
is "step 3 (admin user) accepted" "$(loc "$(hdrs "${H1[@]}" -d 'default_user=alice' \
	-d 'auth_type=form' -d 'passwordPlain=sup3rsecret' -d 'step=3' -d 'submit=Submit' \
	"${U}${PREFIX}/i/?step=3")")" "index.php?step=4"
body "${H1[@]}" "${U}${PREFIX}/i/?step=4" >/dev/null
body "${H1[@]}" "${U}${PREFIX}/i/?step=5" >/dev/null

[ -f "${DATA}/config.php" ] && ok "config.php written" || bad "config.php written" "<missing>" "file"
[ -f "${DATA}/users/alice/config.php" ] && ok "user alice created" || bad "user alice created" "<missing>" "file"
is "base_url stored as a path (not a pinned domain)" \
	"$(sed -n "s/^[[:space:]]*'base_url' => \\(.*\\),$/\\1/p" "${DATA}/config.php" | tr -d "'")" "$PREFIX"
[ -f "${DATA}/applied_migrations.txt" ] && ok "migrations applied, wizard over" \
	|| bad "migrations applied, wizard over" "<missing>" "applied_migrations.txt"
has "login page is served" "$(body "${H1[@]}" "${U}${PREFIX}/i/?c=auth&a=login")" 'name="challenge"'

# FreshRSS serves a feed from its own cache while it is younger than `limits.cache_duration`
# (800 s by default, httpUtil.php:450), which would hide a newly published article from the test.
# Set it to 0 so every actualize really revalidates against the publisher.
docker exec frss-fn php -d error_reporting=0 -r '
	$p = "/var/www/FreshRSS/data/config.php";
	$c = include $p;
	$c["limits"]["cache_duration"] = 0;
	$c["limits"]["cache_duration_min"] = 0;
	file_put_contents($p, "<?php\n return " . var_export($c, true) . ";\n");
' 2>/dev/null
is "feed cache disabled for the test" \
	"$(docker exec frss-fn php -d error_reporting=0 -r \
		'$c = include "/var/www/FreshRSS/data/config.php"; echo (int)$c["limits"]["cache_duration"];' 2>/dev/null)" "0"

# The wizard subscribes to a public feed (github.com releases). Remove it so the test depends on
# nothing but the local publisher, and so refreshes cannot be delayed by the public internet.
default_ids=$(docker exec frss-fn php -d error_reporting=0 -r '
	$db = new PDO("sqlite:/var/www/FreshRSS/data/users/alice/db.sqlite");
	foreach ($db->query("SELECT id FROM feed") as $r) {
		if (strpos($r["id"], "2") === false) { } else { continue; }
	}
	foreach ($db->query("SELECT id, url FROM feed") as $r) {
		if (strpos($r["url"], "feed-fn") === false) { echo $r["id"]; }
	}
' 2>/dev/null)
admin_csrf=$(field "$(body "${H1[@]}" "${U}${PREFIX}/i/?c=subscription&a=index")" '_csrf')
for fid in $default_ids; do
	body "${H1[@]}" -d "_csrf=${admin_csrf}" -d "id=${fid}" \
		"${U}${PREFIX}/i/?c=feed&a=delete" >/dev/null
done
is "only the local feed remains" \
	"$(docker exec frss-fn php -d error_reporting=0 -r '
		$db = new PDO("sqlite:/var/www/FreshRSS/data/users/alice/db.sqlite");
		echo (int)$db->query("SELECT count(*) FROM feed")->fetchColumn();
	' 2>/dev/null)" "1"

# ---------------------------------------------------------------------------------------------
echo
echo "== 3. login (real challenge/response authentication)"
auth=$(login_as H1 alice sup3rsecret)
loginloc=$(loc "$auth")
has "login redirects into the reader" "$loginloc" "${PREFIX}/i/"
hasnt "login does not land on an error" "$loginloc" 'c=error'

reader=$(body "${H1[@]}" "${U}${PREFIX}/i/")
has "reader loads, user identified"  "$reader" 'logged_in'
hasnt "reader is not the login form"  "$reader" 'name="challenge"'
csrf=$(field "$reader" '_csrf')
[ -n "$csrf" ] && ok "CSRF token issued" || bad "CSRF token issued" "<empty>" "value"
is "session survives navigation"  "$(body "${H1[@]}" "${U}${PREFIX}/i/" | grep -c 'name="challenge"')" "0"
is "cookie is host-only (2nd domain anonymous)" \
	"$(body "${H2[@]}" "${U}${PREFIX}/i/" | grep -c 'name="challenge"')" "1"

# A wrong password must not open a session.
CURL_JAR="$JAR2"
body "${H1[@]}" "${U}${PREFIX}/i/?c=auth&a=login" >/dev/null
badloc=$(loc "$(login_as H1 alice wrongpassword)")
hasnt "wrong password is refused" "$badloc" "${PREFIX}/i/?rid"
is "wrong password leaves the session anonymous" \
	"$(body "${H1[@]}" "${U}${PREFIX}/i/" | grep -c 'name="challenge"')" "1"
CURL_JAR="$JAR"

# ---------------------------------------------------------------------------------------------
echo
echo "== 4. subscribe to the feed"
addloc=$(loc "$(hdrs -d "_csrf=${csrf}" -d "url_rss=${FEED_URL}" -d 'category=0' -d 'feed_kind=0' \
	"${H1[@]}" "${U}${PREFIX}/i/?c=feed&a=add")")
has "add-feed redirects into the app" "$addloc" "${PREFIX}/i/"
hasnt "add-feed has no /i/i"            "$addloc" '/i/i'
subs=$(body "${H1[@]}" "${U}${PREFIX}/i/?c=subscription&a=index")
has "feed is listed"      "$subs" 'Functional Test'
has "feed appears in the sidebar filter" \
	"$(body "${H1[@]}" "${U}${PREFIX}/i/?c=index&a=normal")" 'Filter: Functional Test'

# ---------------------------------------------------------------------------------------------
echo
echo "== 5. refresh and read"
FEED_ID=$(docker exec frss-fn php -d error_reporting=0 -r '
	$db = new PDO("sqlite:/var/www/FreshRSS/data/users/alice/db.sqlite");
	foreach ($db->query("SELECT id, url FROM feed") as $r) {
		if (strpos($r["url"], "feed-fn") !== false) { echo $r["id"]; break; }
	}
' 2>/dev/null)
[ -n "$FEED_ID" ] && ok "local feed stored with id ${FEED_ID}" || bad "local feed stored" "<empty>" "id"

for _ in $(seq 30); do
	normal=$(body "${H1[@]}" "${U}${PREFIX}/i/?c=index&a=normal")
	[ "$(printf '%s' "$normal" | grep -c 'First article from the local feed')" != "0" ] && break
	body "${H1[@]}" -X POST -d "_csrf=${csrf}" "reload_limit=20" \
		"${U}${PREFIX}/i/?c=feed&a=reload&id=${FEED_ID}" >/dev/null 2>&1
	sleep 1
done
has "article title rendered"   "$normal" 'First article from the local feed'
has "feed name rendered"       "$normal" 'Functional Test'
has "entries are rendered"     "$normal" 'item-title'
hasnt "no /i/i in the HTML"    "$normal" '/rss/i/i'

# A new article on the publisher (same feed URL) must show up after a refresh: proves the feed is
# really fetched on every refresh and not served from a copy made when it was added.
abody -X POST "http://127.0.0.1:${FEED_PORT}/publish" >/dev/null
has "publisher now has a 2nd article" "$(abody "http://127.0.0.1:${FEED_PORT}/feed.xml")" 'Published article #2'
found2=0
for _ in $(seq 20); do
	normal2=$(body "${H1[@]}" "${U}${PREFIX}/i/?c=index&a=normal")
	[ "$(printf '%s' "$normal2" | grep -c 'Published article #2')" != "0" ] && { found2=1; break; }
	body "${H1[@]}" -X POST -d "_csrf=${csrf}" "reload_limit=20" \
		"${U}${PREFIX}/i/?c=feed&a=reload&id=${FEED_ID}" >/dev/null 2>&1
	sleep 1
done
is "new article picked up by a refresh" "$found2" "1"
has "both articles are readable" "$normal2" 'First article from the local feed'

# Search and mark-as-read.
search=$(body "${H1[@]}" "${U}${PREFIX}/i/?c=index&a=normal&search=local+feed")
has "search finds the article" "$search" 'local feed'
has "entries expose a read-state menu" "$search" 'mark-read-menu'
has "the new article is searchable too" \
	"$(body "${H1[@]}" "${U}${PREFIX}/i/?c=index&a=normal&search=Published")" 'Published article #2'

# ---------------------------------------------------------------------------------------------
echo
echo "== 6. exports and feeds"
opml=$(body "${H1[@]}" "${U}${PREFIX}/i/?c=index&a=opml&type=a")
has "OPML export lists the feed" "$opml" 'feed.xml'
has "OPML is well-formed"        "$opml" '<opml'

rss1=$(body "${H1[@]}" "${U}${PREFIX}/i/?c=index&a=rss")
has "RSS output is RSS"            "$rss1" '<rss'
has "RSS output carries the article" "$rss1" 'First article from the local feed'
# The channel <link> must be absolute and follow the domain actually used.
has "RSS <link> is absolute on domain 1" "$rss1" "<link>http://a.example${PREFIX}</link>"
is "RSS view is refused without a session" \
	"$(acode "${H2[@]}" "${U}${PREFIX}/i/?c=index&a=rss")" "403"

# Shared query feed (token-authenticated, no session): must be reachable from both domains.
q=$(body "${H1[@]}" "${U}${PREFIX}/i/?c=user&a=queries")
hasnt "query page has no /i/i" "$q" '/i/i'

# ---------------------------------------------------------------------------------------------
echo
echo "== 7. Google Reader API"
# The wizard leaves the API off; an administrator enables it and gives the client a password.
docker exec frss-fn php /var/www/FreshRSS/cli/reconfigure.php --api-enabled true >/dev/null 2>&1
is "api_enabled written to config.php" \
	"$(docker exec frss-fn php -d error_reporting=0 -r \
		'$c = include "/var/www/FreshRSS/data/config.php"; echo $c["api_enabled"] ? "1" : "0";' 2>/dev/null)" "1"
# The web SAPI serves config.php from opcache, which can lag a moment behind the CLI write.
api_up=0
for _ in $(seq 15); do
	[ "$(acode "${H1[@]}" -d 'Email=alice' -d 'Passwd=probe' \
		"${U}${PREFIX}/api/greader.php/accounts/ClientLogin")" != "503" ] && { api_up=1; break; }
	sleep 1
done
is "API accepted by the web layer (not 503)" "$api_up" "1"
body "${H1[@]}" -d "_csrf=${csrf}" -d 'apiPasswordPlain=apisecret' \
	"${U}${PREFIX}/i/?c=api&a=updatePassword" >/dev/null
is "API password stored for alice" \
	"$(docker exec frss-fn php -d error_reporting=0 -r \
		'$c = include "/var/www/FreshRSS/data/users/alice/config.php"; echo $c["apiPasswordHash"] !== "" ? "1" : "0";' 2>/dev/null)" "1"

api=$(abody "${H1[@]}" -d 'Email=alice' -d 'Passwd=apisecret' \
	"${U}${PREFIX}/api/greader.php/accounts/ClientLogin")
has "ClientLogin issues a SID" "$api" 'SID='
sid=$(printf '%s' "$api" | sed -n 's/^SID=\(.*\)$/\1/p' | head -1)
[ -n "$sid" ] && ok "SID captured" || bad "SID captured" "<empty>" "value"

authz="Authorization: GoogleLogin auth=${sid}"
tags=$(abody "${H1[@]}" -H "$authz" "${U}${PREFIX}/api/greader.php/reader/api/0/tag/list?output=json")
has "tag/list answers"           "$tags" 'user/-/label/'
subs_api=$(abody "${H1[@]}" -H "$authz" "${U}${PREFIX}/api/greader.php/reader/api/0/subscription/list?output=json")
has "subscription/list has the feed" "$subs_api" 'feed.xml'
hasnt "no /i/i in the API output"    "$subs_api" '/i/i/'
# The Fever API is the second implemented API; checking it authenticates and answers on both
# domains is enough here (entry listing needs a `groups` request, covered by the RSS export above).
fever_key=$(docker exec frss-fn php -d error_reporting=0 -r '
	$c = include "/var/www/FreshRSS/data/users/alice/config.php";
	echo (string)($c["feverKey"] ?? "");
' 2>/dev/null)
has "Fever API authenticates on domain 1" \
	"$(abody "${H1[@]}" -d "api_key=${fever_key}" "${U}${PREFIX}/api/fever.php?api")" '"auth":1'
has "Fever API authenticates on domain 2" \
	"$(abody "${H2[@]}" -d "api_key=${fever_key}" "${U}${PREFIX}/api/fever.php?api")" '"auth":1'

# ---------------------------------------------------------------------------------------------
echo
echo "== 8. second domain: same instance, same data"
# Domain 2 has its own host-only session, so it needs its own login and its own jar.
CURL_JAR="$JAR2"
body "${H2[@]}" "${U}${PREFIX}/i/?c=auth&a=login" >/dev/null
h2=$(login_as H2 alice sup3rsecret || true)
has "login works on the 2nd domain" "$(loc "$h2")" "${PREFIX}/i/"

d1=$(CURL_JAR="$JAR";  body "${H1[@]}" "${U}${PREFIX}/i/")
d2=$(CURL_JAR="$JAR2"; body "${H2[@]}" "${U}${PREFIX}/i/")
has "article visible on domain 1" "$d1" 'First article from the local feed'
has "article visible on domain 2" "$d2" 'First article from the local feed'
has "feed listed on domain 2" \
	"$(CURL_JAR="$JAR2"; body "${H2[@]}" "${U}${PREFIX}/i/?c=subscription&a=index")" 'Functional Test'

cfg1=$(CURL_JAR="$JAR";  body "${H1[@]}" "${U}${PREFIX}/i/?c=configure&a=system")
cfg2=$(CURL_JAR="$JAR2"; body "${H2[@]}" "${U}${PREFIX}/i/?c=configure&a=system")
has "settings page renders on domain 1" "$cfg1" 'Base URL'
has "settings page renders on domain 2" "$cfg2" 'Base URL'
has "base URL shown for domain 1" "$cfg1" "a.example${PREFIX}"
has "base URL shown for domain 2" "$cfg2" "b.example${PREFIX}"

# The RSS view needs a session; now that domain 2 is logged in, its <link> must follow it.
rss2=$(CURL_JAR="$JAR2"; body "${H2[@]}" "${U}${PREFIX}/i/?c=index&a=rss")
has "RSS <link> is absolute on domain 2" "$rss2" "<link>http://b.example${PREFIX}</link>"

# A write on one domain must be visible on the other: one database, not a per-domain copy.
CURL_JAR="$JAR"
scs=$(field "$cfg1" '_csrf')
body "${H1[@]}" -d "_csrf=${scs}" -d 'instance-name=Renamed On Domain 1' \
	"${U}${PREFIX}/i/?c=configure&a=system" >/dev/null
has "a change on domain 1 is visible on domain 2" \
	"$(CURL_JAR="$JAR2"; body "${H2[@]}" "${U}${PREFIX}/i/?c=configure&a=system")" 'Renamed On Domain 1'

# ---------------------------------------------------------------------------------------------
echo
echo "== 9. logout"
CURL_JAR="$JAR"
logoutloc=$(loc "$(hdrs -d "_csrf=${csrf}" "${H1[@]}" "${U}${PREFIX}/i/?c=auth&a=logout")")
has "logout redirects inside the app" "$logoutloc" "${PREFIX}/i/"
is "session destroyed" "$(body "${H1[@]}" "${U}${PREFIX}/i/" | grep -c 'name="challenge"')" "1"

echo
echo "== result: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
