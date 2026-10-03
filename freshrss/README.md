# freshrss

FreshRSS, patched so that **one instance can be served from a sub-directory, through several
domains at the same time**, with OIDC and WebSub working.

Everything is a single patch on top of upstream FreshRSS (`patches/`), so the change is easy to
review and to re-apply on a newer release.

| | |
|---|---|
| Image | `ghcr.io/nuln/freshrss:1.30.0` (pinned upstream version) and `:latest` — **private package, see "Pulling the image"** |
| Base | Debian + Apache + mod_php + `mod_auth_openidc` (required for OIDC) |
| Upstream | **1.30.0** (the latest release), pinned by commit in `ARG FRESHRSS_REF` |
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

The image is built from the **1.30.0 release tag**, not from the development branch, so the
published tag says `1.30.0` and the code is a released version.

FreshRSS merged several security fixes *after* 1.30.0, three of which touch exactly the files this
patch modifies. Dropping them silently would have made this image weaker than the multi-domain
build it replaces, so two of them are carried inside the patch:

| Upstream fix | Why it is here |
|---|---|
| `64f7f24` Improve WebSub security | re-enables the self-URL check in `p/api/pshb.php` that 1.30.0 ships commented out; this patch works on that same endpoint |
| `6780afe` Reject token access for disabled accounts (CWE-613) | one line in `lib/Minz/Request.php`, which this patch also changes |

One is **not** carried, deliberately:

| Upstream fix | Why not |
|---|---|
| `5a270c0` Rotate session ID on all authenticated transitions (CWE-384) | it conflicts with this patch in `lib/Minz/Session.php`, and on the 1.30.0 base its callers catch a `RuntimeException` that the analysis proves is never thrown — `catch.neverThrown` in `app/Models/Auth.php` and `app/Controllers/userController.php`, which fails the project's own PHPStan level 10 gate. Shipping code that does not pass the upstream analyser is not acceptable, so this one waits for upstream's next release. |

The remaining post-1.30.0 fixes (`d5ad610` CWE-294, `a625348` CWE-352, `cd42dc7` CWE-409) touch no
file this patch modifies and are listed here only for completeness; they are **not** present either.

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

`test/integration.sh` — 178 checks against a real Apache + PHP + `mod_auth_openidc` stack, with a
mock identity provider, a mock WebSub hub and a mock reverse proxy:

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

Upstream's own gates pass on the patched tree: `phpcs`, **PHPStan level 10 with zero errors**,
and the whole PHPUnit suite — 778 tests, 1472 assertions, no failures. The 41 added tests live in
`tests/lib/Minz/RequestTest.php` and `tests/lib/Minz/UrlTest.php`.

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
- `create-user.php --email` does **not** send a validation mail: it stores `mail_login` before
  calling the updater, so the "the address changed" branch that signs the token never fires. The
  address has to be set from the profile form (or `FreshRSS_user_Controller::updateUser()`, which is
  what that form calls) for the mail to be sent. Upstream behaviour, not a side effect of the patch.
- **Only `linux/arm64` was tested locally**, because the machine that produced this image had no
  access to a registry to pull an `amd64` base image. The CI workflow runs the same suites on
  `linux/amd64`, so the multi-architecture claim rests on CI, not on a local run.

### Pulling the image

The package on GitHub Container Registry is **private**, so a plain `docker pull` is refused. Pick
whichever suits the deployment:

```sh
# 1. Authenticate once with a personal access token that has the `read:packages` scope
#    (classic token: "read:packages"; fine-grained token: Packages → Read).
echo "$GHCR_TOKEN" | docker login ghcr.io -u nuln --password-stdin
docker pull ghcr.io/nuln/freshrss:1.30.0

# 2. Or make the package public once, in the GitHub UI, and then no credentials are needed at all:
#    https://github.com/users/nuln/packages/container/package/freshrss/settings
#    → "Change visibility" → Public. Recommended for anything that is not secret: the image is a
#    public build of a public project, and this repository already holds its source.
```

The published tags are the upstream version the patch is based on — currently **`1.30.0`** — plus
**`latest`**. Both point at the same multi-architecture manifest (`linux/amd64` and `linux/arm64`),
so the right thing to deploy is the version tag, not `latest`:

```yaml
services:
  freshrss:
    image: ghcr.io/nuln/freshrss:1.30.0   # pinned; `latest` moves
```

