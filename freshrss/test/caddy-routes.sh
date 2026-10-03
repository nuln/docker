#!/usr/bin/env bash
# Test: the reverse-proxy examples route correctly, and the diagnostic that explains why.
#
# A proxy that "silently does nothing" is the most common way a Caddy setup fails here: a catch-all
# `redir` or `respond` is compiled ahead of the FreshRSS route and answers every request, including
# /rss/*. Nothing errors, the container is healthy, and the symptom is a redirect to the wrong site.
# The Caddyfile does not reveal this, because Caddy reorders what you wrote — the compiled route
# order does.
#
# So these cases assert on the compiled order, using test/caddy-routes.py, and they cover the failure
# modes as well as the working shapes. Asserting only that the examples work would leave the
# diagnostic — the thing that tells a reader what went wrong — untested.
#
# Usage: ./test/caddy-routes.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
CADDY_IMAGE='caddy:2-alpine'
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()   { pass=$((pass+1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
is()   { if [ "$2" = "$3" ]; then ok "$1"; else fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n         got:  %s\n         want: %s\n' "$1" "$2" "$3"; fi; }
has()  { case "$2" in *"$3"*) ok "$1";; *) fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n         got:  %s\n         want it to contain: %s\n' "$1" "$2" "$3";; esac; }
hasnt(){ case "$2" in *"$3"*) fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n         got:  %s\n         want it NOT to contain: %s\n' "$1" "$2" "$3";; *) ok "$1";; esac; }

# Every fixture is written once, up front, under a name it keeps for the rest of the run. Rewriting a
# file and immediately bind-mounting it races the container's view of it: on macOS Docker Desktop that
# intermittently yields a bind-mount error or a torn read, which shows up here as a route that
# mysteriously loses half a URL. Distinct names mean no mount ever races a write.

CONF="$TMP/conf"
mkdir -p "$CONF"
cp "$ROOT/Caddyfile.example" "$ROOT/Caddyfile.outer.example" "$ROOT/Caddyfile.inner.example" "$CONF/"

# A FreshRSS route that will actually reach FreshRSS.
cat > "$CONF/freshrss.caddy" <<'EOF'
handle /rss/* {
	reverse_proxy freshrss:80 {
		header_up X-Forwarded-Proto {scheme}
		header_up X-Forwarded-Host {host}
		header_up X-Forwarded-Port {server_port}
	}
}
redir /rss /rss/ 308
EOF

# The same route as a bare directive, which is sorted after redir and so never gets a chance.
cat > "$CONF/fr-bare.caddy" <<'EOF'
reverse_proxy freshrss:80
EOF

# Three catch-alls: a bare redir, an anonymous handle, and a named matcher. The first shadows the
# FreshRSS route; the other two do not.
cat > "$CONF/fb-bare.caddy" <<'EOF'
redir https://www.example.com{uri}
EOF
cat > "$CONF/fb-handle.caddy" <<'EOF'
handle {
	redir https://www.example.com{uri}
}
EOF
cat > "$CONF/fb-both.caddy" <<'EOF'
redir https://www.example.com{uri}
handle {
	redir https://www.example.com{uri}
}
EOF
cat > "$CONF/fb-named.caddy" <<'EOF'
@catchall not path /rss /rss/*
redir @catchall https://www.example.com{uri}
EOF

# Neither anonymous spelling of the exclusion is accepted by redir, so both must be rejected rather
# than silently misparsed — these are the two forms a reader is most likely to try.
cat > "$CONF/bad-block.caddy" <<'EOF'
handle /rss/* {
	reverse_proxy freshrss:80
}
redir {
	not path /rss /rss/*
}
https://www.example.com{uri}
EOF
cat > "$CONF/bad-inline.caddy" <<'EOF'
handle /rss/* {
	reverse_proxy freshrss:80
}
redir not path /rss /rss/* https://www.example.com{uri}
EOF

# A site block whose only route is the FreshRSS one: nothing answers any other path.
cat > "$CONF/only-rss.caddy" <<'EOF'
handle /rss/* {
	reverse_proxy freshrss:80
}
EOF

# site <name> <import...> -> a site block importing the given snippet files, in the order given.
site() {
  local name="$1"; shift
  { printf 'example.com {\n'
    local s
    for s in "$@"; do printf '\timport %s\n' "$s"; done
    printf '}\n'
  } > "$CONF/$name"
}

site split-a freshrss.caddy fb-handle.caddy
site split-b fb-handle.caddy freshrss.caddy
site bare-redir freshrss.caddy fb-bare.caddy
site bare-and-handle freshrss.caddy fb-both.caddy
site bare-proxy fr-bare.caddy fb-handle.caddy
site named freshrss.caddy fb-named.caddy
site try-block bad-block.caddy
site try-inline bad-inline.caddy
site narrow only-rss.caddy

# adapt <caddyfile> [ignored...] -> JSON on stdout. Everything lives in one mounted directory, so the
# snippet arguments are no longer needed; they are accepted and dropped so call sites can name what
# they mean. stderr is captured so a mount or parse failure surfaces as a real message rather than an
# empty comparison.
adapt() {
  docker run --rm -v "$CONF:/etc/caddy/conf:ro" \
    "$CADDY_IMAGE" caddy adapt --adapter caddyfile --config "/etc/caddy/conf/$1" 2>"$TMP/.err"
}

# validate <caddyfile> [ignored...] -> Caddy's verdict, or its parse error.
validate() {
  docker run --rm -v "$CONF:/etc/caddy/conf:ro" \
    "$CADDY_IMAGE" caddy validate --adapter caddyfile --config "/etc/caddy/conf/$1" > "$TMP/.vout" 2>&1
  python3 - "$TMP/.vout" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8", errors="replace").read()
errors = []
for line in raw.splitlines():
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        record = json.loads(line)
    except ValueError:
        continue
    if record.get("level") == "error" and record.get("msg"):
        errors.append(record["msg"])
# Caddy prints the verdict as bare text while everything around it is JSON, and a successful run
# ends on an unrelated startup line — so neither "first line" nor "last line" is the verdict.
if errors:
    print(errors[0])
elif "Valid configuration" in raw:
    print("Valid configuration")
else:
    print(raw.strip().splitlines()[-1] if raw.strip() else "")
PY
}

# fmt_clean <file> -> "clean" when Caddy would not reformat it.
fmt_clean() {
  if docker run --rm -v "$ROOT/$1:/etc/caddy/conf/Caddyfile:ro" \
      "$CADDY_IMAGE" caddy fmt --diff /etc/caddy/conf/Caddyfile >/dev/null 2>&1; then
    echo clean
  fi
}

# route_answering <caddyfile> [snippet...] -- <path>... -> label of the first route matching <path>.
# The JSON goes through a file rather than a pipeline: a long chain of readers can be cut short by a
# downstream process exiting, which silently truncates the answer.
route_answering() {
  local main="$1"
  shift
  local paths=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done
  shift
  paths=("$@")
  adapt "$main" > "$TMP/.json"
  if [ ! -s "$TMP/.json" ]; then
    echo "adapt failed: $(head -1 "$TMP/.err" 2>/dev/null)"
    return
  fi
  python3 "$HERE/caddy-routes.py" "$TMP/.json" "${paths[@]}" 2>/dev/null |
    sed -n 's/^ *answered by route [0-9]*: //p' | head -1
}

printf '\n== shipped examples validate and are already formatted ==\n'
for f in Caddyfile.example Caddyfile.outer.example Caddyfile.inner.example; do
  is "$f is valid" "$(validate "$f")" 'Valid configuration'
  is "$f is fmt-clean" "$(fmt_clean "$f")" 'clean'
done

printf '\n== Caddyfile.example: /rss/* is proxied, nothing shadows it ==\n'
J="$(adapt Caddyfile.example)"
is '/rss/ is proxied'              "$(route_answering Caddyfile.example -- '/rss/')"   'REVERSE_PROXY -> freshrss:80'
is '/rss/i/ is proxied'            "$(route_answering Caddyfile.example -- '/rss/i/')" 'REVERSE_PROXY -> freshrss:80'
is '/rss/api/ is proxied'          "$(route_answering Caddyfile.example -- '/rss/api/')" 'REVERSE_PROXY -> freshrss:80'
is 'a query string does not affect matching' \
   "$(route_answering Caddyfile.example -- '/rss/i/?c=auth&a=login')" 'REVERSE_PROXY -> freshrss:80'
is 'a bare /rss redirects to /rss/' "$(route_answering Caddyfile.example -- '/rss')"    'REDIRECT 308 -> /rss/'
is '/ is 404'                      "$(route_answering Caddyfile.example -- '/')"       'RESPOND 404'
is '/other is 404'                 "$(route_answering Caddyfile.example -- '/other')"  'RESPOND 404'
is '/rssfoo is 404'                "$(route_answering Caddyfile.example -- '/rssfoo')" 'RESPOND 404'
hasnt 'no redirect to another host' "$J" 'www.example.com'

printf '\n== Caddyfile.outer.example: two-hop, same guarantees ==\n'
is '/rss/ reaches the inner Caddy'   "$(route_answering Caddyfile.outer.example -- '/rss/')"   'REVERSE_PROXY -> caddy-inner:80'
is '/rss/i/ reaches the inner Caddy' "$(route_answering Caddyfile.outer.example -- '/rss/i/')" 'REVERSE_PROXY -> caddy-inner:80'
is '/ is 404'                        "$(route_answering Caddyfile.outer.example -- '/')"       'RESPOND 404'

printf '\n== split across files: catch-all as an anonymous handle ==\n'
for name in split-a split-b; do
  is "$name is valid" "$(validate "$name" freshrss.caddy fb-handle.caddy)" 'Valid configuration'
  is "$name: /rss/ is proxied"   "$(route_answering "$name" freshrss.caddy fb-handle.caddy -- '/rss/')" \
     'REVERSE_PROXY -> freshrss:80'
  is "$name: /rss/i/ is proxied" "$(route_answering "$name" freshrss.caddy fb-handle.caddy -- '/rss/i/?c=auth&a=login')" \
     'REVERSE_PROXY -> freshrss:80'
  is "$name: / still falls through" "$(route_answering "$name" freshrss.caddy fb-handle.caddy -- '/')" \
     'REDIRECT 302 -> https://www.example.com{http.request.uri}'
done

printf '\n== failure modes the diagnostic has to catch ==\n'

# An unqualified `redir` is sorted ahead of `handle` by Caddy's directive order and matches
# everything: a correct-looking setup that proxies nothing, with no error anywhere.
is 'a bare redir still compiles' "$(validate bare-redir freshrss.caddy fb-bare.caddy)" 'Valid configuration'
is '…and it is what answers /rss/' "$(route_answering bare-redir freshrss.caddy fb-bare.caddy -- '/rss/')" \
   'REDIRECT 302 -> https://www.example.com{http.request.uri}'

# Adding the anonymous handle without removing the bare redir does not help — the bare one is
# compiled first and still wins. Worth a case: it is the natural first attempt.
is 'a bare redir beside a handle still wins' \
   "$(route_answering bare-and-handle freshrss.caddy fb-both.caddy -- '/rss/')" \
   'REDIRECT 302 -> https://www.example.com{http.request.uri}'
adapt bare-and-handle freshrss.caddy fb-both.caddy > "$TMP/.json"
is '…while the handle version is still compiled' \
   "$(python3 "$HERE/caddy-routes.py" "$TMP/.json" | grep -c 'example\.com{')" '2'

# The FreshRSS route has to be a `handle` block too; a bare `reverse_proxy` loses the same way.
is 'a bare reverse_proxy loses to the catch-all' \
   "$(route_answering bare-proxy fr-bare.caddy fb-handle.caddy -- '/rss/')" \
   'REDIRECT 302 -> https://www.example.com{http.request.uri}'

hasnt 'block-form anonymous matcher is rejected' \
       "$(validate try-block bad-block.caddy)" 'Valid configuration'
hasnt 'inline-form anonymous matcher is rejected' \
       "$(validate try-inline bad-inline.caddy)" 'Valid configuration'

# The named matcher does work, so the documented alternative stays honest.
is 'a named not-path matcher is accepted' "$(validate named freshrss.caddy fb-named.caddy)" \
   'Valid configuration'
is '…and it also leaves /rss/ proxied' \
   "$(route_answering named freshrss.caddy fb-named.caddy -- '/rss/')" 'REVERSE_PROXY -> freshrss:80'
is '…while still redirecting /' "$(route_answering named freshrss.caddy fb-named.caddy -- '/')" \
   'REDIRECT 302 -> https://www.example.com{http.request.uri}'

printf '\n== the diagnostic itself ==\n'
adapt split-a freshrss.caddy fb-handle.caddy > "$TMP/split-a.json"
OUT="$(python3 "$HERE/caddy-routes.py" "$TMP/split-a.json" '/rss/' '/')"
has 'names the route answering /rss/' "$OUT" 'answered by route 2: REVERSE_PROXY -> freshrss:80'
has 'names the route answering /'    "$OUT" 'answered by route 3: REDIRECT 302'
has 'marks a route that matches any path' "$OUT" 'any path'
has 'keeps the host matcher visible' "$OUT" 'host example.com'
has 'keeps a path matcher visible'   "$OUT" 'path /rss/*'
hasnt 'does not dump the whole JSON' "$OUT" '"apps"'
is 'reads stdin as well as a file' \
   "$(python3 "$HERE/caddy-routes.py" - '/rss/' < "$TMP/split-a.json" |
      sed -n 's/^ *answered by route [0-9]*: //p')" 'REVERSE_PROXY -> freshrss:80'

adapt narrow only-rss.caddy > "$TMP/narrow.json"
is 'a path no route matches is reported' \
   "$(python3 "$HERE/caddy-routes.py" "$TMP/narrow.json" '/x' | sed -n 's/^ *//p' | tail -1)" \
   'no route matched'
is '…while a covered path still resolves' \
   "$(python3 "$HERE/caddy-routes.py" "$TMP/narrow.json" '/rss/i/' |
      sed -n 's/^ *answered by route [0-9]*: //p')" 'REVERSE_PROXY -> freshrss:80'

printf '%s' '{"apps":{"http":{"servers":{"s":{"routes":[]}}}}}' > "$TMP/empty.json"
is 'exits 1 when there is nothing to route' \
   "$(python3 "$HERE/caddy-routes.py" "$TMP/empty.json" '/x' >/dev/null 2>&1; echo $?)" '1'
is 'exits 2 without a config' \
   "$(python3 "$HERE/caddy-routes.py" >/dev/null 2>&1; echo $?)" '2'
is 'exits 0 on a config with routes' \
   "$(python3 "$HERE/caddy-routes.py" "$TMP/split-a.json" >/dev/null 2>&1; echo $?)" '0'
is 'rejects input that is not JSON' \
   "$(printf 'not json' > "$TMP/bad.json"; python3 "$HERE/caddy-routes.py" "$TMP/bad.json" >/dev/null 2>&1; echo $?)" '1'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]