# OpenCode

A Docker image based on official OpenCode (`github.com/anomalyco/opencode`), optimized for low-power machines (J3455/N5105) and accessed over the LAN via Tailscale.

The image **ships without any compiler toolchain by default**. Coding environments (Go / Rust / TypeScript, etc.) are installed **on demand** by the built-in `install.sh` script — after the container starts, you decide when and which to install. All environments live in the mounted `data/cache`, so they persist and are restored simply by re-mounting the volume after a container rebuild.

## Build

The image is built automatically by CI (`.github/workflows/opencode.yml`) for multiple architectures (amd64/arm64) and pushed to:

```
ghcr.io/nuln/opencode:latest
ghcr.io/nuln/opencode:<version>
```

The version is taken from the latest release of the official npm package `opencode-ai`. To build locally:

```bash
docker build -t ghcr.io/nuln/opencode:latest opencode
```

## Local testing

If you just want to quickly verify opencode runs (without installing the full Go/Rust/Python toolchain and without low-power constraints), build with `Dockerfile`:

```bash
cd opencode
# Build the image
docker build -f Dockerfile -t opencode-test .

# Start with the free-model config (chat with zero keys)
docker run -d -p 4096:4096 \
  -v "$(pwd)/opencode.free.json:/home/opencode/.config/opencode/opencode.json" \
  opencode-test

# Open in browser
open http://localhost:4096
```

- Contains only Node + opencode; starts fast (~6s), good for local smoke tests.
- The default `opencode.free.json` uses official free models and needs **no API key** to chat.
- With an OpenCode Go plan, inject `OPENCODE_API_KEY` into the runtime to select `opencode-go/*` models (see "OpenCode Go plan" below).
- This image **does not include a Go/Rust/Python toolchain by default** (nothing is installed on start), so the agent is limited when compiling after writing code; install on demand with `install.sh` when needed (see below). For production use `docker compose` (see below).

### Install coding environments on demand (in-image script)

The image ships `install.sh`, run **when you decide** — it does not auto-run on container start. All environments are installed under `$OPENCE_CACHE` (default `/home/opencode/cache`); mount that directory at start for **persistence** (re-mount after rebuild to restore, no reinstall needed):

```bash
# Mount the cache directory at start (persist coding environments)
docker run -d -p 4096:4096 \
  -v "$(pwd)/data/cache:/home/opencode/cache" \
  -v "$(pwd)/opencode.free.json:/home/opencode/.config/opencode/opencode.json" \
  opencode-test
```

Enter the container to install on demand (single, multiple, or update):

```bash
# Install only Go (does not affect others)
docker exec -it <container> install.sh go

# Install only Rust + TypeScript
docker exec -it <container> install.sh rust node-tools

# Install Java + Kotlin (kotlin auto-installs the JDK first)
docker exec -it <container> install.sh java kotlin

# Install JVM family + modern runtimes: java bun scala kotlin
docker exec -it <container> install.sh java bun scala kotlin

# Install Lua / PHP (official source build, using the image's bundled gcc+make)
docker exec -it <container> install.sh lua php

# Update installed Go to the latest (--update forces reinstall)
docker exec -it <container> install.sh go --update

# Update everything installed
docker exec -it <container> install.sh --update
```

Supported targets: `go` / `rust` / `java` / `bun` / `scala` / `kotlin` / `lua` / `php` / `node-tools` (TypeScript, etc.).

**Dependencies**:
- `scala` / `kotlin` run on the JVM and depend on `java`. When installing either, if `cache/jdk` is missing the script **auto-installs Java first** — no manual step required.
- **`lua` / `php` are built from official source** (see "Source build & multi-arch" below) using the image's bundled `gcc`/`make`, no extra system libs needed.
- Node itself and Python 3 come from the base image `node:24-bookworm` (includes python3.11) and are not in the script; `node-tools` is just npm global packages (e.g. TypeScript).

**Source build & multi-arch support**:
- The script detects architecture via `uname -m` throughout and **supports both `amd64` (x86_64) and `arm64` (aarch64)**. When building the image use `docker buildx build --platform linux/amd64,linux/arm64` for a multi-arch image.
- `lua`: download official source from `lua.org`, `make linux` into `cache/lua` (pure gcc, no extra deps).
- `php`: download official source from `php.net`, `./configure --disable-all --enable-cli && make` to build a minimal CLI into `cache/php`. **No extensions by default**; add them by reinstalling with `--enable-xxx` in `./configure` (the matching `-dev` system lib must be installed by root via `apt`). The compiled binary is fully transparent with no third-party backdoor risk.
- `go`/`rust`/`java`/`bun` are official prebuilt binaries, also auto-selected for x86_64 / aarch64 per architecture.

**Size notes** (installed into `data/cache`, single-arch estimate; install on demand, not all at once):