Pin by digest if the deployment must be byte-reproducible:

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

Both files take the image from `${FRESHRSS_IMAGE:-ghcr.io/nuln/freshrss:1.30.0}`, so a test run can
point them at a locally built image without editing the file.

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

### 4. Identity provider

Register **one redirect URI per domain** (port required by Authentik):

```
https://a.example:443/rss/i/oidc/
https://b.example:443/rss/i/oidc/
```

`OIDC_X_FORWARDED_HEADERS` defaults to `X-Forwarded-Host X-Forwarded-Proto X-Forwarded-Port`
in this image (upstream leaves it unset, which breaks every reverse-proxy deployment).

The session cookie stays host-only, so each domain has its own login. The **accounts are
shared**: OIDC maps `OIDC_REMOTE_USER_CLAIM` (default `preferred_username`) to a FreshRSS user,
and a user moving from one domain to the other is silently signed in by the IdP.

---

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `FRESHRSS_PATH_PREFIX` | *(empty)* | public sub-directory, e.g. `/rss`. **The only setting a sub-directory deployment needs.** Empty = domain root. Identical on every domain. |
| `FRESHRSS_BASE_URL` | *(empty)* | pin the base URL; wins over `data/config.php`. Full URL = one domain, path = host follows the request |
| `FRESHRSS_WEBSUB_BASE_URL` | *(empty)* | address advertised to WebSub hubs; wins over `websub_base_url` |
| `TRUSTED_PROXY` | *(empty)* | proxy ranges allowed to send identity headers (`X-WebAuth-User` / `X-Remote-User`); OIDC / SSO only. It does **not** recover the client address — FreshRSS reads `CONN_REMOTE_ADDR` only |
| `OIDC_ENABLED` | *(empty)* | any non-zero value activates OIDC |
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

1. Bump `ARG FRESHRSS_REF` in `Dockerfile` to the new upstream commit.
2. Rebase the patch:

   ```sh
   git clone https://github.com/FreshRSS/FreshRSS.git && cd FreshRSS
   git checkout <new-ref>
   git apply --check ~/nuln/docker/freshrss/patches/0001-multi-domain-and-subdirectory.patch
   git apply      ~/nuln/docker/freshrss/patches/0001-multi-domain-and-subdirectory.patch
   # resolve conflicts, then re-run the checks below, then regenerate the patch
   git diff > ~/nuln/docker/freshrss/patches/0001-multi-domain-and-subdirectory.patch
   ```

3. Verify: `vendor/bin/phpcs .`, `vendor/bin/phpstan analyse -c phpstan.dist.neon`,
   `vendor/bin/phpunit --bootstrap ./tests/bootstrap.php ./tests`.
   `.github/workflows/freshrss.yml` does all of this and fails the build with a clear message if
   the patch stops applying.

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
| `test/integration.sh` | 230-check end-to-end test (sub-directory, domains, OIDC login, WebSub, strip mode, email validation, allowed_hosts) |
| `test/functional.sh` | 68-check end-to-end test of the product itself (install → login → subscribe → read → API) |
| `test/browser-login.py` | logs in with a real Chromium: the crypto chain, the POST, the cookie, the reader view |
| `test/browser-csp.py` | checks the served CSP in a browser: no executable inline script, and a third-party origin allowed or refused as configured |
| `test/browser.sh` | runs that three ways — direct, behind a prefix-stripping proxy, behind Caddy — plus the withheld-scripts case |
| `test/mock-idp.php` | minimal but complete OIDC provider: discovery, JWKS, RS256 `id_token`, code flow |
| `test/mock-websub-hub.php` | minimal WebSub hub **and** prefix-preserving reverse proxy used by the test |
| `test/smtp-sink.php` | minimal SMTP server that captures the email-validation message |
| `test/fixtures/index.php` | RSS publisher that can advertise a hub and move its `rel="self"` |
| `test/bcrypt-challenge.sh` | reproduces the browser login inside the container |
| `Caddyfile.example` | recommended reverse-proxy configuration |
| `docker-compose.yml` | one-command deployment: `docker compose up -d`, published on localhost, auto-installed |
| `docker-compose.proxy.yml` | the same behind a reverse proxy, on an external network, no published port |
| `.env.example` | every variable the compose files read, with defaults |
