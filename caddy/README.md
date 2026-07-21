# Caddy

A custom Caddy image that compiles in several plugins via `xcaddy` on top of the official image, for reverse proxying, static sites, WebSocket proxying, UDP forwarding, and certificate automation.

## Built-in plugins

| Plugin | Purpose |
|--------|---------|
| `caddy-l4` | L4 / UDP SNI forwarding (e.g. forward `udp/:443` to hysteria) |
| `rate-limit` | Request rate limiting, anti-bruteforce / anti-spam (a moat for low-power machines) |
| `cache-handler` | Reverse-proxy / static-asset caching, speed-up |
| `transform-encoder` | Structured (JSON) log output |
| `caddy-dns/cloudflare` | ACME DNS-01 challenge, cert requests via Cloudflare DNS (no 80 port needed, supports wildcards) |
| `greenpau/caddy-security` | OIDC login (e.g. PocketID), path-level auth |

## Build

The image is built automatically by CI (`.github/workflows/caddy.yml`) for multiple architectures (amd64/arm64) and pushed to:

```
ghcr.io/nuln/caddy:latest
ghcr.io/nuln/caddy:<version>
```

The version is taken from the latest official Caddy release. To build locally:

```bash
docker build -t ghcr.io/nuln/caddy:latest caddy
```

## Usage

```bash
cd caddy
cp .env.sample .env
docker compose up -d
```

- Config: `Caddyfile` (committed, organized by domain/plugin, edit directly)
- Certs/data: `data/` (ACME auto-requests, must be persisted)
- Logs: `./logs/error.log`, `access.log` (JSON format, via transform-encoder)
- Static sites: `www/<domain>/`, default fallback `www/html/`
- Upstream dependencies: `hysteria:3443` (UDP forwarding), `xray:8444` (/ws reverse proxy)

## Ports

`80` (redirect) / `443` + `443/udp` (main entry + UDP forwarding) / `2053` (ws reverse proxy) / `8080` (redirect) / `8443` (proxy_protocol + TLS)

## Environment variables (.env)

| Variable | Description |
|----------|-------------|
| `CF_DNS_API_TOKEN` | Cloudflare DNS-01 verification token (Zone:DNS edit permission only). If empty, falls back to HTTP-01 (needs public 80 port reachable) |
| `MEM_LIMIT` / `CPU_LIMIT` | Container memory/CPU cap, default `512m` / `1` |

## Config structure (one file per plugin)

Config is split by plugin: **each `*.caddy` under `conf/` is a standalone minimal example** that runs on its own with `caddy run --config conf/xxx.caddy` (ships its own global block + minimal site). The production `Caddyfile` is a **self-contained** aggregate config that inlines all `order`/`security`/`layer4` global options and **does not import these snippets** (to avoid duplicate global-block conflicts).

```
caddy/
├── Caddyfile            # production aggregate config (self-contained, all global options + real sites)
├── conf/
│   ├── l4.json          # layer4 (L4/UDP forwarding, JSON format — the only JSON file)
│   ├── rate-limit.caddy # rate-limit example (self-contained, runnable via caddy run --config conf/rate-limit.caddy)
│   ├── cache.caddy      # cache example (self-contained)
│   ├── logging.caddy    # structured JSON log example (self-contained)
│   ├── cloudflare.caddy # Cloudflare DNS-01 cert example (self-contained)
│   └── oidc.caddy       # caddy-security + PocketID OIDC example (self-contained, with subpath protection)
└── ...
```

- **layer4 uses JSON** (`conf/l4.json`): L4 forwarding is a separate app, structured as `{"apps":{"layer4":{...}}}`. The production `Caddyfile` declares the equivalent config directly via a global `layer4 { }` block.
- **All other plugins use Caddyfile directives**; the production `Caddyfile` declares each directive's `order` and `security { }` in its global block, then uses `rate_limit` / `cache` / `authenticate` etc. directly in site blocks.
- To change production config, edit `Caddyfile` directly; to verify a plugin's standalone usage, see the corresponding `conf/xxx.caddy` example.

## OIDC login (PocketID via caddy-security)

