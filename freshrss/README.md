# freshrss

FreshRSS, patched so that **one instance can be served from a sub-directory, through several
domains at the same time**, with OIDC and WebSub working.

Everything is a single patch on top of upstream FreshRSS (`patches/`), so the change is easy to
review and to re-apply on a newer release.

| | |
|---|---|
| Image | `ghcr.io/nuln/freshrss:1.30.4` (pinned upstream version) and `:latest` — **private package, see "Pulling the image"** |
| Base | Debian + Apache + mod_php + `mod_auth_openidc` (required for OIDC) |
| Upstream | **1.30.4** (the latest release), pinned by commit in `ARG FRESHRSS_REF` |
| Licence | AGPL-3.0, like FreshRSS — this image is a modified distribution and must keep offering the corresponding source (the patch lives in this repository) |

---

## Why a patch is needed

FreshRSS assumes a single public address and derives the public root from the *current page*.
Both break behind a reverse proxy that serves the instance from a sub-directory, and much worse
when that sub-directory is reachable through several domains:

| # | Upstream behaviour | Consequence |
|---|---|---|
| 1 | `Minz_Request::guessBaseUrl()` returns the directory of the **current page** | `Minz_Url::display()` appends `/i` again → **`/rss/i/i`**; every link, redirect and the logo are broken |
| 2 | `trim($conf->base_url, ' /\\"')` | the leading `/` of `/rss` is eaten, so a path-only `base_url` **cannot be expressed at all** |
| 3 | session cookie path left empty → PHP uses the backend script directory | the browser never sends the cookie back under `/rss/` → **logged out on every request** |
| 4 | `OIDCRedirectURI /i/oidc/` hardcoded | the OIDC callback is announced at the domain root → **404** under a sub-directory |
| 5 | WebSub is driven by `base_url` | with a path-only value, `serverIsPublic('')` is false → **WebSub can never be enabled** |
| 6 | `p/api/pshb.php` only answers `hub_mode=subscribe` / `hub_mode=unsubscribe` | a specification-compliant hub verifies with `hub.mode=verify` and gets `422` → **the subscription is never activated and no content is ever pushed** |

### Upstream base and carried-over security fixes

The image is built from the **1.30.4 release tag**, not from the development branch, so the
published tag says `1.30.4` and the code is a released version.

