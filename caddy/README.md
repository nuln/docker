# Caddy

A custom Caddy image that compiles a small, curated plugin set via `xcaddy` on top of the official image, for reverse proxying, static sites, WebSocket proxying, UDP forwarding, and certificate automation.

## Image variants

| Dockerfile | Tags | Plugins |
|-----------|------|---------|
| `Dockerfile` | `:<version>`, `:latest` | lean set (4 plugins), the default |
| `Dockerfile.full` | `:<version>-full`, `:full` | lean set + webdav / exec / webhook |

`Dockerfile.base` was removed — the lean build already is the base.

## Built-in plugins (both variants)

| Plugin | Purpose |
|--------|---------|
| `caddy-l4` | L4 / UDP SNI forwarding (e.g. forward `udp/:443` to hysteria) |
| `caddy-dynamicdns` | Keeps DNS records in sync with the public IP (DDNS for dynamic-IP hosts) |
| `caddy-dns/cloudflare` | ACME DNS-01 challenge, cert requests via Cloudflare DNS (no 80 port needed, supports wildcards) |
| `nuln/caddy-plugins/alidns` | ACME DNS-01 via Alibaba Cloud — both 云解析 DNS (`alidns`) and 边缘安全加速 ESA (`esa`). Fork of `caddy-dns/alidns`, MIT © 2020 Yu Zhu |

## Extra plugins (`:full` only)

| Plugin | Purpose |
|--------|---------|
| `caddy-webdav` | WebDAV file server |
| `caddy-exec` | Run shell commands from a handler / config |
| `caddy-webhook` | Webhook receiver handler |

Switch with `CADDY_IMAGE` in `.env` (e.g. `ghcr.io/nuln/caddy:2.11.7-full`).

## Build

The image is built automatically by CI (`.github/workflows/caddy.yml`) for multiple architectures (amd64/arm64) and pushed to:

```
ghcr.io/nuln/caddy:<version>        # lean  (Dockerfile)          — e.g. 2.11.7
ghcr.io/nuln/caddy:<version>-full   # full  (Dockerfile.full)     — e.g. 2.11.7-full
ghcr.io/nuln/caddy:latest           # lean
ghcr.io/nuln/caddy:full             # full
```

`<version>` tracks whatever Caddy stable was when CI ran, so the numeric tag and
the binary inside always agree.

`CADDY_VERSION` defaults to `latest`, so a local build needs no arguments and picks up the current stable release. Pass it to pin a specific one:

```bash
# latest (default)
docker build -t ghcr.io/nuln/caddy:local caddy

# pinned
docker build --build-arg CADDY_VERSION=2.11.7 -t ghcr.io/nuln/caddy:2.11.7 caddy
docker build -f caddy/Dockerfile.full --build-arg CADDY_VERSION=2.11.7 -t ghcr.io/nuln/caddy:2.11.7-full caddy
```

CI resolves the latest release once and passes it in as a build-arg, so the published tag always matches what is inside the image. The Dockerfile's `latest` default means a plain `docker build` is **not** reproducible across days — pass `--build-arg` when you need to rebuild a specific tag.

`CADDY_VERSION` is re-declared inside the builder stage and handed to `xcaddy build`: an ARG declared before the first `FROM` is only in scope for `FROM` lines, so without the re-declaration the stage cannot see it and xcaddy falls back to its own `latest`. That mismatch is invisible — the image builds, it just contains a different Caddy than the base layer it was copied onto.

### Constraints

- `nuln/caddy-plugins/alidns` requires Caddy **≥ 2.11.7**. Go module version
  selection rejects an older one outright:
  `requires github.com/caddyserver/caddy/v2@v2.11.7, not v2.11.4`. `latest` is
  always new enough, but a pinned `CADDY_VERSION` below that floor fails at
  `go get` unless the plugin's `go.mod` is relaxed.
- The builder image is `caddy:builder`, which floats. That is deliberate: it
  tracks Go toolchain and xcaddy updates, and does not affect the Caddy version
  being compiled. Pinning it to `caddy:${CADDY_VERSION}-builder` is possible if
  a fully hermetic toolchain is ever needed.

## Usage

```bash
cd caddy
cp .env.sample .env
docker compose up -d
```

- Config: `Caddyfile` (committed, organized by domain/plugin, edit directly)
- Certs/data: `data/` (ACME auto-requests, must be persisted)
- Logs: `./logs/error.log`, `access.log` (JSON format, via the built-in `json` encoder)
- Static sites: `www/<domain>/`, default fallback `www/html/`
- Upstream dependencies: `hysteria:3443` (UDP forwarding), `xray:8444` (/ws reverse proxy)

## Ports

`80` (redirect) / `443` + `443/udp` (main entry + UDP forwarding) / `2053` (ws reverse proxy) / `8080` (redirect) / `8443` (proxy_protocol + TLS)

## Environment variables (.env)

| Variable | Description |
|----------|-------------|
| `CADDY_IMAGE` | Image tag to run, `ghcr.io/nuln/caddy:<version>` (lean) or `:<version>-full` |
| `CF_DNS_API_TOKEN` | Cloudflare DNS-01 verification token (Zone:DNS edit permission only). If empty, falls back to HTTP-01 (needs public 80 port reachable) |
| `ALIDNS_AK` / `ALIDNS_SK` | Optional Alibaba Cloud DNS credentials, used by the `conf/alidns.caddy` example |
| `MEM_LIMIT` / `CPU_LIMIT` | Container memory/CPU cap, default `512m` / `1` |

## Config structure (one file per plugin)