| Target | Est. size | Notes |
|--------|-----------|-------|
| go | ~260M | |
| rust | ~520M | minimal profile already smallest, still large |
| java | ~310M | Temurin JDK |
| bun | ~90M | |
| scala | ~30M + extra download on first run | depends on java |
| kotlin | ~80M | depends on java |
| lua | ~few MB (build output) | official source build |
| php | ~tens of MB (build output) | official source build, minimal CLI |
| node-tools | ~10M | TypeScript only |

Installing everything is about **2.5G–3G**; install only the languages you need. All environments persist in the mounted `data/cache` and survive container rebuilds.

**Each target installs independently, with its own environment variables**: the install function first checks whether the tool is already installed (skips download if so), then writes that tool's **environment variables into its own `env.sh`** under its install directory (e.g. `cache/go/env.sh`, persisted with the cache), and appends a `source` line for these `env.sh` files to `~/.profile` (skips if already written, no duplicate accumulation). After deleting and rebuilding the container and re-mounting the cache, re-running install re-imports and reuses everything.

**Script structure**: the repo has a single script file `install.sh` with two kinds of functions:
- `install.sh setup-bash-wrap` (**called once by Dockerfile at image build**, as root): saves the real bash as `bash.real` and wraps `/usr/bin/bash` so it `source`s each tool's `env.sh` on startup. This opencode version runs commands via `/bin/bash` without `-l` (empirically it does not read `~/.profile`/`/etc/profile.d`), so this wrapper lets the opencode process auto-load installed tool environment variables.
- `install.sh go/rust/...` (**run on demand at runtime**): install tool + write tool-dir `env.sh` + write `~/.profile` import lines.

**opencode process auto-loads the environment (no restart needed)**: via the bash wrapper above, the bash that opencode uses to run commands is exactly this wrapped bash, which `source`s each tool's `env.sh`. So after installation, **go / cargo / tsc etc. are immediately usable inside the opencode process** (when the agent compiles/runs code) — no `docker restart`, no manual `source` in the container.

**Persistence & rebuild recovery**:

- Environments live in the mounted `data/cache`; deleting/rebuilding the container only requires re-mounting the same directory to recover — the script **skips downloading already-installed tools** (unless `--update`), only replenishing env vars.
- After re-mounting, **no reinstall is needed to use them**: the bash wrapper sources tool `env.sh` on every start, so just `docker restart <container>`; or re-run `install.sh <target>` (already-installed skips download, only ensures vars are written).
- Verified loop: ① start → install java/bun/scala/kotlin/lua/php → `java`/`bun`/`scala-cli`/`kotlin`/`lua`/`php` all usable inside the opencode process; ② delete container → restart (re-mount cache) → run script confirming **all skip download** → previous coding environments still work inside the opencode process.

## Usage

```bash
cd opencode
cp .env.sample .env       # fill in a strong OPENCODE_SERVER_PASSWORD
docker compose up -d
```

- Web / API: `http://<hostIP>:4096` (enter account + password)
- Remote access: from phone/Internet use Tailscale, open `http://<tailscale-ip>:4096` in a browser
- Config: `data/config/opencode.json` (template: `opencode.json.example`)
- AI platform accounts: API-key types go via `opencode.json` + env vars; OAuth types via `/connect` or `opencode auth login`, credentials persisted in `data/share/auth.json`

## AI platform accounts

OpenCode supports two connection methods, chosen by platform type:

### 1. API Key type (Anthropic / OpenAI / DeepSeek / Gemini / Ollama, etc.)

All provider keys are **handled in the config file `data/config/opencode.json`** (template: `opencode.json.example`, referenced via `{env:XXX}`) and supplied by each deployment's runtime (host shell / orchestrator / secrets manager). They are **not written into `.env`, not committed to the repo, and not passed through by docker-compose**.

| Provider | Access | baseURL | Env var referenced in config |
|----------|--------|---------|----------|
| `anthropic` (Claude) | official native (Models.dev) | — (default `https://api.anthropic.com/v1`) | `ANTHROPIC_API_KEY` |
| `openai` | official native (Models.dev) | `https://api.openai.com/v1` | `OPENAI_API_KEY` |
| `deepseek` | OpenAI-compatible (`@ai-sdk/openai-compatible`) | `https://api.deepseek.com/v1` | `DEEPSEEK_API_KEY` |
| `gemini` | OpenAI-compatible gateway (`@ai-sdk/openai-compatible`) | `https://generativelanguage.googleapis.com/v1beta/openai/` | `GEMINI_API_KEY` |
| `ollama` | local OpenAI-compatible (`@ai-sdk/openai-compatible`) | `http://host.docker.internal:11434/v1` | none (local) |
| `opencode` | opencode official provider (native) | — | `OPENCODE_API_KEY` (**free models need none**; Zen/Go paid models need it) |