1.30.4 adds no new patch fixes; it exists because of **PHP**, not FreshRSS:
[CVE-2026-109618 / CVE-2026-109619](https://github.com/FreshRSS/FreshRSS/issues/9475) are
pre-authentication remote code executions in PHP itself (CVSS 9.2), fixed in Debian's `php8.4`
`8.4.27-1~deb13u1`, published 2026-10-21. A container image freezes the distribution packages it
was built from, so `1.30.0` kept shipping `8.4.26` — vulnerable — no matter how new the FreshRSS
source was. Check what a running container actually has:

```sh
docker exec freshrss php -v        # must read 8.4.27 or later
docker run --rm --entrypoint sh ghcr.io/nuln/freshrss:1.30.4 -c 'php -v'
```

**The bump alone does not fix it, and that is the reusable lesson.** `FRESHRSS_BASE_IMAGE` is
`debian:13-slim`, a *tag*: its `apt` repositories are read at build time, so the PHP version is
decided when the layer runs and then frozen into the image. BuildKit keys a `RUN` layer on the
command text, so once the `apt-get install` step has run, **every later build replays that layer**
— the fixed PHP is never fetched. On 2026-10-22, rebuilding this repository without a changed ARG
still produced `8.4.26`, while `apt-get` inside the *same* fresh base image offered `8.4.27`
immediately. `--no-cache-filter` is no help either: it matches the step path, and this step's path
is the literal `RUN apt-get update…`.

Two mechanical defences are therefore in the Dockerfile, and neither depends on remembering:

- **the apt layer is keyed to `DEBIAN_APT_REFRESH`** — a caller-supplied date. Bump the date and
  the layer is rebuilt; the build refuses to start without one, so a cached (stale) layer cannot
  be reused silently;
- **the build asserts `PHP_VERSION >= 8.4.27`** and fails with the CVE name, so an image that
  would still be vulnerable cannot be produced at all.

Rebuilding on bare `debian:13-slim` is how a PHP security update is taken, and the image records
which day it did so (`docker inspect --format '{{index .Config.Labels "nuln.base.apt-refresh"}}'`).
Pin the digest (`ARG FRESHRSS_BASE_IMAGE=debian@sha256:…`) if a deployment must be
byte-reproducible — but then updates are manual by definition, and the date must be bumped for
each one.

1.30.1 … 1.30.4 also carry roughly 40 upstream fixes made since 1.30.0. The ones that touch what
this patch changes:

| Upstream fix | What it changes for this image |
|---|---|
| `f800a430` + `6bb0c679` WebSub: `hub.mode=verify` handling, and `hub.verify=sync` in the subscription request | `p/api/pshb.php` — the same endpoint this patch extends. Complements the `<prefix>/api/pshb.php` callback the patch builds |
| `859a2ad0` no local DNS leak when fetching feeds through a proxy | `lib/Minz/Request.php::serverIsPublic()`, which this patch calls to decide whether WebSub may be enabled. It gained a `$allowDnsResolve` parameter; the patch's call sites are unaffected and still resolve by default |
| `0187b15c` sanitizer: block `data:` URIs except `data:image` | `lib/simplepie/…/Sanitize.php`, fetched content only |
| `4e5e142c` remove a vulnerable error-display code path | `lib/Minz/Error.php` |
| `f6170833`, `74556f80`, `c5dd38b0`, `8769b4e2`, `da9dc448` … | 404 handling, refresh UX, sort overrides, Fever key no longer logged, API favicon |

The two security fixes this patch used to carry by hand are now upstream, in the exact form the
patch had them, so the patch no longer touches those lines:

| Upstream fix | Now |
|---|---|
| `64f7f24` Improve WebSub security | upstream re-enabled the self-URL check in `p/api/pshb.php`; the patch no longer patches that block at all |
| `6780afe` Reject token access for disabled accounts (CWE-613) | upstream added `!$conf->enabled` in `lib/Minz/Request.php` |

`5a270c0` — rotate the session ID on every authenticated transition (CWE-384), which 1.30.0 did
have but this patch held back — is **in 1.30.4**, because upstream changed
`Minz_Session::regenerateID()` to throw `RuntimeException` instead of calling `Minz_Error::error()`,
and wrapped every caller in a `try`/`catch`. That is precisely the shape this patch needed: it
patches `Session.php` (cookie path) and `authController.php` independently of those lines, and the
whole tree passes PHPStan level 10, so the old `catch.neverThrown` objection is gone. The
login, re-authentication and logout paths therefore now rotate the session ID.

`p/api/pshb.php` is still patched, for the verification challenge only (row 6 above).


`patches/0001-multi-domain-and-subdirectory.patch` fixes all six:

- `Minz_Request::applicationPath()` derives the **public root** from `SCRIPT_NAME` (or
  `X-Forwarded-Prefix` when the proxy strips it), so it is the same for `/`, `/i/`, `/api/`,
  `/f.php` and `/i/oidc/`.
- `base_url` now accepts a **path** (`/rss`) or an empty value → the host is taken from the
  request, so several domains share one instance. A full URL still pins a single host, exactly
  as before.
- the session cookie is pinned to the public path (`/rss/`).
- new `websub_base_url` gives WebSub the single stable address it needs, without affecting the
  other domains.
- new `allowed_hosts` optionally constrains which host may be used to build absolute URLs
  (Host header injection defence).
- `p/api/pshb.php` answers the WebSub verification challenge. PHP maps the `hub.mode` and
  `hub.challenge` parameter names onto `hub_mode` / `hub_challenge`, the spelling the rest of the
  file already used, so this is a few lines and leaves the existing dialect untouched.

### What was verified

`test/integration.sh` — 230 checks against a real Apache + PHP + `mod_auth_openidc` stack, with a
mock identity provider, a mock WebSub hub and a mock reverse proxy (all re-run on the 1.30.4 base):

- every entry point serves (`/rss/`, `/rss/i/`, `/rss/api/pshb.php`, `/rss/f.php`) and
  `/rss/rss/` 404s
- the landing redirect is `/rss/i/?rid=…`, never `/rss/i/i`
- `Set-Cookie: … path=/rss/`
- absolute URLs follow the domain that was actually used, on every domain
- every HTML page the patch touched (all of `configure/*`, subscription, the reader views, the
  profile) renders on both domains, without `/i/i`, and shows the new WebSub field
- `FRESHRSS_WEBSUB_BASE_URL` pins the WebSub address, it is considered public, and the callback
  URL is built from it
- `cli/do-install.php --base-url/--websub-base-url` and `cli/reconfigure.php` store and change
  both settings
- a sub-directory literally named `/i` is served correctly and is not confused with the `/i/`
  entry-point
- a **complete OIDC login**: anonymous request → `authorize` → `authorize` redirects back with a
  code → FreshRSS exchanges it → the RS256 `id_token` is accepted (`state`, `nonce`, `aud`, JWKS
  signature, client authentication) → the session is established and resolved to the account named
  by `preferred_username`
- a **complete WebSub round trip** behind a reverse proxy that does *not* strip the prefix: the
  feed advertises a hub, FreshRSS subscribes with the callback
  `…/rss/api/pshb.php?k=…`, the hub verifies that callback, pushes new content, and the article is
  stored **with no pull refresh at all**; the unsubscription uses the same prefixed callback
- `X-Forwarded-Prefix`: with no `FRESHRSS_PATH_PREFIX` at all, a request announcing
  `X-Forwarded-Prefix: /rss` still produces `/rss/i/` in the page and in redirects — the mode a
  stripping proxy (`handle_path`, `proxy_pass …/`) needs
- **email validation** end to end: `force_email_validation` signs a token, a real SMTP sink
  receives the mail, the link it carries keeps the sub-directory and follows the domain of the
  request, a wrong token bounces back to the validation page without clearing anything, and
  following the right one clears the token
- `allowed_hosts`: a request claiming a host outside the list is still served, but no absolute URL
  it produces mentions that host; emptying the list restores the permissive default

`test/functional.sh` — 68 checks driving the actual product: the installation wizard, the real
challenge/response login, subscribing to a real feed, refreshing, reading, search, OPML/RSS
export, the Google Reader and Fever APIs, the second domain (login, read, write) and logout.

`test/browser.sh` — 38 checks with a real Chromium, because every check above logs in with curl and
therefore never runs the JavaScript the login page depends on: the login button is enabled by
`extra.js`, `bcrypt.js` derives the challenge, submitting produces a POST, the cookies stay scoped to
`/rss/`, and the reader logs no CSP warning. Run once direct, once behind a prefix-stripping proxy
and once behind Caddy, plus a scenario where the scripts are withheld: the page must say so instead
of leaving a dead button, and must not enter a reload loop.

`test/upgrade.sh` — 39 checks for the path every operator takes and nothing else covered: a data
volume created by **1.30.0** (the previous release), started on the new image. It installs, subscribes
and reads on the old image, then mounts the same volume on the new one and asserts that

- the instance is not re-opened for installation, keeps serving, and has no `/rss/i/i`;
- the subscription, its articles, the second user, the API password hash and a per-user setting are
  all still there, and `base_url` is still the stored path;
- the password set on the old build logs in, the reader loads, and a stale session cookie from the
  old build does **not** authenticate (1.30.4 rotates the session id on login);
- a write (subscription form) and the refresh CLI both work against the migrated database, and
  FreshRSS's own `cli/health.php` reports nothing;
- the PHP on the new image is ≥ 8.4.27 — the CVE fix comes from the image, not from the app;
- the patch is still in effect: cookie scoped to `/rss/`, CSP header, login watchdog script, the
  WebSub base URL field.

All five suites were run on the image that carries **PHP 8.4.27**: 230 + 68 + 38 + 39 checks, zero
failures, plus `test/caddy-routes.sh` (49).

Upstream's own gates pass on the patched 1.30.4 tree: `phpcs` (631 files, no violations),
**PHPStan level 10 with zero errors**, and the whole PHPUnit suite — 811 tests, 1582 assertions.
Three `DatabaseDAOTest::test_strilike_MySQL` data sets fail, and fail identically on the **unpatched**
tree at the same ref (a SQLite collation difference under `php:8.3-cli`; CI tolerates them by name,
so a real regression still fails the build). The patch adds 41 tests, all passing, in
`tests/lib/Minz/RequestTest.php` and `tests/lib/Minz/UrlTest.php`.

The same suites were run against an **unpatched 1.30.4 image built from the same Dockerfile**, to
confirm the extended behaviour comes from the patch and not from upstream: integration aborts at
`cookie scoped to prefix` (`HttpOnly; SameSite=Lax`, no `path=/rss/`), which is exactly the
logged-out-on-every-request defect described above.

### Known limits

- The session cookie stays host-only, so each domain needs its own login. Accounts are shared,
  so the second domain only asks for credentials again.
- `allowed_hosts` has no environment variable; it is read from `./data/config.php`.
- The refresh cadence of a feed is unchanged: FreshRSS keeps a feed for
  `limits.cache_duration` (800 s) and skips a feed inside its TTL. A "reload this feed" on the
  UI, or `?c=feed&a=reload&id=N`, forces a fetch. This is upstream behaviour, not a side effect
  of the patch.
- **`data/` is made group-accessible to the Apache group at start-up, and the directories are setgid.**
  FreshRSS creates its per-feed WebSub state (`data/PubSubHubbub/…`) as *root* with mode `0770`,
  which the default `022` umask turns into `0750 root:root`. The Apache workers run as `www-data`,
  which is neither the owner nor in group root, so they cannot traverse into it and every WebSub
  callback answers `410 Feed info not found!`. This is invisible on macOS or Windows, where Docker
  Desktop bypasses permission checks, and it breaks any deployment that bind-mounts `data/` — the
  documented Compose setup included. The entrypoint therefore sets a group-friendly umask, makes
  `data/` group-writable, and marks the directories setgid so that state created *later* by root
  inherits the right group. `test/integration.sh` asserts it with the real `www-data` uid, and skips
  that assertion when the filesystem does not enforce permissions.
- A feed pointing at a private address (a container name, a LAN host) is refused unless
  `internal_host_allowlist` or `INTERNAL_HOST_ALLOWLIST` allows it. Relevant when you aggregate
  your own services; the flag is described in `docs/en/admins/09_AccessControl.md`. The value is
  matched as `host` or `host:port`, so a non-default port has to be spelled out.
- **Upstream CLI caveat, not fixed here.** `getopt()` only reads the value of a long option
  declared with `::` when it is attached with `=`, and it stops scanning at the first bare
  argument. A boolean option written as `--api-enabled true` therefore loses its own value *and*
  every option that follows it, silently — including `--base-url` and `--websub-base-url`. Always
  write `--api-enabled=true`, or place boolean options last. The environment variables this image
  documents (`FRESHRSS_PATH_PREFIX`, `FRESHRSS_BASE_URL`, `FRESHRSS_WEBSUB_BASE_URL`) do not go
  through the CLI parser and are unaffected. `test/integration.sh` pins both spellings so the
  behaviour cannot change unnoticed.
- **WebSub status is per user and per push.** Since 1.30.1 a subscription only counts as enabled
  once a push has actually been received (`websub_pending` in the feed editor until then), the key
  is a random 32-byte value instead of a salt-derived hash, and a subscription whose advertised hub
  no longer matches the stored `!hub.json` is refused with a warning rather than silently renewed.
  `test/integration.sh` performs the full round trip with a mock hub, so the pending → enabled
  transition is exercised.
- `create-user.php --email` does **not** send a validation mail: it stores `mail_login` before
  calling the updater, so the "the address changed" branch that signs the token never fires. The
  address has to be set from the profile form (or `FreshRSS_user_Controller::updateUser()`, which is
  what that form calls) for the mail to be sent. Upstream behaviour, not a side effect of the patch.
- **Only `linux/arm64` was tested locally**, because the machine that produced this image has no
  access to a registry to pull an `amd64` base image. The CI workflow runs the same suites on
  `linux/amd64`, so the multi-architecture claim rests on CI, not on a local run. That applies to
  the PHP and CVE position too: `8.4.27` is what Debian arm64 ships today, and the amd64 build
  takes the same `trixie-security` package — verify with `docker exec … php -v` on the tag you
  deploy.

### Pulling the image

The package on GitHub Container Registry is **private**, so a plain `docker pull` is refused. Pick
whichever suits the deployment:

```sh
# 1. Authenticate once with a personal access token that has the `read:packages` scope
#    (classic token: "read:packages"; fine-grained token: Packages → Read).
echo "$GHCR_TOKEN" | docker login ghcr.io -u nuln --password-stdin
docker pull ghcr.io/nuln/freshrss:1.30.4

# 2. Or make the package public once, in the GitHub UI, and then no credentials are needed at all:
#    https://github.com/users/nuln/packages/container/package/freshrss/settings
#    → "Change visibility" → Public. Recommended for anything that is not secret: the image is a
#    public build of a public project, and this repository already holds its source.
```

The published tags are the upstream version the patch is based on — currently **`1.30.4`** — plus
**`latest`**. Both point at the same multi-architecture manifest (`linux/amd64` and `linux/arm64`),
so the right thing to deploy is the version tag, not `latest`:

```yaml
services:
  freshrss:
    image: ghcr.io/nuln/freshrss:1.30.4   # pinned; `latest` moves
```

The old `1.30.0` tag is **not** re-published and stays on PHP 8.4.26, which is vulnerable to
CVE-2026-109618/9 (see "Upstream base and carried-over security fixes"). Moving to `1.30.4` is a
drop-in change: no volume layout, configuration key or environment variable differs.

The digest below was published for 1.30.0 and is kept only as a worked example of the syntax —
replace it with the digest of the tag you actually ship (`docker image inspect --format '{{index .RepoDigests 0}}'`):

```sh
docker pull ghcr.io/nuln/freshrss@sha256:a5f834f74b47f8a33eb949051e5145af7a81c4d777a2af89e3f938b9e5a5d755
```
---

## Usage

### 1. Deploy

Two compose files ship here. Pick one.

**`docker-compose.yml` — one command, nothing else to set up.** Single container, published on
`127.0.0.1:8080`, installed and populated automatically:

```sh
echo "$GHCR_TOKEN" | docker login ghcr.io -u nuln --password-stdin   # the package is private
docker compose up -d
docker compose logs -f          # waits for "✅ FreshRSS user successfully created."
```

Then open <http://127.0.0.1:8080/rss/> and log in with `alice` / `change-me-now`
(`ADMIN_USER` / `ADMIN_PASSWORD` — **change them**, in `.env` or on the command line). The setup
wizard does not appear: `FRESHRSS_INSTALL` and `FRESHRSS_USER` install the instance and create the
administrator on first start, and both are no-ops on every later start. Nothing under `./data` ever
has to be edited by hand.

Copy `.env.example` to `.env` to change anything; every value has a working default.

**`docker-compose.proxy.yml` — behind a reverse proxy.** No published port, joined to an external
network, which is the usual production shape:

```sh
docker network create proxy
docker compose -f docker-compose.proxy.yml up -d
```

The reverse proxy itself is not part of these files — `Caddyfile.example` is a working one. What
matters is that it must **not strip the prefix**; see the next section.

Both files take the image from `${FRESHRSS_IMAGE:-ghcr.io/nuln/freshrss:1.30.4}`, so a test run can
point them at a locally built image without editing the file.

### 2b. Two hops: a proxy in front of Caddy

If something already terminates the client's connection before Caddy — another proxy tier, a load
balancer, a service mesh — you need two hops, and the inner Caddy must **relay** the forwarding
headers instead of recomputing them. Recomputing them is the usual way to break this: the hop is
plain HTTP internally, so FreshRSS would see `http` and generate downgraded absolute URLs, lose
`Secure` on the session cookie, and point links at a container name.

`Caddyfile.outer.example`, `Caddyfile.inner.example` and `docker-compose.two-hop.yml` are that
setup, ready to copy:

```sh
docker network create proxy
cp Caddyfile.outer.example Caddyfile
cp Caddyfile.inner.example Caddyfile.inner
docker compose -f docker-compose.two-hop.yml up -d
```

**Give FreshRSS its own subdomain.** The example is built that way, and it is what makes the file
self-contained: it declares one site block, needs no catch-all, and modifies none of your other
services. Caddy allows a hostname to be declared in only one place, so if you keep one file per
service, a second `example.com` block — from any file — is a startup error.

Serving FreshRSS under a path of a domain you already serve (`example.com/rss`) **cannot** be done
from a file that declares the hostname: Caddy allows a hostname in only one place, so a second
`example.com` block is a startup error. What you can do is keep one file per service and `import`
each into the one site block, which is the same shape the examples above use:

```caddyfile
# freshrss.caddy — imported into your existing site block
handle /rss/* {
    reverse_proxy freshrss:80 {
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-Port {server_port}
    }
}
redir /rss /rss/ 308
```

```caddyfile
# Caddyfile — the site block you already have
example.com {
    import freshrss.caddy
    import fallback.caddy
}
```

**If that domain also has a catch-all redirect, it has to be a `handle` block.** This is the single
thing most likely to send you down an afternoon:

```caddyfile
# fallback.caddy
handle {
    redir https://www.example.com{uri}
}
```

A bare `redir https://www.example.com{uri}` compiles *ahead* of `handle /rss/*`, matches every
request, and answers `/rss/` itself — no error anywhere, healthy containers, login page you never
reach. Wrapping it in `handle` puts it in the same mutually-exclusive group as the FreshRSS route,
where Caddy orders the two by path specificity and `/rss/*` wins. There is nothing to add to the
file and no matcher to remember: no `@catchall`.

Two rules that the examples encode, both learned the hard way:

- **The inner Caddy must have no `ports:`.** It trusts the `X-Forwarded-*` headers it receives, which
  disables Caddy's built-in protection against a forged Host. That is only safe while the port is
  unreachable from anywhere but this network.
- **Use `handle` for the FreshRSS route, not a bare `reverse_proxy /rss/*`.** Caddy's built-in
  directive order evaluates `redir` and `respond` *before* `handle` and `reverse_proxy`, so an
  unqualified `redir` (a catch-all redirect to the main site) or a bare `respond 404` answers every
  request and the sub-directory is never proxied. `handle` blocks are mutually exclusive and ordered
  by path specificity, which is why they are immune to this.

### When /rss redirects somewhere else: read the compiled routes

None of this is visible in the Caddyfile, because Caddy reorders what you wrote. Ask it:

```sh
docker exec <caddy> caddy adapt --config /etc/caddy/Caddyfile 2>/dev/null \
  | python3 test/caddy-routes.py - /rss/
```

```
effective route order (first match wins):
   1. REDIRECT 302 -> https://www.example.com{http.request.uri} [host example.com, any path]
   2. REVERSE_PROXY -> freshrss:80 [host example.com AND path /rss/*]

  /rss/
      answered by route 1: REDIRECT 302 -> https://www.example.com{http.request.uri}
```

Route 1 is answering `/rss/`, and `any path` says why. Wrapping that redirect in `handle` moves it
behind route 2. `test/caddy-routes.py` takes any Caddy JSON — from `caddy adapt`, from
`docker exec`, or saved to a file — and prints the order with the route that answers each path you
name. `test/caddy-routes.sh` asserts the ordering for every shape described here, including the ones
that fail, so a change to an example cannot quietly reintroduce the problem.

If nothing sits in front of Caddy, do not use two hops: point `Caddyfile.example` at `freshrss:80`
directly. One hop has none of these subtleties.

### 2. Reverse proxy — the path MUST NOT be stripped

This is the one thing to get right. `mod_auth_openidc` compares `OIDCRedirectURI` against the
path **Apache itself serves** (`oidc_util_url_cur_matches()` in `src/util/url.c` does a plain
`strcmp` on `r->parsed_uri.path`), and builds the absolute `redirect_uri` from
`scheme://host:port` + that path only. So a proxy that strips the prefix makes OIDC impossible:
writing `/rss/i/oidc/` then loops forever, writing `/i/oidc/` then 404s. The container therefore
serves the prefix through an Apache `Alias`, and the proxy forwards the path unchanged.

Caddy (see `Caddyfile.example`):

```caddy
(common) {
	encode zstd gzip
	# `handle`, not `handle_path`: the request must reach Apache as /rss/… unchanged.
	handle /rss/* {
		reverse_proxy freshrss:80 {
			header_up X-Forwarded-Host   {host}
			header_up X-Forwarded-Proto  {scheme}
			header_up X-Forwarded-Port   {server_port}
		}
	}
	redir /rss /rss/ 308
	respond 404
}

a.example { import common }
b.example { import common }
```

`header_up` is an option *inside* `reverse_proxy`, not a directive of its own; written at the top
level Caddy refuses to start with `unrecognized directive: header_up`.

nginx:

```nginx
location /rss/ {
    proxy_pass http://freshrss;          # no trailing slash, no rewrite
    proxy_set_header Host              $host;
    proxy_set_header X-Forwarded-Host  $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Port  $server_port;
}
```

Traefik — use a rule **without** a `stripprefix` middleware:

```yaml
- traefik.http.routers.freshrss.rule=PathPrefix(`/rss`)
- traefik.http.routers.freshrss.middlewares=freshrssHeaders   # X-Forwarded-* only, no stripprefix
```

Always **overwrite** `X-Forwarded-Host`. FreshRSS trusts it, and there is no allowlist unless
you configure one (see below).

> `X-Forwarded-Prefix` is supported for a proxy that *does* strip the prefix, but OIDC cannot
> work in that mode. Use a path-preserving proxy.

### 3. Nothing else to configure

`FRESHRSS_PATH_PREFIX=/rss` is **the only setting a sub-directory deployment needs.** It drives
everything at once:

| Driven by `FRESHRSS_PATH_PREFIX` | Effect |
|---|---|
| Apache `Alias` | serves `/rss/` from the FreshRSS `p/` directory |
| `OIDCRedirectURI` | becomes `/rss/i/oidc/` |
| `OIDCDefaultURL` | becomes `/rss/i/` |
| session cookie | `Path=/rss/` |
| `base_url` in `data/config.php` | the installation wizard writes `'/rss'` (the **path only**), so the host follows the request |
| `healthcheck` | probes `/rss/i/` |

Nothing under `./data/` has to be edited, and the wizard is reachable at
`https://a.example/rss/i/`. Accepted spellings: `/rss`, `rss`, `rss/`, `/rss/`.

#### Only if you need to pin a single domain

```sh
environment:
  FRESHRSS_BASE_URL: https://a.example/rss        # wins over data/config.php
  FRESHRSS_WEBSUB_BASE_URL: https://rss.example.net/rss
```

#### Only if you want WebSub

WebSub needs one stable, publicly reachable address, because the callback URL is built by the
refresh cron job, outside of any HTTP request. Set it once:

```sh
environment:
  FRESHRSS_WEBSUB_BASE_URL: https://rss.example.net/rss
```

Other domains are unaffected: they still serve the UI, the RSS feeds and the API. Only the
subscription with the hubs is pinned to that address. Then
`Administration → System configuration` shows it, and the **WebSub** checkbox is enabled.

#### Only if you want a host allowlist

Edit `./data/config.php` (there is no env var for this one):

```php
'allowed_hosts' => ['a.example', 'b.example', 'cn.example.org'],
```

Recommended unless your reverse proxy is the only thing able to set `X-Forwarded-Host`.

#### Same settings, without the environment

If you prefer to keep everything in the data volume, the wizard stores the path on its own and
you can adjust it afterwards:

```php
'base_url'         => '/rss',                          // path: host follows the request
'websub_base_url'  => 'https://rss.example.net/rss',  // WebSub: one pinned address
'allowed_hosts'    => [],                              // no restriction (default)
```

`base_url` accepts three forms: a **full URL** pins one domain (upstream behaviour), a **path**
(`/rss`) lets the host follow the request, and **empty** behaves like a path but relies entirely
on the headers the reverse proxy forwards.

| Situation | `base_url` | Consequence |
|---|---|---|
| Single domain, keep it simple | `'https://a.example/rss'` | every link pinned to `a.example` (upstream behaviour) |
| **Several domains** | `'/rss'` | links follow the domain in use |
| OIDC on several domains | `'/rss'` | `redirect_uri` becomes `https://<domain>/rss/i/oidc/` per domain |
| WebSub | `'/rss'` + `websub_base_url` | the hub talks to the single `websub_base_url` domain |

### 4. Identity provider (OpenID Connect)

OIDC is handled by **FreshRSS itself** — no Apache module, no `OIDC_ENABLED`. Set the provider
settings and pick `oidc` as the authentication method:

```yaml
environment:
  OIDC_PROVIDER_METADATA_URL: https://idp.example/.well-known/openid-configuration
  OIDC_CLIENT_ID: freshrss
  OIDC_CLIENT_SECRET: ${OIDC_CLIENT_SECRET}
  OIDC_SCOPES: openid profile email
  # OIDC_REMOTE_USER_CLAIM: preferred_username   # which claim becomes the FreshRSS username
  # OIDC_AUTO_REGISTER: '1'                      # create the account on first login
```

Then set the method once, on the data volume:

```sh
docker exec freshrss php cli/reconfigure.php --auth-type oidc
```

or choose *OpenID Connect* in the installation wizard.

Register **one redirect URI per domain** — note the query string, which is what makes this work
behind a prefix-stripping proxy:

```
https://a.example/rss/i/?c=auth&a=oidcCallback
https://b.example/rss/i/?c=auth&a=oidcCallback
```

What the implementation guarantees, and why it is safe to rely on:

| Property | Detail |
|---|---|
| Flow | authorization code + **PKCE (S256)** |
| Token verification | **RS256 only**; `alg: none` and HS256 are refused |
| Claims checked | `iss`, `aud`, `azp`, `exp`, `nbf`, `iat` (±120 s), `nonce` |
| Replay | `state` is one-time and consumed before the code is exchanged |
| Key rotation | one JWKS refetch when the key no longer matches |
| Secrets | exchanged server-to-server; plaintext provider URLs refused unless `OIDC_ALLOW_INSECURE=1` (tests only) |
| Second way in | disabled: no password form, no self-registration; auto-registered accounts get a random undisclosed password |
| Logout | RP-initiated when the provider advertises `end_session_endpoint` |

The password form and the registration page return 403/redirect on an OIDC instance, so the
provider is the only way in.

The session cookie stays host-only, so each domain has its own login. The **accounts are
shared**: every domain maps the same claim to the same FreshRSS user, so a user moving from one
domain to the other is re-authenticated by the IdP and lands in the same account.

#### The older Apache-module path still works

`OIDC_ENABLED` and `mod_auth_openidc` are still installed and configured, for deployments that
already use them; nothing changes for those. They are no longer needed, and the two paths are
mutually exclusive: `OIDC_ENABLED` protects `/rss/i/` at the web-server level, while `auth_type=oidc`
does the login inside FreshRSS. Use one or the other, not both.

For that legacy path the redirect URI is `https://a.example/rss/i/oidc/` instead, and it cannot work
behind a proxy that strips the prefix (`mod_auth_openidc` compares the path Apache sees with
`strcmp`).

---

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `FRESHRSS_PATH_PREFIX` | *(empty)* | public sub-directory, e.g. `/rss`. **The only setting a sub-directory deployment needs.** Empty = domain root. Identical on every domain. |
| `FRESHRSS_BASE_URL` | *(empty)* | pin the base URL; wins over `data/config.php`. Full URL = one domain, path = host follows the request |
| `FRESHRSS_WEBSUB_BASE_URL` | *(empty)* | address advertised to WebSub hubs; wins over `websub_base_url` |
| `TRUSTED_PROXY` | *(empty)* | proxy ranges allowed to send identity headers (`X-WebAuth-User` / `X-Remote-User`); OIDC / SSO only. It does **not** recover the client address — FreshRSS reads `CONN_REMOTE_ADDR` only |
| `OIDC_ENABLED` | *(empty)* | legacy: any non-zero value activates the Apache `mod_auth_openidc` path. **Not needed** for the built-in OIDC login, which uses `auth_type=oidc` |
| `OIDC_PROVIDER_METADATA_URL` | *(empty)* | built-in OIDC: discovery document, e.g. `https://idp.example/.well-known/openid-configuration` |
| `OIDC_ISSUER` | *(empty)* | alternative to the metadata URL; the discovery document is derived from it |
| `OIDC_CLIENT_ID` / `OIDC_CLIENT_SECRET` | *(empty)* | built-in OIDC client credentials |
| `OIDC_SCOPES` | `openid profile email` | built-in OIDC scopes |
| `OIDC_REMOTE_USER_CLAIM` | `preferred_username` | which claim becomes the FreshRSS username |
| `OIDC_AUTO_REGISTER` | `1` | create the FreshRSS account on first login |
| `OIDC_LOGOUT_REDIRECT` | `1` | also end the provider session on logout |
| `OIDC_ALLOW_INSECURE` | `0` | allow an `http://` provider — tests/local development only |
| `FRESHRSS_CSP_WARNING` | `0` | set to `1` to restore FreshRSS's "unsafe-eval" notice on admin pages. It is silenced by default: the policy forbids `unsafe-eval` on purpose and no shipped script needs it, so the notice only ever looked like a fault |
| `FRESHRSS_CSP_SCRIPT_SRC` | *(empty)* | value for `script-src`, overriding `default-src` for scripts only. Needed to let a third party injected at the edge — Cloudflare Browser Insights — actually load |
| `CRON_MIN` | `7,37 * * * *` | feed refresh schedule — a **whole** crontab expression, not just the minutes: every 30 minutes is `*/30 * * * *`. A shorter value is completed with `* * * *`. |
| `DATA_PATH` | *(empty)* | alternate data directory |

Everything else (`OIDC_*`, `FRESHRSS_INSTALL`, `FRESHRSS_USER`, `ENABLE_ACCESS_LOG`, `LISTEN`,
…) behaves exactly as upstream. `OIDC_X_FORWARDED_HEADERS` additionally defaults to
`X-Forwarded-Host X-Forwarded-Proto X-Forwarded-Port` here (upstream leaves it unset, which
breaks every reverse-proxy deployment).

This image follows the upstream Dockerfile (Debian + Apache + mod_php + `mod_auth_openidc`,
`Docker/` layout, `data/` volume, same `ENTRYPOINT`/`CMD` contract) and adds three things:
building from a pinned `FRESHRSS_REF` with a patch, the `FRESHRSS_PATH_PREFIX` support, and a
`HEALTHCHECK`. The one deliberate difference is the source fetch: upstream expects the build
context to already be a FreshRSS checkout, whereas this repository builds the pinned commit
itself so the image can be rebuilt from the patch alone.

---

## Updating FreshRSS

1. Bump `ARG FRESHRSS_REF` in `Dockerfile` to the new upstream commit (and `FRESHRSS_BRANCH` to the
   tag name, for error messages only), then the image tag in `docker-compose*.yml`, `.env.example`
   and this README.
2. Rebase the patch, in a checkout that has no `vendor/` yet:

   ```sh
   git clone https://github.com/FreshRSS/FreshRSS.git && cd FreshRSS
   git checkout <new-ref>
   git apply --check ~/nuln/docker/freshrss/patches/0001-multi-domain-and-subdirectory.patch
   git apply      ~/nuln/docker/freshrss/patches/0001-multi-domain-and-subdirectory.patch
   # resolve conflicts, then re-run the checks below, then regenerate the patch
   git add -A                       # staged, so untracked new files (login-watchdog.js, tests) are included
   git diff --cached > ~/nuln/docker/freshrss/patches/0001-multi-domain-and-subdirectory.patch
   ```

   `git diff` without `--cached` silently drops files the patch **adds**, and would produce a patch
   that no longer contains `p/scripts/login-watchdog.js` or the two test files.
   Run `composer install` only *after* regenerating: `vendor/` is then untracked noise in
   `git status`, and must never end up in the patch.

3. Verify: `vendor/bin/phpcs .`, `vendor/bin/phpstan analyse -c phpstan.dist.neon`,
   `vendor/bin/phpunit --bootstrap ./tests/bootstrap.php ./tests`.
   `.github/workflows/freshrss.yml` does all of this and fails the build with a clear message if
   the patch stops applying.

   The build **refuses to run without `DEBIAN_APT_REFRESH`**, and fails when the PHP it produced
   is older than 8.4.27. Pass today's date:

   ```sh
   docker build --build-arg "DEBIAN_APT_REFRESH=$(date -u +%Y-%m-%d)" -t ghcr.io/nuln/freshrss:1.30.4 .
   ```
4. Rebuild **and** run the suites against the new image — the patch applying is not the same thing
   as the instance behaving:

   ```sh
   docker build --build-arg "DEBIAN_APT_REFRESH=$(date -u +%Y-%m-%d)" -t ghcr.io/nuln/freshrss:1.30.4 .
   ./test/integration.sh ghcr.io/nuln/freshrss:1.30.4
   ./test/functional.sh  ghcr.io/nuln/freshrss:1.30.4
   ./test/browser.sh     ghcr.io/nuln/freshrss:1.30.4
   ./test/upgrade.sh     ghcr.io/nuln/freshrss:1.30.4 ghcr.io/nuln/freshrss:<previous tag>
   ```

   `test/upgrade.sh` is the one that matters most when the upstream version changes: it starts the
   old image, builds a real installation on a volume, then starts the new image **on that same
   volume** and checks that the subscription, the articles, the users, the API password and the
   per-user config all survived. Cold-start tests cannot catch a broken migration.

   `docker exec <container> php -v` must report `8.4.27` or later. The build itself refuses to
   produce an image with a PHP older than that (CVE-2026-109618/9), so a green build that then
   reports an older version means the container is not the image you just built.

   **Rebuild on a schedule too, not only when FreshRSS releases.** A CVE in a PHP extension needs no
   upstream release at all: the fix arrives in `trixie-security`, and nothing except a rebuild picks
   it up. Nothing today does this automatically — the workflow only runs on a push under
   `freshrss/**` — so a monthly rebuild (manually, or `workflow_dispatch`, or a `schedule:` entry)
   is the practical minimum for an internet-facing instance.


## Notes and limits

- **All domains must share the same sub-directory.** `FRESHRSS_PATH_PREFIX` is a single value
  because the OIDC callback and the cookie scope are derived from it. `https://a.example/rss`
  and `https://b.example` cannot be served by the same container.
- The Apache `mod_alias` module is re-enabled **only** when `FRESHRSS_PATH_PREFIX` is set. Its
  target is the same directory as `DocumentRoot`, so nothing extra becomes reachable.
- The first request or two after a cold start may return 500 while `data/` is being prepared;
  it settles within a couple of seconds. The `HEALTHCHECK` probe retries.
- Changing `FRESHRSS_PATH_PREFIX` on an existing install invalidates session cookies (path
  change) and requires re-registering the OIDC redirect URIs. **Clear the browser's cookies as
  well**: cookie identity is (name, domain, path), so the cookie from the previous configuration
  keeps being sent alongside the new one — broader path first, and PHP keeps the last entry for a
  repeated name. The stale one then shadows the valid one and every login silently fails. The
  symptom is a login form that accepts the correct credentials and returns to itself, with no error
  anywhere; deleting the cookies in the browser resolves it immediately.
- Upstream's built-in update mechanism is disabled (`disable_update`): update the image instead.

### Content-Security-Policy and Cloudflare Browser Insights

FreshRSS sends `Content-Security-Policy: default-src 'self'; frame-ancestors 'none'`, hard-coded in
`lib/Minz/ActionController.php`. Only `frame-ancestors` has a configuration key (`csp.frame-ancestors`,
editable in the admin UI); `default-src` has none, and extensions can only amend it in PHP.

That policy is deliberately strict and it does its job — it also blocks the
`static.cloudflareinsights.com/beacon.min.js` that Cloudflare injects at the edge, so Browser
Insights collects nothing and the console fills with violations. To keep the feature, allow its origin. The
container can do it itself, which needs no change to the proxy at all:

```sh
FRESHRSS_CSP_SCRIPT_SRC="'self' https://static.cloudflareinsights.com"
```

`script-src` overrides `default-src` for scripts only, so every other directive keeps falling back
to `default-src 'self'`.

It is applied in `Minz_ActionController::declareCspHeader()`, at the single point where the header
is assembled — not during bootstrap. Controllers replace the whole policy through `_csp()`;
`indexController` does, to permit frames, images and media, so a value set earlier is silently
dropped on the reader page and only the login page carries it. The startup log line
(`docker logs freshrss | grep CSP`) confirms the value reached the container: an entry in `.env`
only takes effect because the compose files pass the variable through. The same thing can be done at the proxy instead, if you would rather not
put it in the environment; see the commented block in `Caddyfile.example`:

```caddyfile
header_down Content-Security-Policy "default-src 'self'; script-src 'self' https://static.cloudflareinsights.com; frame-ancestors 'none'"
```

Three things that are easy to get wrong, all verified in section 5a6 of the suite:

- It must **replace** the header, not add to it. Several CSP headers are enforced as their
  **intersection** — the most restrictive of them — so appending a permissive `script-src`
  alongside the original relaxes nothing. Caddy's `+Content-Security-Policy` form does exactly
  that and therefore does not work.
- `script-src` overrides `default-src` for scripts only. Every other directive still falls back to
  `default-src 'self'`, so the policy keeps working.
- A source must name a scheme and, unless it is the default for that scheme, the port. CSP matches
  host **and** port exactly: `https://static.cloudflareinsights.com` permits 443 and nothing else.

The beacon reports to `/cdn-cgi/rum` on the site's own origin, which `default-src 'self'` already
covers — no `connect-src` change is needed.

### When the login button does nothing

Upstream ships the login form's submit button **disabled**, and only `p/scripts/extra.js` enables
it — after `main.js` has published `window.context` and `scripts/vendor/bcrypt.js` has loaded. If
any of those three never arrives, the page renders, the button does nothing, and **no request is
ever sent**: the failure is completely silent.

This image adds `p/scripts/login-watchdog.js`, which the login page loads for that reason. It
reloads once — a dropped request is usually transient — and then says which scripts to check. It
cannot help when *every* sub-resource stalls, because it is itself a sub-resource; in that case the
page arrives unstyled, which is itself the visible symptom.

To tell the cases apart, open the browser's Network panel and reload the login page:

| What you see | Cause |
|---|---|
| A request stuck in `(pending)`, never completing | the reverse proxy cannot serve parallel requests — the page needs six at once (document, two stylesheets, three scripts) |
| `Failed to load resource` in the console | a script is filtered, blocked or 404 |
| `FreshRSS waiting for bcrypt.js…` repeating | `scripts/vendor/bcrypt.js` never loaded |
| A red banner naming the scripts | the watchdog reporting the above |

A single-threaded proxy is enough to cause this: PHP's built-in server deadlocks against a browser
that opens six connections, which is why the test proxy in `test/strip-proxy.php` sets
`PHP_CLI_SERVER_WORKERS`.

## Files

| Path | Role |
|---|---|
| `Dockerfile` | builds upstream at a pinned ref and applies the patch |
| `patches/0001-…patch` | the whole change, reviewable and re-appliable |
| `FreshRSS.Apache.conf` | upstream conf + env-driven `OIDCRedirectURI` + `IncludeOptional` for the prefix |
| `entrypoint.sh` | normalises the prefix, exports the OIDC paths, generates the `Alias`, hands over to the upstream entrypoint |
| `healthcheck.sh` | probes `<prefix>/i/`, fails loudly on a broken sub-directory mapping |
| `test/integration.sh` | 231-check end-to-end test (sub-directory, domains, OIDC login, WebSub, strip mode, email validation, allowed_hosts) |
| `test/functional.sh` | 68-check end-to-end test of the product itself (install → login → subscribe → read → API) |
| `test/caddy-routes.py` | prints a Caddy JSON config's route order and names the route that answers each path — for when a catch-all is eating `/rss` |
| `test/caddy-routes.sh` | asserts that ordering for every proxy shape documented here, including the shapes that fail |
| `test/browser-login.py` | logs in with a real Chromium: the crypto chain, the POST, the cookie, the reader view |
| `test/browser-csp.py` | checks the served CSP in a browser: no executable inline script, and a third-party origin allowed or refused as configured |
| `test/browser.sh` | runs that three ways — direct, behind a prefix-stripping proxy, behind Caddy — plus the withheld-scripts case |
| `test/mock-idp.php` | minimal but complete OIDC provider: discovery, JWKS, RS256 `id_token`, code flow |
| `test/mock-websub-hub.php` | minimal WebSub hub **and** prefix-preserving reverse proxy used by the test |
| `test/smtp-sink.php` | minimal SMTP server that captures the email-validation message |
| `test/fixtures/index.php` | RSS publisher that can advertise a hub and move its `rel="self"` |
| `test/bcrypt-challenge.sh` | reproduces the browser login inside the container |
| `Caddyfile.example` | recommended reverse-proxy configuration |
| `Caddyfile.outer.example` / `Caddyfile.inner.example` | the two-hop variant, when a proxy in front of Caddy already terminates the connection |
| `docker-compose.two-hop.yml` | edge Caddy + inner Caddy + FreshRSS, wired on one network; the inner Caddy deliberately publishes no port |
| `docker-compose.yml` | one-command deployment: `docker compose up -d`, published on localhost, auto-installed |
| `docker-compose.proxy.yml` | the same behind a reverse proxy, on an external network, no published port |
| `.env.example` | every variable the compose files read, with defaults |