Config is split by plugin: **each `*.caddy` under `conf/` is a standalone minimal example** that runs on its own with `caddy run --config conf/xxx.caddy` (ships its own global block + minimal site). The production `Caddyfile` is a **self-contained** aggregate config that inlines the `layer4` global option and **does not import these snippets** (to avoid duplicate global-block conflicts).

```
caddy/
├── Caddyfile            # production aggregate config (self-contained, all global options + real sites)
├── conf/
│   ├── l4.json          # layer4 (L4/UDP forwarding, JSON format — the only JSON file)
│   ├── cloudflare.caddy # Cloudflare DNS-01 cert example (self-contained)
│   ├── alidns.caddy     # Alibaba Cloud DNS-01 cert example (self-contained)
│   ├── dynamicdns.caddy # caddy-dynamicdns example (self-contained, global dynamic_dns block)
│   └── logging.caddy    # structured JSON log example (self-contained, built-in json encoder)
└── ...
```

- **layer4 uses JSON** (`conf/l4.json`): L4 forwarding is a separate app, structured as `{"apps":{"layer4":{...}}}`. The production `Caddyfile` declares the equivalent config directly via a global `layer4 { }` block.
- **Everything else uses Caddyfile directives**; the production `Caddyfile` declares each global option (`layer4`, `acme_dns`, `dynamic_dns`, ...) in its global block.
- To change production config, edit `Caddyfile` directly; to verify a plugin's standalone usage, see the corresponding `conf/xxx.caddy` example.

## 动态 DNS（caddy-dynamicdns）

`dynamic_dns` 是一个全局选项，负责把本机公网 IP 自动同步到 DNS 记录，适合动态 IP 的家庭宽带 / VPS。

- `conf/dynamicdns.caddy` 是可独立运行的最小示例（`caddy run --config conf/dynamicdns.caddy`）。
- 生产 `Caddyfile` 里已预留注释掉的 `dynamic_dns { }` 块，填好 provider 凭据后取消注释即可生效。
- `provider` 需与镜像内置的 DNS provider 对应（`cloudflare` / `alidns`），凭据从环境变量注入。

## 推荐的额外插件

以下插件建议在后续版本中添加，按优先级排列：

| 优先级 | 插件 | 下载量 | 用途 |
|--------|------|--------|------|
| ⭐⭐⭐ | `github.com/corazawaf/coraza-caddy/v2` | 6.5K⬇ | Coraza WAF，集成 OWASP CRS 核心规则集，抵御 SQL 注入/XSS 等攻击 |
| ⭐⭐⭐ | `github.com/hslatman/caddy-crowdsec-bouncer` | 13K⬇ | CrowdSec 联动封禁，基于社区威胁情报自动阻断恶意 IP（支持 L4+L7） |
| ⭐⭐⭐ | `github.com/WeidiDeng/caddy-cloudflare-ip` | 13.5K⬇ | 获取 Cloudflare 真实访客 IP（如果网站通过 CF CDN 回源） |
| ⭐⭐ | `github.com/porech/caddy-maxmind-geolocation` | 12.5K⬇ | GeoIP 地理匹配，按国家/城市/ASN 进行访问控制 |
| ⭐⭐ | `github.com/darkweak/souin/plugins/caddy` | 23.5K⬇ | 企业级 HTTP 缓存，支持 Redis 等分布式后端 |
| ⭐⭐ | `github.com/caddyserver/replace-response` | 118K⬇ | 响应体内容替换/修改，可用于动态修改 HTML/JSON 响应 |
| ⭐⭐ | `github.com/mholt/caddy-ratelimit` | 20K⬇ | 限流，防刷/防爆破 |
| ⭐⭐ | `github.com/ggicci/caddy-jwt` | 3.7K⬇ | JWT 认证，适用于 API 鉴权（轻量替代 caddy-security） |
| ⭐⭐ | `github.com/ueffel/caddy-brotli` | 8.8K⬇ | Brotli 压缩，比 gzip 提升约 20% 压缩率 |
| ⭐ | `github.com/kirsch33/realip` | 6.4K⬇ | 从可信代理头提取真实客户端 IP |
| ⭐ | `github.com/lucaslorentz/caddy-docker-proxy/v2` | 2.1K⬇ | Docker 自动配置，label 驱动（适合 Docker Swarm 环境） |

### 按场景推荐组合

**安全增强**：coraza-waf + crowdsec-bouncer + maxmind-geolocation  
**性能优化**：souin-cache + brotli + replace-response  
**Cloudflare 用户**：cloudflare-ip + caddy-dns/cloudflare + caddy-dynamicdns

## 插件文档更新

`plugins.md` 包含 Caddy 插件市场全部 312 个插件的完整信息，可通过脚本定时更新：

```bash
# 手动更新
python3 scripts/update-plugins.py

# 更新并提交
python3 scripts/update-plugins.py --commit

# 更新、提交并推送
python3 scripts/update-plugins.py --push
```

建议在 CI 中定期运行（例如每周一次）或在需要查阅最新插件时手动运行。

## Notes

- Config uses `Caddyfile` (`caddy run --config /etc/caddy/Caddyfile`). layer4 uses the global `layer4 { }` block; the HTTP part uses Caddyfile directives only, no JSON needed.
- Only modules baked into the image are usable — a directive from a plugin that is not compiled in fails at config load with `unrecognized directive`. Keep the plugin list in `Dockerfile` / `Dockerfile.full` and the config in sync.
- Removed plugins (previously in the image): `caddy-supervisor`, `caddy-ratelimit`, `cache-handler`, `transform-encoder`, `caddy-events-exec`, `caddy-git`, `caddy-security`, `caddy-cgi`, `caddy-wol`, `caddy-hmac`. Use the built-in `json` log encoder instead of `transform-encoder`.
- Low-power defaults: `mem_limit 512m / cpus 1`.