The image compiles the `caddy-security` plugin and can connect to PocketID (or any OIDC provider) for unified login directly.

### How it works

- The global `security { }` block defines an **authentication portal myportal** (OIDC backend pointing to PocketID) + an **authorization policy pocketid**.
- Use `authenticate with myportal` in a site block to enable auth on specific paths; unauthenticated users are redirected to PocketID, and return with a JWT cookie after login.

### Protect only a `/xxx` subpath of a domain

The `example.com` site in `Caddyfile` demonstrates: only `/protected/*` requires login, other paths (`/`, `/static`) pass through directly.

```caddyfile
example.com, www.example.com {
    @protected path /protected/*
    handle @protected {
        authenticate with myportal
        file_server /var/www/example.com
    }
    handle {
        file_server /var/www/example.com
    }
}
```

To protect more subpaths, copy the `@protected` matcher and change `path`. For whole-site protection, drop the matcher and use `authenticate with myportal` directly.

### Config steps

1. Start a PocketID container, create an OIDC Client, callback:
   `https://<your caddy domain>/caddy-security/oauth2/pocketid/authorization-code-callback`
2. In `.env` fill: `POCKETID_CLIENT_ID`, `POCKETID_CLIENT_SECRET` (generate `JWT_SECRET` with `openssl rand -base64 32`).
3. Change `Caddyfile`'s `base_auth_url` / `metadata_url` to your PocketID address, `cookie domain` to your main domain.
4. `docker compose up -d`, visiting a protected path redirects to PocketID login.

## 推荐的额外插件

以下插件建议在后续版本中添加，按优先级排列：

| 优先级 | 插件 | 下载量 | 用途 |
|--------|------|--------|------|
| ⭐⭐⭐ | `github.com/corazawaf/coraza-caddy/v2` | 6.5K⬇ | Coraza WAF，集成 OWASP CRS 核心规则集，抵御 SQL 注入/XSS 等攻击 |
| ⭐⭐⭐ | `github.com/hslatman/caddy-crowdsec-bouncer` | 13K⬇ | CrowdSec 联动封禁，基于社区威胁情报自动阻断恶意 IP（支持 L4+L7） |
| ⭐⭐⭐ | `github.com/WeidiDeng/caddy-cloudflare-ip` | 13.5K⬇ | 获取 Cloudflare 真实访客 IP（如果网站通过 CF CDN 回源） |
| ⭐⭐ | `github.com/porech/caddy-maxmind-geolocation` | 12.5K⬇ | GeoIP 地理匹配，按国家/城市/ASN 进行访问控制 |
| ⭐⭐ | `github.com/darkweak/souin/plugins/caddy` | 23.5K⬇ | 企业级 HTTP 缓存，支持 Redis 等分布式后端，替代 cache-handler |
| ⭐⭐ | `github.com/caddyserver/replace-response` | 118K⬇ | 响应体内容替换/修改，可用于动态修改 HTML/JSON 响应 |
| ⭐⭐ | `github.com/ueffel/caddy-brotli` | 8.8K⬇ | Brotli 压缩，比 gzip 提升约 20% 压缩率 |
| ⭐⭐ | `github.com/ggicci/caddy-jwt` | 3.7K⬇ | JWT 认证，适用于 API 鉴权（轻量替代 caddy-security） |
| ⭐ | `github.com/kirsch33/realip` | 6.4K⬇ | 从可信代理头提取真实客户端 IP |
| ⭐ | `github.com/lucaslorentz/caddy-docker-proxy/v2` | 2.1K⬇ | Docker 自动配置，label 驱动（适合 Docker Swarm 环境） |
| ⭐ | `github.com/mholt/caddy-webdav` | 40K⬇ | WebDAV 文件服务器 |

### 按场景推荐组合

**安全增强**：coraza-waf + crowdsec-bouncer + maxmind-geolocation  
**性能优化**：souin-cache + brotli + replace-response  
**Cloudflare 用户**：cloudflare-ip + caddy-dns/cloudflare

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
- Rate limiting is enabled in each site's `handle` (default 100 requests/IP/min, see `rate_limit` in `Caddyfile`).
- Low-power defaults: `mem_limit 512m / cpus 1`.