**Notes on the opencode official provider key (important):**
- **Free models** (`opencode/*-free`, `opencode/big-pickle`, etc.) work out of the box, **no key needed**.
- **Zen / Go paid models** (e.g. `opencode/gpt-5.1-codex`) need an OpenCode API Key: register at `opencode.ai/auth` → create an API Key → inject `OPENCODE_API_KEY` into the runtime (e.g. host `export` or orchestrator secrets); the config already references it via `options.apiKey: "{env:OPENCODE_API_KEY}"`. You can also `docker compose exec opencode opencode auth login` and pick `OpenCode Zen`.

Note: **Ollama inside a Docker container must use `host.docker.internal` not `localhost`** to reach the host's Ollama service. After changing config run `docker compose restart opencode`.

### 2. OAuth type (Claude Pro/Max, ChatGPT Plus/Pro, etc. web accounts)

**No API key needed, no `.env` change needed.** After starting the container, use `opencode auth login` for interactive login; credentials are stored in `data/share/auth.json` and survive restart:

```bash
# 1) Make sure the container is running
docker compose up -d

# 2) Interactive login (TUI picks platform → OAuth → browser authorize)
docker compose exec -it opencode opencode auth login

# 3) List logged-in accounts
docker compose exec opencode opencode auth list
```

- The login flow opens a browser for authorization (container runs on host, browser callback is routed back to the container by the host); follow the prompts.
- If a platform's CLI only supports "manually enter API Key", also use `opencode auth login` → pick platform → Manually enter API Key.
- You can also do the same in the Web UI with the `/connect` command (type `/connect` in the chat box).
- To remove/replace credentials: run `opencode auth login` again and pick the same platform to overwrite.

> Note: OAuth credentials live in `data/share/auth.json`, which is runtime data (ignored by `.gitignore`), **do not commit it to the repo**.

## Official API usage (headless server)

Besides `opencode web` (Web UI + API on the same port), opencode officially provides **`opencode serve`**: a headless HTTP service exposing an OpenAPI 3.1 REST interface, callable by your own client / IDE plugin / script. This image defaults to `opencode web`, whose underlying layer also exposes the API, so the examples below apply to both.

- API port: `4096` (same as Web)
- OpenAPI docs: `http://<host>:4096/doc` (HTML/Swagger in browser, or `Accept: application/json` for JSON)
- Auth: once `OPENCODE_SERVER_PASSWORD` is set, HTTP uses Basic Auth (username defaults to `opencode`, changeable via `OPENCODE_SERVER_USERNAME`)

### curl examples

```bash
# Health check
curl -u opencode:$OPENCODE_SERVER_PASSWORD http://localhost:4096/global/health

# Create a session
curl -u opencode:$OPENCODE_SERVER_PASSWORD -X POST http://localhost:4096/session \
  -H "Content-Type: application/json" \
  -d '{"title": "demo"}'

# Send a message (specify provider/model, e.g. deepseek-v4-flash)
curl -u opencode:$OPENCODE_SERVER_PASSWORD -X POST \
  http://localhost:4096/session/<session-id>/message \
  -H "Content-Type: application/json" \
  -d '{"parts":[{"type":"text","text":"write a Go hello world"}],"model":{"providerID":"deepseek","modelID":"deepseek-v4-flash"}}'

# Live event stream (SSE, watch tool-call progress)
curl -N -u opencode:$OPENCODE_SERVER_PASSWORD http://localhost:4096/global/event
```

> Full endpoints see `http://<host>:4096/doc`. To call cross-origin from another frontend (e.g. a custom Web/App), start with `--cors <origin>` (the current `web` command does not expose this flag; use `opencode serve --cors ...` instead of the default command when needed).

## Environment variables (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENCODE_SERVER_USERNAME` | Login username | — |
| `OPENCODE_SERVER_PASSWORD` | Login password (empty = no auth) | — |
| `CARGO_BUILD_JOBS` | Rust parallel build jobs | `1` |
| `GOMAXPROCS` | Go parallelism | `2` |
| `MAKEFLAGS` | make parallelism | `-j2` |
| `MEM_LIMIT` / `CPU_LIMIT` | Container memory/CPU cap | `4g` / `2` |

## Notes

- `opencode web` does not support sub-path deployment (assets use root path); use root path + Tailscale directly.
- For a pure API / cross-origin frontend, swap `command` to `opencode serve --hostname 0.0.0.0 --port 4096 --cors <origin>`; the rest of the config stays the same.
- Cache is unified under `data/cache` and survives container rebuilds.
- `data/config/node_modules/` holds provider dependencies (AI SDK packages); on first use of a provider OpenCode auto-`npm install`s there, ignored by `.gitignore`.
- Go architecture is selected at build via `uname -m`; do not switch to `TARGETARCH`.
- At image build, `install.sh setup-bash-wrap` wraps `/usr/bin/bash` (sourcing each tool dir's `env.sh`); this is the image's only environment-loading mechanism. Tools themselves are not installed by default and are loaded on demand at runtime via `install.sh <target>` into `data/cache`.
