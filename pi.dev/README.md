# Pi (pi.dev Coding Agent) — Docker All-in-One Development Box

Built on [Pi Coding Agent](https://pi.dev) (`earendil-works/pi`), modeled after the OpenCode image architecture.

**pi and its runtime environment and dependencies are fully baked into the image — it works out of the box**: Node 24, pi CLI, git, ripgrep (required by pi's built-in grep tool), curl, ca-certificates, make/gcc and other base dependencies are all in the image. No post-start install needed.

The image does **not** bundle any compiler toolchain by default. Language environments (Go / Rust / TypeScript / ...) are installed on demand by the built-in `install.sh` — you decide what and when. Everything is installed into the mounted `data/cache`, and is restored automatically after the container is recreated.

## Baked in at build time (pi's base environment and dependencies)

| Component | Description |
|-----------|-------------|
| `node` / `npm` | pi's Node runtime (>= 22.19, from the base image node:24-bookworm) |
| `pi` | `@earendil-works/pi-coding-agent` CLI (npm global install) |
| `git` | version control |
| `ripgrep` | required by pi's built-in grep tool (official Dockerfile.pi ships it) |
| `bash` | the shell pi uses to run commands |
| `curl` / `ca-certificates` | HTTP requests / TLS certificates |
| `make` / `gcc` | for `install.sh` source builds (lua/php) |
| `tmux` | pi multi-instance parallel running (official docs recommend it) |
| `less` | terminal paging / log viewing |
| `zsh` | alternate shell |

All installed during `docker build`; pi is usable immediately after the container starts.

**All curated plugins are preinstalled in the image** (see [PLUGINS.md](PLUGINS.md)): core MCP/subagents/LSP, permission/security, IM (Telegram/Feishu/WeChat), Web UI (`pi-web-chat`), remote control (`remote-pi`), and memory. They live in the image layer at `/home/pi/.pi-plugins` — outside the mounted config dir, so the mount can never shadow them. On the first container start the s6 service `wire-plugins` writes a settings.json that references them by absolute path (pi loads them directly, no copying) — nothing to run.

## Differences from the official containerization approach

- The official `Dockerfile.pi` only installs pi + bash/git/ripgrep; language toolchains must be installed into the image manually (large, not persistent).
- This approach: pi and its runtime deps are also baked in, but language toolchains are installed on demand into a persistent volume (does not grow the image).

## Build

```bash
# local build (pinned by default; bump PI_VERSION in Dockerfile for a new release)
docker build -t pi.dev:0.84.1 .
```

## Usage

```bash
cp .env.sample .env            # edit configuration

# create the mount dirs (ownership MUST be 1000:1000 so the container's pi user, uid 1000, can write)
mkdir -p data/pi data/cache data/workspace
chown -R 1000:1000 data/       # required on Linux/NAS; can be skipped on macOS Docker Desktop

docker compose up -d           # run pi in the background (or `docker compose up` to enter pi in the foreground)
```

> Why `chown 1000:1000`: compose bind-mounts host dirs (`./data/*`), and Docker does not change the ownership of host dirs. If the owner is not uid 1000, the container's `pi` user cannot write into them, and plugin/toolchain installs will fail. Create the dirs yourself on the host — no script needed.
>
> Existing stacks that used the old `./data/agent` mount: migrate once with `mkdir -p data/pi && mv data/agent data/pi/agent` (the container config dir is now the whole `~/.pi`, which also persists web-chat and remote-pi state).

### Enter the pi interactive UI

The image is supervised by [s6-overlay v3](https://github.com/just-containers/s6-overlay) (`/init` is PID 1). On first start the s6 service `wire-plugins` wires the preinstalled plugins into the mounted config dir (writes a settings.json referencing the baked store by absolute path), the `pi-web` service auto-starts the Web UI daemon (`pi --web --lan`, http://<host>:3141), and CMD launches the pi TUI in the foreground (working dir `/home/pi/dev`):

```bash
# Way 1: foreground, straight into pi (official Plain Docker style)
docker compose up

# Way 2: background, then exec a pi session
docker compose up -d
docker compose exec -it pi pi
```

Skills are baked into the image at `/etc/s6-overlay/plugins/skills` but are
**NOT loaded by default**. To enable them, set `PI_SKILLS` in `.env` and
recreate the container; on first boot `wire-plugins` copies them into
`~/.agents/skills/` (pi's native global skill dir):

| `PI_SKILLS` | Effect |
|-------------|--------|
| `true` | copy **all 33** curated skills |
| `a,b,c` | copy **only** the listed skills (whitelist); unknown names are skipped with a warning |
| `false`/empty | not loaded (default) |

```bash
PI_SKILLS=true            # everything
PI_SKILLS=tdd,browser     # just those two
```

1. **Your own / chosen skills** — put a directory with a `SKILL.md` (name +
   description frontmatter) under
   `pi.dev/rootfs/etc/s6-overlay/plugins/skills/<skill-name>/`. Rebuild the
   image. With `PI_SKILLS=true` (or its whitelist) they load on the next fresh boot.

2. **Third-party skill packages** — add the npm package to
   `rootfs/etc/s6-overlay/scripts/install.d/plugins.sh` (any array, e.g. `CORE`);
   `pi install npm:<pkg>` bakes it into the plugin store at build time and pi
   discovers its `skills/` via the package manifest. Or `docker compose exec pi
   pi install npm:<pkg>` at runtime.

### Install programming environments on demand (in-container script)

`install.sh` inside the container, run on demand, independent of each other:

```bash
# Go only (does not affect others)
docker compose exec pi install.sh go

# Rust + TypeScript only
docker compose exec pi install.sh rust node-tools

# Java + Kotlin (kotlin auto-installs JDK first)
docker compose exec pi install.sh java kotlin

# JVM family + modern runtimes
docker compose exec pi install.sh java bun scala kotlin

# Lua / PHP (official source builds, using the image's bundled gcc+make)
docker compose exec pi install.sh lua php

# DB / storage CLI clients (MySQL, PostgreSQL, Redis, SQLite, MinIO client)
docker compose exec pi install.sh db-clients

# Update installed Go to latest (--update forces reinstall)
docker compose exec pi install.sh go --update
```

Supported targets: `go` / `rust` / `java` / `bun` / `scala` / `kotlin` / `lua` / `php` / `node-tools` (TypeScript etc.) / `db-clients` (MySQL / PostgreSQL / Redis / SQLite / MinIO `mc`).

> The image also **bakes in** a few base CLI tools: `gh` (GitHub CLI, `gh auth login`) and `wrangler` (Cloudflare Workers/Pages/D1/R2) — usable immediately, no `install.sh` needed.

### Scaffold new projects (`new-project`)

The image ships starter templates that scaffold a project into the working dir
(`/home/pi/dev`) with zero network and the image's own toolchains:

```bash
docker compose exec pi new-project --list   # show templates (go rust node python worker)
docker compose exec pi new-project go my-api  # scaffold Go HTTP API into my-api/
docker compose exec pi new-project worker cf-app
docker compose exec pi new-project rust rsvc
```

`{{ PROJECT }}` in template filenames/contents is replaced with the target dir
name. Add your own by dropping a directory under
`pi.dev/rootfs/etc/s6-overlay/templates/<name>/` (any file ending `.tpl` gets
the substitution + suffix stripped) and rebuilding the image.

### Healthcheck

The image declares a `HEALTHCHECK`; with the default `PI_AUTOSTART_WEB=1` the
container is healthy once the Web UI answers on `:3141`, so `docker compose
ps` shows the real boot state. Set `PI_AUTOSTART_WEB=0` and it degrades to a
liveness check (never falsely marks the box sick just because the UI is off).

A **pi-watchdog** s6 longrun supervises the Web UI daemon: if `:3141` stops
answering (and autostart is on) it restarts `pi --web` automatically, honoring
`PI_WEB_ARGS`. Tune the poll with `PI_WATCHDOG_INTERVAL` (default 30s). It
tracks restart count + crash-loop state in `~/.pi/agent/pi-watchdog.json`, and
after `PI_WATCHDOG_MAX_FAILURES` (default 3) consecutive failed restarts it
backs off instead of relaunching blindly.

### Inspect loaded skills (`skills`)

```bash
docker compose exec pi skills      # loaded skills (name + description)
docker compose exec pi skills -a     # every skill available in the image
docker compose exec pi skills tdd    # confirm tdd is loaded (exit 0/1)
```

### Reclaim disk space (`install.sh gc`)

Installed language toolchains live in the `data/cache` volume. Clean them on
demand:

```bash
docker compose exec pi install.sh gc          # list cached toolchains + sizes
docker compose exec pi install.sh gc go rust  # remove specific ones
docker compose exec pi install.sh gc --all    # remove every cached toolchain
```


### Plugin ecosystem (extend pi's capabilities)

pi has a huge plugin catalog (the official catalog has 5000+ packages, categorized by download count in [PLUGINS.md](PLUGINS.md)). The curated set is **preinstalled in the image by default** (baked into `/home/pi/.pi-plugins`, wired into the mounted `data/pi` on first start), so the box is usable immediately — no install step.

**Web UI (usable right away):** the s6 service `pi-web` auto-starts `pi --web --lan` on container start, so open `http://<host>:3141` in a browser after `docker compose up -d`. Control it with `docker compose exec pi pi --web status|stop|restart`. Disable the autostart with `PI_AUTOSTART_WEB=0` in `.env`.

**remote-pi (phone control):** the extension is preinstalled. In a pi session run `/remote-pi` (first time answers the wizard: agent name, session, auto-start relay) then `/remote-pi pair` and scan the QR with the Remote Pi mobile app. Pairing/relay config persist in `data/pi/remote`.

**IM channels:** the Telegram / Feishu / WeChat plugins are preinstalled too; each channel still needs its own bot credential (see table below) and its own `/telegram` `/feishu` `/wechat` setup.

To add, remove or update plugins (the preinstalled set is baked into the image; changes made here persist in `data/pi`):

```bash
docker compose exec pi install.sh plugins all       # (re)install the full curated set
docker compose exec pi install.sh plugins --im       # install only one group
docker compose exec pi pi install npm:pi-subagents   # add a specific plugin (one per call)
docker compose exec pi pi remove npm:<package>       # remove
docker compose exec pi pi update --extensions        # update
docker compose exec pi pi list                       # list installed
```

To change which plugins ship by default, edit the arrays in section "4. pi plugins" of `install.sh` and rebuild the image.

**IM channel setup (each channel has its own bot credentials):**

| Channel | Plugin | Config |
|---------|--------|--------|
| Telegram | `@llblab/pi-telegram` | Create a bot via BotFather for a token, inject `TELEGRAM_BOT_TOKEN` |
| Feishu/Lark | `pi-feishu-lark` | Scan to create a bot, `FEISHU_APP_ID`/`FEISHU_APP_SECRET`; card callback default port 3001 (already mapped) |
| WeChat | `pi-wechat-assistant` | WeChat iLink scan-to-connect, `/wechat login` → `/wechat start`, phone becomes a remote for a pi session |

> Security note: IM channels bind 127.0.0.1 by default — **do not expose them to the public internet** (no built-in auth). For remote access use Tailscale / SSH tunnel. Feishu card interaction needs a publicly reachable URL; put it behind Tailscale serve or a trusted reverse proxy.

The full plugin list, curated picks, conflict analysis and recommended preinstall are in **[PLUGINS.md](PLUGINS.md)**.

### Dependencies

- `scala` / `kotlin` depend on the JVM; if `cache/jdk` is missing, install **auto-installs Java first** — no manual step.
- `lua` / `php` are built from official source (using the image's bundled gcc/make, zero extra system libs).
- Node and Python 3 come from the base image `node:24-bookworm` (bundles python3), not from the script.

### Install size reference (installed into data/cache; install only what you need)

| Target | Approx size | Notes |
|--------|-------------|-------|
| go | ~260M | |
| rust | ~520M | minimal profile keeps it small |
| java | ~310M | Temurin JDK |
| bun | ~90M | |
| scala | ~30M + extra first-run downloads | depends on java |
| kotlin | ~80M | depends on java |
| lua | a few MB (build output) | official source build |
| php | tens of MB (build output) | official source build, minimal CLI |
| node-tools | ~10M | TypeScript only |

Installing everything is about **2.5G–3G**; install only the languages you need. Everything persists in the mounted `data/cache` and is restored after container recreation.

## Core mechanism

**Each target installs independently with its own environment variables**: the install function first checks whether it is already installed (skips download if so), then writes that tool's env vars into **its own `env.sh`** (e.g. `cache/go/env.sh`, persisted with the cache), and appends a `source` line to `~/.profile` (skipped if already present, no accumulation). After deleting/recreating the container and re-mounting the cache, re-running install reuses everything.

**BASH_ENV lets the pi process load the environment automatically (no restart)**: at build time `install.sh setup-bash-env` writes `/etc/pi-env.sh` that sources each tool's `env.sh`, and the image sets `BASH_ENV=/etc/pi-env.sh`. pi runs commands via `/bin/bash` without reading `~/.profile`, so this makes installed tool environments load in every pi command. After installing, **go / cargo / tsc etc. work immediately inside the pi process** — no docker restart, no manual `source`.

**Persistence & recreation**:
- Environments live in the mounted `data/cache`; recreating the container and re-mounting restores everything — the script skips downloads of already-installed tools (unless `--update`) and only re-adds the env vars.
- After re-mounting, no reinstall is needed: BASH_ENV sources the tool env.sh on every startup, just `docker restart <container>`; or re-run `install.sh <target>` (skips download if installed, only ensures the vars are written).

Verified cycle: 1. start -> install go/lua -> `go`/`lua` work in the pi process; 2. delete the container -> restart (re-mount cache) -> the script skips all downloads -> the previous programming environment still works in the pi process.

## Configuration

### Environment variables (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| `TZ` | timezone | `Asia/Shanghai` |
| `PI_IMAGE` | image name | `ghcr.io/nuln/pi.dev:0.84.1` |
| `CARGO_BUILD_JOBS` | Rust parallel build jobs | `1` |
| `GOMAXPROCS` | Go parallelism | `2` |
| `MAKEFLAGS` | make parallelism | `-j2` |
| `MEM_LIMIT` / `CPU_LIMIT` | container memory/CPU caps | `4g` / `2` |
| `PI_SKILLS` | load baked skills (`true`/whitelist/`false`) | `false` |
| `PI_WATCHDOG_INTERVAL` | web-UI self-healing poll (s) | `30` |
| `PI_WATCHDOG_MAX_FAILURES` | back off after N failed restarts (crash-loop guard) | `3` |

### AI provider accounts

Pi supports two ways to connect:

1. **Environment variable** (API-key type): `export` in a `docker compose exec` session, or inject into the container env:
   ```bash
   docker compose exec -it -e ANTHROPIC_API_KEY=sk-ant-... pi pi
   ```
   pi reads standard env vars such as `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` / `DEEPSEEK_API_KEY` / `GEMINI_API_KEY` / `OPENROUTER_API_KEY`.

2. **`auth.json`** (recommended, persistent): write it into the mounted `data/pi/agent/auth.json` (i.e. `~/.pi/agent/auth.json`), persisted with the volume and auto-refreshed:
   ```json
   { "anthropic": { "type": "api_key", "key": "sk-ant-..." } }
   ```
   You can also run `docker compose exec -it pi pi` and log in interactively with `/login` (OAuth or manual key); credentials persist in `data/pi/agent/auth.json`.

Key priority: CLI `--api-key` > `auth.json` > environment variables.

### Volume layout

| Volume | Container path | Purpose |
|--------|----------------|---------|
| `./data/pi` | `/home/pi/.pi` | pi config/state: sessions, auth, web-chat, remote-pi pairing/relay, and plugins the **user** installs later. The preinstalled plugin store is baked into the image at `/home/pi/.pi-plugins` (outside this mount) and referenced by absolute path |
| `./data/cache` | `/home/pi/cache` | language toolchains (core persistence) |
| `./data/workspace` | `/home/pi/dev` | code working dir (short dir under home) |

## Notes

- Container user is `pi` (uid 1000); the image defaults to `USER pi`, default working dir `/home/pi/dev`.
- The mount dirs `data/*` are created and owned by you on the host (`chown 1000:1000`); on macOS `chown` may report Operation not permitted, which is a filesystem limitation — ignore it, or `chmod` to ensure the dirs are writable.
