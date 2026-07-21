# Caddy 插件完全手册

> 数据来源: https://caddyserver.com/api/packages
> 总插件数: 312

本文档列出了 Caddy 官方插件市场所有可用插件的完整列表，按功能分类整理。

---

## 目录

- [安全认证 (Security/Auth)](#01-security_安全认证-securityauth)
- [DNS 提供商 (DNS Providers)](#02-dns_dns-提供商-dns-providers)
- [Layer4 TCP/UDP 代理](#03-l4_layer4-tcpudp-代理)
- [Layer7 反向代理增强](#04-proxy_layer7-反向代理增强)
- [缓存 (Cache)](#05-cache_缓存-cache)
- [存储后端 (Storage)](#06-storage_存储后端-storage)
- [响应处理/过滤 (Response Transform)](#07-transform_响应处理过滤-response-transform)
- [日志与监控 (Logging & Monitoring)](#08-logging_日志与监控-logging-&-monitoring)
- [速率限制 (Rate Limit)](#09-ratelimit_速率限制-rate-limit)
- [GeoIP/地理位置 (Geo Location)](#10-geoip_geoip地理位置-geo-location)
- [IP 管理 (IP Sources & Real IP)](#11-ip_ip-管理-ip-sources-&-real-ip)
- [实时通信 (Realtime)](#12-realtime_实时通信-realtime)
- [应用托管 (App Hosting)](#13-apphost_应用托管-app-hosting)
- [压缩 (Compression)](#14-compress_压缩-compression)
- [TLS/证书 (TLS & Certificates)](#15-tls_tls证书-tls-&-certificates)
- [Webhook 与事件 (Webhook & Events)](#16-webhook_webhook-与事件-webhook-&-events)
- [命令行执行 (Execute)](#17-exec_命令行执行-execute)
- [Git 集成 (Git Integration)](#18-git_git-集成-git-integration)
- [数据库 (Database)](#19-db_数据库-database)
- [媒体处理 (Media Processing)](#22-media_媒体处理-media-processing)
- [配置适配器与格式 (Config & Adapters)](#23-config_配置适配器与格式-config-&-adapters)
- [实用工具 (Utilities)](#24-util_实用工具-utilities)
- [其他 (Other)](#99-other_其他-other)

_最后更新: 2026-07-20_

## 1. 安全认证 (Security/Auth)

> 共 32 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 1574639⬇ | `github.com/greenpau/caddy-security` | `http.authentication.providers.authorizer, http.handlers.authenticator, security` | http.authentication.providers.authorizer authorizes access to endpoints based on the presense and content of JWT token. |
| 2 | 6534⬇ | `github.com/corazawaf/coraza-caddy/v2` | `http.handlers.waf` | http.handlers.waf is a Web Application Firewall implementation for Caddy. |
| 3 | 3737⬇ | `github.com/ggicci/caddy-jwt` | `http.authentication.providers.jwt` | http.authentication.providers.jwt facilitates JWT (JSON Web Token) authentication. |
| 4 | 1858⬇ | `github.com/firecow/caddy-forward-auth` | `http.handlers.forward_auth` |  |
| 5 | 1746⬇ | `github.com/casbin/caddy-authz/v2` | `http.handlers.authz` |  |
| 6 | 1366⬇ | `github.com/HeavenVolkoff/caddy-authelia/plugin` | `http.handlers.authelia` | http.handlers.authelia implements a plugin for securing routes with authentication |
| 7 | 1083⬇ | `github.com/kadeessh/kadeessh` | `ssh, ssh.actor_matchers.critical_option, ssh.actor_matchers.extension, ...` | ssh is the app providing ssh services |
| 8 | 936⬇ | `github.com/ueffel/caddy-basic-auth-filter` | `caddy.logging.encoders.filter.basic_auth_user` |  |
| 9 | 810⬇ | `github.com/Javex/caddy-fail2ban` | `http.matchers.fail2ban` | http.matchers.fail2ban implements an HTTP handler that checks a specified file for banned IPs and matches if they are found |
| 10 | 472⬇ | `go.akpain.net/caddy-tailscale-auth` | `` |  |
| 11 | 312⬇ | `github.com/enum-gg/caddy-discord` | `http.authentication.providers.discord, http.handlers.discord` | http.authentication.providers.discord allows you to authenticate caddy routes from a Discord User Identity.  e.g. Accessing /really-cool-people requires user to have {Role} within {Guild}  Discord's O |
| 12 | 270⬇ | `github.com/bploetz/caddy-oauth2-token-introspection` | `http.handlers.oauth2_token_introspection` | http.handlers.oauth2_token_introspection is a Caddy http.handlers Module for authorizing requests via OAuth2 Token Introspection |
| 13 | 233⬇ | `github.com/gr33nbl00d/caddy-revocation-validator` | `tls.client_auth.revocation` |  |
| 14 | 224⬇ | `github.com/steffenbusch/caddy-basicauth-totp` | `http.handlers.basicauth2fa, http.handlers.basicauthtotp` | http.handlers.basicauth2fa is a Caddy module that enhances Caddy's `basic_auth` directive by adding Time-based One-Time Password (TOTP) two-factor authentication (2FA). This module supplements `basic_ |
| 15 | 200⬇ | `github.com/Wafris/wafris-caddy` | `http.handlers.wafris` | Wafris, a free, open source WAF (web application firewall) |
| 16 | 154⬇ | `github.com/BraveRoy/caddy-waf` | `http.handlers.waf` |  |
| 17 | 92⬇ | `github.com/steffenbusch/caddy-postauth-2fa` | `http.handlers.postauth2fa` | http.handlers.postauth2fa is a Caddy HTTP handler module that adds TOTP-based two-factor authentication (2FA) after a primary authentication handler (such as basic_auth). It enforces an additional TOT |
| 18 | 83⬇ | `github.com/steffenbusch/caddy-jwt-issuer` | `http.handlers.jwt_issuer` | http.handlers.jwt_issuer is a Caddy module that issues JSON Web Tokens (JWT) after username and password authentication. It is intended to generate JWTs that are checked with https://github.com/ggicci |
| 19 | 73⬇ | `github.com/exante/caddy-tls-san-dns` | `tls.client_auth.san_dns, tls.client_auth.verifier.san_dns` |  |
| 20 | 63⬇ | `github.com/anujc4/caddy-geoblock` | `http.handlers.geoblock, http.matchers.geoblock` | http.handlers.geoblock implements geolocation-based request blocking for Caddy.  It looks up the client's IP address in MaxMind databases and blocks or allows requests based on geographic and network |
| 21 | 52⬇ | `github.com/chris-swift-dev/caddy-fail2ban` | `http.matchers.fail2ban` | http.matchers.fail2ban implements an HTTP handler that checks a specified file for banned IPs and matches if they are found |
| 22 | 31⬇ | `github.com/relvacode/caddy-oidc` | `http.handlers.oidc, http.matchers.anonymous, http.matchers.auth_method, ...` | http.handlers.oidc is a middleware that authenticates and authorizes requests based on configured rules. It's associated with a separately configured OIDC provider by name. |
| 23 | 21⬇ | `github.com/thestaticturtle/caddy-client-tls-ldap-validator` | `tls.client_auth.verifier.ldap_validator` |  |
| 24 | 19⬇ | `github.com/mkalus/caddy_block_aws` | `http.handlers.blockaws` |  |
| 25 | 19⬇ | `github.com/z3ntl3/caddyguard` | `http.handlers.guard` | http.handlers.guard is an elegant IPQS plugin for Caddy. |
| 26 | 18⬇ | `github.com/W0n9/caddy_waf_t1k` | `http.handlers.waf_chaitin` | http.handlers.waf_chaitin implements an HTTP handler for WAF. |
| 27 | 14⬇ | `github.com/xupefei/caddy-simple-password` | `http.handlers.simple_password` | http.handlers.simple_password is a Caddy HTTP handler module that adds simple password authentication with cookie-based session persistence. It protects routes with a single shared password. Sessions |
| 28 | 3⬇ | `github.com/jerryhan77/caddy-ldap-basic-auth` | `http.handlers.ldap_basic_auth` |  |
| 29 | 3⬇ | `go.hackfix.me/caddy-paseto` | `http.authentication.providers.paseto` | http.authentication.providers.paseto implements PASETO authentication. |
| 30 | 2⬇ | `github.com/sebdroid/caddy-introspect` | `http.authentication.providers.token_introspect` | http.authentication.providers.token_introspect is an HTTP authentication provider that checks bearer tokens for revocation by probing their issuer. |
| 31 | 0⬇ | `github.com/itstomsh/caddy-geojs-blocker` | `http.handlers.geojs_block` | http.handlers.geojs_block is a Caddy HTTP handler that filters requests based on GeoJS country lookup. It enforces an allowlist or blocklist and maintains cache, counters, and a debug endpoint. |
| 32 | 0⬇ | `github.com/pblop/caddy-tls-fnmt` | `tls.client_auth.verifier.fnmt` |  |

## 2. DNS 提供商 (DNS Providers)

> 共 75 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 1554073⬇ | `github.com/caddy-dns/route53` | `dns.providers.route53` | dns.providers.route53 wraps the provider implementation as a Caddy module. |
| 2 | 405593⬇ | `github.com/caddy-dns/cloudflare` | `dns.providers.cloudflare` | dns.providers.cloudflare wraps the provider implementation as a Caddy module. |
| 3 | 43887⬇ | `github.com/caddy-dns/duckdns` | `dns.providers.duckdns` | dns.providers.duckdns wraps the provider implementation as a Caddy module. |
| 4 | 14244⬇ | `github.com/caddy-dns/rfc2136` | `dns.providers.rfc2136` |  |
| 5 | 12863⬇ | `github.com/caddy-dns/digitalocean` | `dns.providers.digitalocean` | dns.providers.digitalocean wraps the provider implementation as a Caddy module. |
| 6 | 11480⬇ | `github.com/caddy-dns/alidns` | `dns.providers.alidns` | dns.providers.alidns wraps the provider implementation as a Caddy module. |
| 7 | 11170⬇ | `github.com/caddy-dns/dnspod` | `dns.providers.dnspod` | dns.providers.dnspod wraps the provider implementation as a Caddy module. |
| 8 | 9363⬇ | `github.com/caddy-dns/hetzner` | `dns.providers.hetzner` | dns.providers.hetzner wraps the provider implementation as a Caddy module. |
| 9 | 8370⬇ | `github.com/caddy-dns/porkbun` | `dns.providers.porkbun` | dns.providers.porkbun lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 10 | 6075⬇ | `github.com/caddy-dns/godaddy` | `dns.providers.godaddy` | dns.providers.godaddy wraps the provider implementation as a Caddy module. |
| 11 | 5333⬇ | `github.com/caddy-dns/ovh` | `dns.providers.ovh` | dns.providers.ovh wraps the provider implementation as a Caddy module. |
| 12 | 4156⬇ | `github.com/caddy-dns/googleclouddns` | `dns.providers.googleclouddns` | dns.providers.googleclouddns lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 13 | 3675⬇ | `github.com/caddy-dns/azure` | `dns.providers.azure` | dns.providers.azure wraps the provider implementation as a Caddy module. |
| 14 | 3657⬇ | `github.com/caddy-dns/desec` | `dns.providers.desec` | dns.providers.desec lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 15 | 3281⬇ | `github.com/caddy-dns/vultr` | `dns.providers.vultr` | dns.providers.vultr wraps the provider implementation as a Caddy module. |
| 16 | 2897⬇ | `github.com/caddy-dns/acmedns` | `dns.providers.acmedns` | dns.providers.acmedns lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 17 | 2655⬇ | `github.com/caddy-dns/namecheap` | `dns.providers.namecheap` | dns.providers.namecheap wraps the provider implementation as a Caddy module. |
| 18 | 2477⬇ | `github.com/caddy-dns/dynu` | `dns.providers.dynu` | dns.providers.dynu lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 19 | 2427⬇ | `github.com/caddy-dns/netcup` | `dns.providers.netcup` | dns.providers.netcup lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 20 | 2250⬇ | `github.com/caddy-dns/bunny` | `dns.providers.bunny` | dns.providers.bunny lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 21 | 2035⬇ | `github.com/caddy-dns/powerdns` | `dns.providers.powerdns` | dns.providers.powerdns wraps the provider implementation as a Caddy module. |
| 22 | 1692⬇ | `github.com/caddy-dns/inwx` | `dns.providers.inwx` | dns.providers.inwx lets Caddy read and manipulate DNS records hosted by INWX. |
| 23 | 1680⬇ | `github.com/caddy-dns/tencentcloud` | `dns.providers.tencentcloud` | dns.providers.tencentcloud wraps the provider implementation as a Caddy module. |
| 24 | 1679⬇ | `github.com/caddy-dns/ionos` | `dns.providers.ionos` | dns.providers.ionos wraps the provider implementation as a Caddy module. |
| 25 | 1570⬇ | `github.com/caddy-dns/infomaniak` | `dns.providers.infomaniak` | dns.providers.infomaniak lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 26 | 1469⬇ | `github.com/caddy-dns/gandi` | `dns.providers.gandi` | dns.providers.gandi wraps the provider implementation as a Caddy module. |
| 27 | 1294⬇ | `github.com/tosie/caddy-dns-linode` | `dns.providers.linode` | dns.providers.linode wraps the provider implementation as a Caddy module. |
| 28 | 839⬇ | `github.com/caddy-dns/lego-deprecated` | `dns.providers.lego_deprecated` | dns.providers.lego_deprecated is a shim module that allows any and all of the DNS providers in go-acme/lego to be used with Caddy. They must be configured via environment variables, they do not suppor |
| 29 | 834⬇ | `github.com/caddy-dns/netlify` | `dns.providers.netlify` | dns.providers.netlify wraps the provider implementation as a Caddy module. |
| 30 | 799⬇ | `github.com/caddy-dns/google-domains` | `dns.providers.google_domains` | dns.providers.google_domains lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 31 | 796⬇ | `github.com/caddy-dns/linode` | `dns.providers.linode` | dns.providers.linode lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 32 | 682⬇ | `github.com/caddy-dns/openstack-designate` | `dns.providers.openstack-designate` | dns.providers.openstack-designate wraps the provider implementation as a Caddy module. |
| 33 | 595⬇ | `github.com/caddy-dns/namedotcom` | `dns.providers.namedotcom` | dns.providers.namedotcom wraps the provider implementation as a Caddy module. |
| 34 | 525⬇ | `github.com/fvbommel/caddy-dns-ip-range` | `http.ip_sources.dns` | http.ip_sources.dns provides a range of IP addresses associated with a DNS name. Each range will only contain a single IP. |
| 35 | 512⬇ | `github.com/caddy-dns/scaleway` | `dns.providers.scaleway` | dns.providers.scaleway lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 36 | 504⬇ | `github.com/caddy-dns/dnsmadeeasy` | `dns.providers.dnsmadeeasy` | dns.providers.dnsmadeeasy wraps the provider implementation as a Caddy module. |
| 37 | 496⬇ | `github.com/caddy-dns/ddnss` | `dns.providers.ddnss` | dns.providers.ddnss lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 38 | 483⬇ | `github.com/caddy-dns/he` | `dns.providers.he, dns.providers.hetzner, dns.providers.hexonet` | dns.providers.he lets Caddy read and manipulate DNS records hosted by Hurricane Electric. |
| 39 | 476⬇ | `github.com/caddy-dns/mailinabox` | `dns.providers.mailinabox` | dns.providers.mailinabox lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 40 | 463⬇ | `github.com/caddy-dns/hexonet` | `dns.providers.hexonet` | dns.providers.hexonet wraps the provider implementation as a Caddy module. |
| 41 | 463⬇ | `github.com/caddy-dns/namesilo` | `dns.providers.namesilo` | dns.providers.namesilo lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 42 | 442⬇ | `github.com/caddy-dns/directadmin` | `dns.providers.directadmin` | dns.providers.directadmin lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 43 | 431⬇ | `github.com/caddy-dns/vercel` | `dns.providers.vercel` | dns.providers.vercel wraps the provider implementation as a Caddy module. |
| 44 | 427⬇ | `github.com/caddy-dns/njalla` | `dns.providers.njalla` | dns.providers.njalla lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 45 | 386⬇ | `github.com/caddy-dns/dnsimple` | `dns.providers.dnsimple` | dns.providers.dnsimple lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 46 | 313⬇ | `github.com/caddy-dns/cloudns` | `dns.providers.cloudns` | dns.providers.cloudns lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 47 | 258⬇ | `github.com/caddy-dns/metaname` | `dns.providers.metaname` | dns.providers.metaname wraps the provider implementation as a Caddy module. |
| 48 | 257⬇ | `github.com/xcaddyplugins/caddy-dns-godaddy` | `dns.providers.godaddy` | dns.providers.godaddy implements the libdns interfaces for GoDaddy DNS |
| 49 | 214⬇ | `github.com/caddy-dns/dnsexit` | `dns.providers.dnsexit` | dns.providers.dnsexit lets Caddy read and manipulate DNS records hosted by DNSExit. |
| 50 | 210⬇ | `github.com/caddy-dns/transip` | `dns.providers.transip` | dns.providers.transip lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 51 | 179⬇ | `github.com/caddy-dns/dreamhost` | `dns.providers.dreamhost` | dns.providers.dreamhost lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 52 | 167⬇ | `github.com/caddy-dns/dinahosting/v2` | `dns.providers.dinahosting` | dns.providers.dinahosting lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 53 | 147⬇ | `github.com/caddy-dns/spaceship` | `dns.providers.spaceship` | dns.providers.spaceship lets Caddy read and manipulate DNS records hosted by the Spaceship DNS provider. It adapts the libdns spaceship provider for use in Caddy. |
| 54 | 136⬇ | `github.com/liujed/caddy-dns01proxy` | `dns01proxy, http.handlers.dns01proxy` | A proxy server for ACME DNS-01 challenges. |
| 55 | 115⬇ | `github.com/caddy-dns/easydns` | `dns.providers.easydns` | dns.providers.easydns lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 56 | 92⬇ | `github.com/caddy-dns/huaweicloud` | `dns.providers.huaweicloud` | dns.providers.huaweicloud lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 57 | 92⬇ | `github.com/immosquare/caddy-dns-immosquare` | `dns.providers.immosquare` | dns.providers.immosquare lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 58 | 76⬇ | `github.com/caddy-dns/loopia` | `dns.providers.loopia` |  |
| 59 | 68⬇ | `github.com/caddy-dns/nanelo` | `dns.providers.nanelo` | dns.providers.nanelo lets Caddy read and manipulate DNS records hosted by Nanelo DNS. |
| 60 | 59⬇ | `github.com/caddy-dns/domainnameshop` | `dns.providers.domainnameshop` | dns.providers.domainnameshop lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 61 | 42⬇ | `github.com/caddy-dns/glesys` | `dns.providers.glesys` | dns.providers.glesys lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 62 | 37⬇ | `github.com/anthemaker/caddy-dns-fetcher` | `http.handlers.dnsfetcher, http.matchers.dnsfetcher` |  |
| 63 | 32⬇ | `github.com/caddy-dns/hosttech` | `dns.providers.hosttech` | dns.providers.hosttech lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 64 | 32⬇ | `github.com/caddy-dns/neoserv` | `dns.providers.neoserv` | dns.providers.neoserv lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 65 | 29⬇ | `github.com/spaaleks/caddy-dns-technitium` | `dns.providers.technitium` | dns.providers.technitium facilitates DNS record manipulation with Technitium DNS Server. |
| 66 | 23⬇ | `github.com/LeenHawk/edgeone` | `dns.providers.edgeone` | dns.providers.edgeone wraps the provider implementation as a Caddy module. |
| 67 | 13⬇ | `github.com/caddy-dns/civo` | `dns.providers.civo` | dns.providers.civo lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 68 | 10⬇ | `github.com/caddy-dns/katapult` | `dns.providers.katapult` | dns.providers.katapult lets Caddy read and manipulate DNS records hosted by Katapult. |
| 69 | 9⬇ | `github.com/caddy-dns/bluecat` | `dns.providers.bluecat` | dns.providers.bluecat lets Caddy read and manipulate DNS records hosted by Bluecat Address Manager. |
| 70 | 7⬇ | `github.com/caddy-dns/mythicbeasts` | `dns.providers.mythicbeasts` | dns.providers.mythicbeasts lets Caddy read and manipulate DNS records hosted by this DNS provider. |
| 71 | 7⬇ | `github.com/mietzen/caddy-dns-opnsense` | `dns.providers.opnsense` | dns.providers.opnsense lets Caddy read and manipulate DNS records hosted by OPNsense. |
| 72 | 4⬇ | `github.com/Enzonix-LLC/dns-caddy` | `dns.providers.enzonix` | dns.providers.enzonix implements the libdns interfaces for Enzonix. |
| 73 | 1⬇ | `github.com/caddy-dns/thelittlehost` | `dns.providers.thelittlehost` | dns.providers.thelittlehost lets Caddy read and manipulate DNS records hosted by The Little Host. |
| 74 | 0⬇ | `github.com/infogulch/caddy-zone-manager` | `dns_zone` | dns_zone is a Caddy app that keeps a set of DNS zones in sync with a declared desired state. |
| 75 | 0⬇ | `github.com/mietzen/caddy-dns-pfsense` | `dns.providers.pfsense` | dns.providers.pfsense facilitates DNS record manipulation with pfSense Unbound. |

## 3. Layer4 TCP/UDP 代理

> 共 3 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 31991⬇ | `github.com/mholt/caddy-l4` | `layer4, layer4.handlers.echo, layer4.handlers.proxy, ...` | layer4 is a Caddy app that operates closest to layer 4 of the OSI model. |
| 2 | 13082⬇ | `github.com/hslatman/caddy-crowdsec-bouncer` | `admin.api.crowdsec, crowdsec, http.handlers.appsec, ...` | admin.api.crowdsec is a module that serves CrowdSec endpoints to retrieve runtime information about the CrowdSec remediation component built into, and running as part of Caddy. |
| 3 | 195⬇ | `github.com/mohammed90/caddy-ngrok-listener` | `caddy.listeners.ngrok, caddy.listeners.ngrok.tunnels.http, caddy.listeners.ngrok.tunnels.labeled, ...` | caddy.listeners.ngrok is a `listener_wrapper` whose address is an ngrok-ingress address |

## 4. Layer7 反向代理增强

> 共 16 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 8595⬇ | `github.com/caddyserver/ntlm-transport` | `http.reverse_proxy.transport.http_ntlm` | http.reverse_proxy.transport.http_ntlm proxies HTTP with NTLM authentication. It basically wraps HTTPTransport so that it is compatible with NTLM's HTTP-hostile requirements. Specifically, it will use |
| 2 | 7111⬇ | `github.com/caddyserver/forwardproxy` | `` |  |
| 3 | 2469⬇ | `github.com/lindenlab/caddy-s3-proxy` | `http.handlers.s3proxy` | http.handlers.s3proxy implements a proxy to return, set, delete or browse objects from S3 |
| 4 | 2121⬇ | `github.com/lucaslorentz/caddy-docker-proxy/v2` | `` |  |
| 5 | 813⬇ | `github.com/caddy-dns/acmeproxy` | `dns.providers.acmeproxy` | dns.providers.acmeproxy wraps the provider implementation as a Caddy module. |
| 6 | 751⬇ | `github.com/invzhi/caddy-docker-upstreams` | `http.reverse_proxy.upstreams.docker` | http.reverse_proxy.upstreams.docker provides upstreams from the docker host. |
| 7 | 369⬇ | `github.com/Elegant996/scgi-transport` | `http.reverse_proxy.transport.scgi` | http.reverse_proxy.transport.scgi facilitates SCGI communication. |
| 8 | 309⬇ | `github.com/gbox-proxy/gbox` | `http.handlers.gbox` |  |
| 9 | 287⬇ | `github.com/BadAimWeeb/caddy-uwsgi-transport` | `http.reverse_proxy.transport.uwsgi` |  |
| 10 | 163⬇ | `github.com/mohammed90/caddy-aws-transport` | `http.reverse_proxy.transport.aws` | The AWS transport module injects the AWS V4 Signature for requests proxied to AWS services. |
| 11 | 89⬇ | `github.com/wxh06/caddy-uwsgi-transport` | `http.reverse_proxy.transport.uwsgi` |  |
| 12 | 85⬇ | `github.com/openziti-test-kitchen/ziti-caddy` | `http.reverse_proxy.transport.ziti` |  |
| 13 | 53⬇ | `github.com/deanchou/caddy_etcd` | `http.reverse_proxy.upstreams.etcd` | http.reverse_proxy.upstreams.etcd is a Caddy module that integrates etcd with reverse_proxy. |
| 14 | 2⬇ | `github.com/venkatkrishna07/caddy-mcp` | `admin.api.mcp, http.handlers.mcp_discovery, http.reverse_proxy.transport.mcp, ...` |  |
| 15 | 1⬇ | `github.com/venkatkrishna07/caddy-rift` | `admin.api.rift, http.reverse_proxy.transport.rift, rift` | admin.api.rift provides Caddy admin endpoints for rift management. |
| 16 | 0⬇ | `github.com/klzgrad/forwardproxy@naive` | `` |  |

## 5. 缓存 (Cache)

> 共 2 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 23459⬇ | `github.com/darkweak/souin/plugins/caddy` | `http.handlers.cache` | http.handlers.cache development repository of the cache handler, allows the user to set up an HTTP cache system, RFC-7234 compliant and supports the tag based cache purge, distributed and not-distribu |
| 2 | 6524⬇ | `github.com/caddyserver/cache-handler` | `http.handlers.cache` | http.handlers.cache allows the user to set up an HTTP cache system, RFC-7234 compliant and supports the tag based cache purge, distributed and not-distributed storage, key generation tweaking. |

## 6. 存储后端 (Storage)

> 共 17 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 8134⬇ | `github.com/gerolf-vent/caddy-vault-storage` | `caddy.storage.vault` | A highly available storage plugin that integrates with HashiCorp Vault. |
| 2 | 6355⬇ | `github.com/pteich/caddy-tlsconsul` | `caddy.storage.consul` | caddy.storage.consul allows to store certificates and other TLS resources in a shared cluster environment using Consul's key/value-store. It uses distributed locks to ensure consistency. |
| 3 | 6234⬇ | `github.com/ss098/certmagic-s3` | `caddy.storage.s3` |  |
| 4 | 2050⬇ | `github.com/pberkel/caddy-storage-redis` | `caddy.storage.redis` |  |
| 5 | 923⬇ | `github.com/techknowlogick/certmagic-s3` | `caddy.storage.s3` |  |
| 6 | 733⬇ | `github.com/mohammed90/caddy-storage-loader` | `caddy.config_loaders.storage` | caddy.config_loaders.storage is a dynamic configuration loader that reads the configuration from a Caddy storage. If the storage is not configured, the default storage is used, which may be the file-s |
| 7 | 695⬇ | `github.com/zhangjiayin/caddy-mysql-storage` | `caddy.storage.mysql` |  |
| 8 | 637⬇ | `github.com/sillygod/cdp-cache` | `admin.api.purge, caddy.logging.writers.influxlog, caddy.storage.consul, ...` | admin.api.purge is a module that provides the /purge endpoint as the admin api. |
| 9 | 445⬇ | `github.com/yroc92/postgres-storage` | `caddy.storage.postgres` |  |
| 10 | 327⬇ | `github.com/grafana/certmagic-gcs` | `caddy.storage.gcs` | caddy.storage.gcs implements a caddy storage backend for Google Cloud Storage. |
| 11 | 198⬇ | `github.com/mohammed90/caddy-encrypted-storage` | `caddy.storage.encrypted, caddy.storage.encrypted.key.age, caddy.storage.encrypted.key.gcp_kms, ...` | caddy.storage.encrypted is the impelementation of certmagic.Storage interface for Caddy with encryption/decryption layer using [SOPS](https://github.com/getsops/sops). The module accepts any Caddy sto |
| 12 | 116⬇ | `github.com/mentimeter/caddy-storage-cf-kv` | `caddy.storage.cloudflare_kv` | caddy.storage.cloudflare_kv implements a Caddy storage backend for Cloudflare KV |
| 13 | 93⬇ | `github.com/HeavyHorst/certmagic-nats` | `caddy.storage.nats` |  |
| 14 | 78⬇ | `github.com/sil-org/certmagic-storage-dynamodb/v3` | `caddy.storage.dynamodb` | caddy.storage.dynamodb implements certmagic.Storage to facilitate storage of certificates in DynamoDB for a clustered environment. Also implements certmagic.Locker to facilitate locking and unlocking |
| 15 | 19⬇ | `github.com/oltdaniel/caddy-storage-valkey` | `` |  |
| 16 | 7⬇ | `github.com/Enzonix-LLC/kv-caddy` | `caddy.storage.enzonix_kv` | caddy.storage.enzonix_kv implements a Caddy storage backend using the kv-database HTTP API. |
| 17 | 2⬇ | `github.com/swytchdb/swytch/caddy` | `caddy.storage.swytch` | caddy.storage.swytch is the Caddy storage module. Each Caddy reload produces a fresh instance of this struct from the parsed config; Provision is the only entry point allowed to start goroutines or bi |

## 7. 响应处理/过滤 (Response Transform)

> 共 2 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 117920⬇ | `github.com/caddyserver/replace-response` | `http.handlers.replace_response` | http.handlers.replace_response manipulates response bodies by performing substring or regex replacements. |
| 2 | 88333⬇ | `github.com/sjtug/caddy2-filter` | `http.handlers.filter` | http.handlers.filter implements an HTTP handler that writes the visitor's IP address to a file or stream. |

## 8. 日志与监控 (Logging & Monitoring)

> 共 7 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 65735⬇ | `github.com/caddyserver/transform-encoder` | `caddy.logging.encoders.formatted, caddy.logging.encoders.transform` | caddy.logging.encoders.transform allows the user to provide custom template for log prints. The encoder builds atop the json encoder, thus it follows its message structure. The placeholders are namesp |
| 2 | 27388⬇ | `github.com/greenpau/caddy-trace` | `http.handlers.trace` | http.handlers.trace is a middleware which displays the content of the request it handles. It helps troubleshooting web requests by exposing headers (e.g. cookies), URL parameters, etc. |
| 3 | 1047⬇ | `github.com/firecow/caddy-elastic-encoder` | `caddy.logging.encoders.elastic` |  |
| 4 | 180⬇ | `github.com/neodyme-labs/influx_log` | `caddy.logging.writers.influx_log` |  |
| 5 | 107⬇ | `github.com/ybizeul/caddy-logger-graphite` | `caddy.logging.writers.graphite` |  |
| 6 | 67⬇ | `github.com/jonaharagon/caddy-umami` | `http.handlers.umami` | http.handlers.umami is a Caddy module that sends visitor information to Umami's Events REST API endpoint. |
| 7 | 4⬇ | `github.com/jum/caddy-simpletrace` | `http.handlers.simpletrace` | http.handlers.simpletrace implements a lightweight trace context handler for Caddy |

## 9. 速率限制 (Rate Limit)

> 共 4 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 19967⬇ | `github.com/mholt/caddy-ratelimit` | `http.handlers.rate_limit` | http.handlers.rate_limit implements rate limiting functionality.  If a rate limit is exceeded, an HTTP error with status 429 will be returned. This error can be handled using the conventional error ha |
| 2 | 5897⬇ | `github.com/RussellLuo/caddy-ext/ratelimit` | `http.handlers.rate_limit` | http.handlers.rate_limit implements a handler for rate-limiting. |
| 3 | 440⬇ | `github.com/cubic3d/caddy-quantity-limiter` | `http.handlers.quantity_limiter` | http.handlers.quantity_limiter limits the number of successful requests for a token and allows the counter to be reset. |
| 4 | 1⬇ | `github.com/pberkel/caddy-tls-issuer-rate-limit` | `admin.api.rate_limit_tls_issuer, tls.issuance.rate_limit` | admin.api.rate_limit_tls_issuer registers admin API routes for inspecting and resetting shared rate limit pool state. It is loaded automatically by Caddy's admin server when this package is imported. |

## 10. GeoIP/地理位置 (Geo Location)

> 共 8 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 12492⬇ | `github.com/porech/caddy-maxmind-geolocation` | `http.matchers.maxmind_geolocation` |  |
| 2 | 2065⬇ | `github.com/shift72/caddy-geo-ip` | `http.handlers.geoip` | Allows to filter requests based on source IP country. |
| 3 | 1523⬇ | `github.com/zhangjiayin/caddy-geoip2` | `geoip2, http.handlers.geoip2` | http.handlers.geoip2 is an GeoIP2 server handler. it uses GeoIP2 Data to identify the location of the IP |
| 4 | 726⬇ | `github.com/circa10a/caddy-geofence` | `http.handlers.geofence` | http.handlers.geofence |
| 5 | 94⬇ | `git.gorbe.io/caddy/geoip` | `http.matchers.client_asn, http.matchers.client_country, http.matchers.geoip_asn, ...` | http.matchers.client_asn matches requests by the client_ip GeoIP ASN.  Caddyfile syntax:  	@asn-matcher client_asn "24940" 	respond @asn-matcher "Hetzner Online GmbH"  Logging:  	ERROR Failed to parse |
| 6 | 40⬇ | `github.com/ysicing/caddy2-geocn` | `http.matchers.geocity, http.matchers.geocn` |  |
| 7 | 34⬇ | `github.com/jpillora/ipfilter-caddy` | `http.matchers.ipfilter_geolocation` | http.matchers.ipfilter_geolocation allows filtering requests based on source IP country using jpillora/ipfilter. |
| 8 | 0⬇ | `github.com/ubiuser/caddy-geo-ops` | `geo_ops, http.handlers.geo_ops, http.matchers.geo_ops` | geo_ops is the geo_ops application module. |

## 11. IP 管理 (IP Sources & Real IP)

> 共 22 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 45891⬇ | `github.com/mastercactapus/caddy2-proxyprotocol` | `caddy.listeners.proxy_protocol` |  |
| 2 | 21112⬇ | `github.com/mholt/caddy-dynamicdns` | `dynamic_dns, dynamic_dns.ip_sources.simple_http, dynamic_dns.ip_sources.upnp` | dynamic_dns is a Caddy app that keeps your DNS records updated with the public IP address of your instance. |
| 3 | 13521⬇ | `github.com/WeidiDeng/caddy-cloudflare-ip` | `http.ip_sources.cloudflare` | http.ip_sources.cloudflare provides a range of IP address prefixes (CIDRs) retrieved from cloudflare. |
| 4 | 6393⬇ | `github.com/kirsch33/realip` | `http.handlers.realip` |  |
| 5 | 1677⬇ | `github.com/muety/caddy-remote-host` | `http.matchers.remote_host` | http.matchers.remote_host matches based on the remote IP of the connection. A host name can be specified, whose A and AAAA DNS records will be resolved to a corresponding IP for matching.  Note that I |
| 6 | 991⬇ | `github.com/tuzzmaniandevil/caddy-dynamic-clientip` | `http.matchers.dynamic_client_ip` |  |
| 7 | 791⬇ | `github.com/fvbommel/caddy-combine-ip-ranges` | `http.ip_sources.combine` | This module combines the prefixes returned by several other IP source plugins. |
| 8 | 669⬇ | `github.com/monobilisim/caddy-ip-list` | `http.ip_sources.list` | http.ip_sources.list provides a range of IP address prefixes (CIDRs) retrieved from url. |
| 9 | 406⬇ | `github.com/lanrat/caddy-dynamic-remoteip` | `http.matchers.dynamic_remote_ip` | http.matchers.dynamic_remote_ip matchers the requests by the remote IP address. The IP ranges are provided by modules to allow for dynamic ranges. |
| 10 | 266⬇ | `github.com/mietzen/caddy-dynamicdns-cmd-source` | `dynamic_dns.ip_sources.command` | dynamic_dns.ip_sources.command is an IP source that looks up the public IP addresses by executing a script or command from your filesystem.  The command must return the IP addresses comma spreaded in |
| 11 | 109⬇ | `github.com/digilolnet/caddy-bunny-ip` | `http.ip_sources.bunny` | http.ip_sources.bunny provides a range of IP address prefixes (CIDRs) retrieved from https://api.bunny.net/system/edgeserverlist and https://api.bunny.net/system/edgeserverlist/ipv6. |
| 12 | 109⬇ | `github.com/xcaddyplugins/caddy-trusted-cloudfront` | `http.ip_sources.cloudfront` |  |
| 13 | 94⬇ | `github.com/deanchou/caddy_ip_filter` | `http.handlers.ip_filter` |  |
| 14 | 25⬇ | `github.com/LeenHawk/caddy-edgeone-ip` | `http.ip_sources.edgeone` | http.ip_sources.edgeone provides a range of IP address prefixes (CIDRs) retrieved from EdgeOne. |
| 15 | 25⬇ | `github.com/teodorescuserban/caddy-ip-map` | `http.handlers.ipmap` | http.handlers.ipmap implements a middleware that maps inputs to outputs. Specifically, it compares a source value against the map inputs, and for one that matches, it applies the output values to each |
| 16 | 24⬇ | `github.com/xcaddyplugins/caddy-trusted-gcp-cloudcdn` | `http.ip_sources.gcp_cloudcdn` |  |
| 17 | 5⬇ | `github.com/deovero/caddy-ipset` | `http.matchers.ipset` | http.matchers.ipset matches the client_ip against Linux ipset lists using native netlink communication. This enables efficient filtering against large, dynamic sets of IPs and CIDR ranges.  Requiremen |
| 18 | 4⬇ | `github.com/alectrocute/caddy-bunnynet-ip` | `http.ip_sources.bunnynet` | http.ip_sources.bunnynet provides a range of IP address prefixes (CIDRs) retrieved from bunny.net. |
| 19 | 4⬇ | `github.com/anujc4/caddy-dynamic-ip-whitelist` | `admin.api.ipgate, http.handlers.ipgate_trigger, http.matchers.ipgate` | admin.api.ipgate provides admin API endpoints for managing the IP whitelist.  Endpoints:  	GET    /ipgate/whitelist      — list all whitelisted IPs 	DELETE /ipgate/whitelist      — remove all whitelis |
| 20 | 1⬇ | `github.com/azolfagharj/caddy_parspack_ip` | `http.ip_sources.parspack` | http.ip_sources.parspack retrieves ParsPack CDN IP ranges from their official sources |
| 21 | 1⬇ | `github.com/sarumaj/caddy-cdn-ranges/v2` | `http.ip_sources.cdn_ranges` | http.ip_sources.cdn_ranges is a Caddy IP source module that automatically fetches and maintains a list of trusted proxy IP ranges from CDN and cloud providers. It periodically updates the IP ranges an |
| 22 | 0⬇ | `github.com/zidsa/caddy-dynamic-host-matcher` | `http.matchers.dynamic_host` | http.matchers.dynamic_host implements a Caddy HTTP request matcher that dynamically loads host lists from HTTP endpoints. |

## 12. 实时通信 (Realtime)

> 共 3 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 205012⬇ | `github.com/dunglas/vulcain/caddy` | `http.handlers.vulcain` |  |
| 2 | 204109⬇ | `github.com/dunglas/mercure/caddy` | `http.handlers.mercure` | http.handlers.mercure implements a Mercure hub as a Caddy module. Mercure is a protocol allowing to push data updates to web browsers and other HTTP clients in a convenient, fast, reliable and battery |
| 3 | 2135⬇ | `github.com/mholt/caddy-grpc-web` | `http.handlers.grpc_web` | http.handlers.grpc_web is an HTTP handler that bridges gRPC-Web <--> gRPC requests. This module is EXPERIMENTAL and subject to change. |

## 13. 应用托管 (App Hosting)

> 共 7 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 40202⬇ | `github.com/mholt/caddy-webdav` | `http.handlers.webdav` | http.handlers.webdav implements an HTTP handler for responding to WebDAV clients. |
| 2 | 10927⬇ | `github.com/aksdb/caddy-cgi/v2` | `http.handlers.cgi` |  |
| 3 | 1912⬇ | `github.com/git001/caddyv2-upload` | `http.handlers.upload` | Middleware implements an HTTP handler that writes the uploaded file  to a file on the disk. |
| 4 | 1770⬇ | `github.com/dunglas/frankenphp/caddy` | `frankenphp, http.handlers.php` |  |
| 5 | 171⬇ | `willnorris.com/go/imageproxy/caddy` | `http.handlers.imageproxy` |  |
| 6 | 49⬇ | `github.com/mohammed90/caddy-pocketbase` | `admin.api.pocketbase, http.handlers.pocketbase, pocketbase` | admin.api.pocketbase is a module that serves PKI endpoints to retrieve information about the CAs being managed by Caddy. |
| 7 | 12⬇ | `github.com/okrc/caddy-uploadcert-tencentcloud` | `events.handlers.upload_cert_tencentcloud` |  |

## 14. 压缩 (Compression)

> 共 2 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 8767⬇ | `github.com/ueffel/caddy-brotli` | `http.encoders.br` | http.encoders.br can create brotli encoders. |
| 2 | 442⬇ | `github.com/dunglas/caddy-cbrotli` | `http.encoders.br` | http.encoders.br can create Brotli encoders. |

## 15. TLS/证书 (TLS & Certificates)

> 共 8 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 624⬇ | `github.com/ueffel/caddy-tls-format` | `caddy.logging.encoders.filter.tls_cipher, caddy.logging.encoders.filter.tls_version` | caddy.logging.encoders.filter.tls_cipher is Caddy log field filter that replaces the numeric TLS cipher_suite value with the string representation. |
| 2 | 416⬇ | `github.com/gonevo/caddy-tls-file-manager` | `tls.get_certificate.file` | tls.get_certificate.file can get a certificate via file. |
| 3 | 255⬇ | `github.com/quix-labs/caddy-pfx-certificates` | `tls.get_certificate.pfx` | tls.get_certificate.pfx allow user to set path to .pfx file to load TLS certificate |
| 4 | 94⬇ | `github.com/davidventura/caddy-certsrv` | `tls.issuance.certsrv` | tls.issuance.certsrv can request certificates from a Microsoft Active Directory Certificate Services instance |
| 5 | 3⬇ | `github.com/jonarihen/caddy-forticertsync` | `events.handlers.forticertsync` | events.handlers.forticertsync is a Caddy event handler that syncs certificates to FortiGate when Caddy obtains or renews a TLS certificate. |
| 6 | 3⬇ | `github.com/ohdearapp/caddy-get-certificate-cache` | `tls.get_certificate.cached_http` | tls.get_certificate.cached_http is a certmagic.Manager that fetches certificates from an HTTP endpoint (like Caddy's stock tls.get_certificate.http) and caches the result in memory, optionally persist |
| 7 | 0⬇ | `github.com/pberkel/caddy-tls-issuer-opportunistic` | `tls.issuance.opportunistic` | tls.issuance.opportunistic is a TLS certificate issuer (module ID: tls.issuance.opportunistic) that selects between two inner issuers at issuance time based on whether DNS-01 prerequisites are met. Wh |
| 8 | 0⬇ | `github.com/pberkel/caddy-tls-permission-policy` | `tls.permission.policy` |  |

## 16. Webhook 与事件 (Webhook & Events)

> 共 4 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 3949⬇ | `github.com/mholt/caddy-events-exec` | `events.handlers.exec` | events.handlers.exec implements an event handler that runs a command/program. By default, commands are run in the background so as to not block the Caddy goroutine. |
| 2 | 3373⬇ | `github.com/WingLim/caddy-webhook` | `http.handlers.webhook` | http.handlers.webhook is the module configuration. |
| 3 | 27⬇ | `github.com/kmpm/caddy-events-nats` | `events.handlers.nats` |  |
| 4 | 21⬇ | `github.com/Lenart12/caddy-events-store_cert` | `events.handlers.store_cert` | events.handlers.store_cert implements an event handler that stores the cert to a bucket. By default, the bucket is assumed to be a local directory. The handler can be configured to include or exclude |

## 17. 命令行执行 (Execute)

> 共 1 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 15532⬇ | `github.com/abiosoft/caddy-exec` | `exec, http.handlers.exec, http.matchers.exec_noop, ...` | exec is top level module that runs shell commands. |

## 18. Git 集成 (Git Integration)

> 共 2 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 2119⬇ | `github.com/greenpau/caddy-git` | `http.handlers.git` | http.handlers.git implements git repository manager. |
| 2 | 118⬇ | `github.com/mohammed90/caddy-git-fs` | `caddy.fs.git` | The `git` filesystem module uses a git repository as the virtual filesystem. |

## 19. 数据库 (Database)

> 共 3 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 149⬇ | `github.com/ncruces/go-sqlite3` | `` |  |
| 2 | 141⬇ | `github.com/sandstorm/caddy-nats-bridge` | `` |  |
| 3 | 17⬇ | `github.com/AnswerDotAI/caddy-sqlite-router` | `http.handlers.sqlite_router` |  |

## 22. 媒体处理 (Media Processing)

> 共 5 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 1557⬇ | `github.com/protomaps/go-pmtiles/caddy` | `http.handlers.pmtiles_proxy` |  |
| 2 | 617⬇ | `github.com/PixyBlue/caddy-pixbooster` | `http.handlers.pixbooster` |  |
| 3 | 473⬇ | `github.com/ueffel/caddy-imagefilter/v2/defaults` | `` |  |
| 4 | 428⬇ | `github.com/ueffel/caddy-imagefilter/defaults` | `` |  |
| 5 | 59⬇ | `github.com/quix-labs/caddy-image-processor` | `http.handlers.image_processor` | http.handlers.image_processor allow user to do image processing on the fly using libvips With simple queries parameters you can resize, convert, crop your served images |

## 23. 配置适配器与格式 (Config & Adapters)

> 共 9 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 5350⬇ | `github.com/caddyserver/nginx-adapter` | `` |  |
| 2 | 5125⬇ | `github.com/abiosoft/caddy-json-parse` | `http.handlers.json_parse` | http.handlers.json_parse implements an HTTP handler that parses json body as placeholders. |
| 3 | 3721⬇ | `github.com/abiosoft/caddy-yaml` | `` |  |
| 4 | 3272⬇ | `github.com/abiosoft/caddy-json-schema` | `` |  |
| 5 | 2380⬇ | `github.com/abiosoft/caddy-named-routes` | `` |  |
| 6 | 2307⬇ | `github.com/caddyserver/jsonc-adapter` | `` |  |
| 7 | 896⬇ | `github.com/francislavoie/caddy-hcl` | `` |  |
| 8 | 224⬇ | `github.com/RussellLuo/olaf/caddyconfig/adapter` | `` |  |
| 9 | 143⬇ | `github.com/zhangjiayin/caddy-mysql-adapter` | `` |  |

## 24. 实用工具 (Utilities)

> 共 40 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 7552⬇ | `github.com/imgk/caddy-trojan` | `admin.api.trojan, caddy.listeners.trojan, http.handlers.trojan, ...` | admin.api.trojan is ... |
| 2 | 4296⬇ | `github.com/baldinof/caddy-supervisor` | `supervisor` |  |
| 3 | 4018⬇ | `github.com/lolPants/caddy-requestid` | `http.handlers.request_id` | http.handlers.request_id implements an HTTP handler that writes a unique request ID to response headers. |
| 4 | 2795⬇ | `github.com/chukmunnlee/caddy-openapi` | `http.handlers.openapi` |  |
| 5 | 2630⬇ | `github.com/hairyhenderson/caddy-teapot-module` | `http.handlers.teapot` | http.handlers.teapot implements a static "418 I'm a teapot" response to all requests on the route |
| 6 | 2028⬇ | `github.com/techknowlogick/caddy-s3browser` | `` |  |
| 7 | 1677⬇ | `github.com/hslatman/caddy-openapi-validator` | `http.handlers.openapi_validator` | http.handlers.openapi_validator is used to validate OpenAPI requests and responses against an OpenAPI specification |
| 8 | 1551⬇ | `magnax.ca/caddy/gopkg` | `http.handlers.gopkg` | http.handlers.gopkg represents the GoPkg Caddy module. |
| 9 | 501⬇ | `github.com/dulli/caddy-wol` | `http.handlers.wake_on_lan` |  |
| 10 | 309⬇ | `github.com/argami/redir-dns` | `http.handlers.redir_dns` | http.handlers.redir_dns is a RedirDns for manipulating redirecting based on DNS TXT record. |
| 11 | 258⬇ | `github.com/anthemaker/caddy-signed-urls` | `http.matchers.signed` |  |
| 12 | 249⬇ | `github.com/devetek/caddyserver-minifier` | `http.handlers.minifier` |  |
| 13 | 239⬇ | `github.com/sjtug/cerberus` | `http.handlers.cerberus` |  |
| 14 | 224⬇ | `github.com/teodorescuserban/caddy-cookieflag` | `http.handlers.cookieflag` | http.handlers.cookieflag is a middleware that modifies the Secure and HttpOnly flags in Set-Cookie headers. |
| 15 | 185⬇ | `github.com/mpilhlt/caddy-conneg` | `http.matchers.conneg` | http.matchers.conneg matches requests by comparing results of a content negotiation process to a (list of) value(s).  Lists of media types, languages, charsets, and encodings to match the request agai |
| 16 | 173⬇ | `pkg.jsn.cam/caddy-defender` | `http.handlers.defender` | http.handlers.defender implements an HTTP middleware that enforces IP-based rules to protect your site from AIs/Scrapers. It allows blocking or manipulating requests based on client IP addresses using |
| 17 | 165⬇ | `github.com/ltgcgo/floaty` | `http.handlers.floaty` |  |
| 18 | 154⬇ | `github.com/mholt/caddy-hitcounter` | `http.handlers.templates.functions.hitCounter` | http.handlers.templates.functions.hitCounter implements a simple early-Web hit counter. |
| 19 | 150⬇ | `github.com/Odyssey346/ListenCaddy` | `http.handlers.listencaddy` |  |
| 20 | 115⬇ | `github.com/mohammed90/caddy-throttle-listener` | `caddy.listeners.throttle` | The `throttle` listener limits the bandwidth of the connection to the given values. |
| 21 | 80⬇ | `github.com/Tasudo/caddy-jailbait/v2` | `http.handlers.jailbait` |  |
| 22 | 75⬇ | `github.com/teodorescuserban/caddy-argsort` | `http.handlers.argsort` | http.handlers.argsort implements an HTTP handler that reorders the query arguments. |
| 23 | 68⬇ | `github.com/sablierapp/sablier/plugins/caddy` | `http.handlers.sablier` |  |
| 24 | 49⬇ | `github.com/kassner/caddy-trapdoor` | `http.handlers.trapdoor` |  |
| 25 | 44⬇ | `github.com/mkalus/caddy_nobots_v2` | `http.handlers.nobots` | http.handlers.nobots plugin struct, including config |
| 26 | 43⬇ | `github.com/abiosoft/caddy-inspect` | `http.handlers.inspect` | http.handlers.inspect implements an HTTP handler that writes the inspects the current request. |
| 27 | 37⬇ | `github.com/dotvezz/caddy-mirror` | `http.handlers.mirror` | http.handlers.mirror runs multiple handlers and aggregates their results |
| 28 | 35⬇ | `github.com/ewen-lbh/caddy-i18n` | `http.handlers.i18n` |  |
| 29 | 23⬇ | `github.com/sablierapp/sablier-caddy-plugin` | `` |  |
| 30 | 17⬇ | `github.com/scionproto-contrib/caddy-scion` | `http.handlers.scion, scion` | scion implements a caddy module. |
| 31 | 12⬇ | `github.com/via-justa/adguard-home` | `` |  |
| 32 | 11⬇ | `maxchernoff.ca/tools/speedtest` | `http.handlers.speedtest` | [Speedtest] implements an HTTP handler that performs speed tests. |
| 33 | 10⬇ | `github.com/xico42/caddy-lura` | `http.handlers.lura` |  |
| 34 | 8⬇ | `github.com/aureolebigben/caddy-http-service` | `http.handlers.http_service` | http.handlers.http_service implements an HTTP handler module that proxies requests to an external HTTP service. It is registered as http.handlers.http_service. |
| 35 | 8⬇ | `github.com/muety/caddy-plausible-plugin` | `http.handlers.plausible` |  |
| 36 | 6⬇ | `github.com/steffenbusch/caddy-i18n-template-ext` | `http.handlers.templates.functions.i18n` | http.handlers.templates.functions.i18n implements a simple internationalization (i18n) template extension for Caddy v2. It loads translation dictionaries from a JSON file and provides template functio |
| 37 | 3⬇ | `github.com/sebdroid/cookiecrypt` | `http.handlers.cookiecrypt` |  |
| 38 | 1⬇ | `github.com/hookenz/caddy-signed-urls` | `http.matchers.signed_url` |  |
| 39 | 1⬇ | `github.com/pberkel/caddy-redir-dns` | `http.handlers.redir_dns` | http.handlers.redir_dns is a Caddy module implementing HTTP redirects stored in DNS TXT records |
| 40 | 0⬇ | `github.com/muety/caddy-hitkeep-plugin` | `http.handlers.hitkeep` |  |

## 25. 其他 (Other)

> 共 40 个插件

| # | 下载量 | 插件路径 | 模块 | 功能说明 |
|---|--------|----------|------|----------|
| 1 | 3091⬇ | `github.com/abiosoft/caddy-hmac` | `http.handlers.hmac` | http.handlers.hmac implements an HTTP handler that validates request body with hmac. |
| 2 | 1290⬇ | `github.com/sagikazarmark/caddy-fs-s3` | `caddy.fs.s3` | caddy.fs.s3 is a Caddy virtual filesystem module for AWS S3 (and compatible) object store. |
| 3 | 494⬇ | `github.com/RussellLuo/caddy-ext/layer4` | `` |  |
| 4 | 370⬇ | `github.com/RussellLuo/caddy-ext/requestbodyvar` | `http.handlers.request_body_var` | http.handlers.request_body_var implements an HTTP handler that replaces {http.request.body.*} with the value of the given field from request body, if any. |
| 5 | 277⬇ | `github.com/neodyme-labs/user_agent_parse` | `http.handlers.user_agent_parse` |  |
| 6 | 265⬇ | `github.com/RussellLuo/caddy-ext/flagr` | `` |  |
| 7 | 254⬇ | `github.com/cubic3d/caddy-ct` | `http.handlers.ct` | http.handlers.ct allows to transpile YAML based configuration into a JSON ignition to be used with Flatcar or Fedora CoreOS. |
| 8 | 207⬇ | `github.com/darkweak/go-esi/middleware/caddy` | `http.handlers.esi` | http.handlers.esi to handle, process and serve ESI tags. |
| 9 | 198⬇ | `github.com/steffenbusch/caddy-cron-matcher` | `http.matchers.cron` | http.matchers.cron matches requests based on multiple sets of cron expressions. It allows you to define multiple time windows during which requests should be matched. The matcher becomes active after |
| 10 | 177⬇ | `github.com/anapaya/caddy-reconnect` | `reconnect` | reconnect is a module that provides an additional "reconnect" network type that can be used to reconnect to a [network address] if the initial connection fails. |
| 11 | 176⬇ | `github.com/greenpau/caddy-lambda` | `http.handlers.lambda` | http.handlers.lambda is a middleware which triggers execution of a function when it is invoked. |
| 12 | 170⬇ | `github.com/greenpau/caddy-appd` | `` |  |
| 13 | 139⬇ | `github.com/Scarsz/caddy-save` | `http.handlers.save` |  |
| 14 | 117⬇ | `github.com/oltdaniel/caddy-ipinfo-free` | `` |  |
| 15 | 104⬇ | `github.com/steffenbusch/caddy-bot-barrier` | `http.handlers.bot_barrier` | http.handlers.bot_barrier is a Caddy middleware module that requires clients to solve a computational challenge before granting access to HTTP resources. It helps mitigate bot traffic. |
| 16 | 74⬇ | `github.com/steffenbusch/caddy-extra-placeholders` | `http.handlers.extra_placeholders` | http.handlers.extra_placeholders represents the structure for the plugin. |
| 17 | 59⬇ | `github.com/mohammed90/caddy_profiling/profiling` | `profiling` | The `profiling` app hosts the collection of push-based profiling agents with common profiling parameters acorss the Caddy instance. |
| 18 | 54⬇ | `github.com/mholt/caddy-psl` | `http.handlers.public_suffix` | http.handlers.public_suffix adds placeholders that return values based on the Public Suffix List, or PSL (https://publicsuffix.org). The placeholders can be useful for routing, responses, headers, or |
| 19 | 53⬇ | `git.gorbe.io/caddy/crawler` | `http.matchers.crawler` |  |
| 20 | 42⬇ | `github.com/mohammed90/caddy_profiling/pyroscope` | `profiling.profiler.pyroscope, pyroscope` | profiling.profiler.pyroscope is the container of the `pyroscope` profiler if configured as a guest module of the `profiling` app |
| 21 | 40⬇ | `github.com/mohammed90/caddy_profiling/profefe` | `profefe, profiling.profiler.profefe` | The `profefe` app collects profiling data during the life-time of the process and uploads them to the profefe server. |
| 22 | 33⬇ | `github.com/dbaggett/caddy-olo-signature-authorization` | `http.handlers.olo_signature` |  |
| 23 | 33⬇ | `github.com/urfave/cli/v3` | `` |  |
| 24 | 32⬇ | `github.com/infogulch/xtemplate` | `http.handlers.xtemplate` |  |
| 25 | 31⬇ | `github.com/libdns/hexonet` | `` |  |
| 26 | 19⬇ | `github.com/teler-sh/teler-caddy` | `` |  |
| 27 | 15⬇ | `github.com/clickonetwo/tracker` | `http.handlers.adobe_usage_tracker` | http.handlers.adobe_usage_tracker implements HTTP middleware that parses uploaded log files from Adobe desktop applications in order to collect measurements about past launches. These measurements are |
| 28 | 15⬇ | `github.com/kitche/caddy-modsecurity` | `` |  |
| 29 | 15⬇ | `github.com/sagikazarmark/caddy-k8s-admission` | `http.handlers.k8s_admission, k8s.admission.always_allow, k8s.admission.always_deny, ...` | http.handlers.k8s_admission is a Caddy HTTP handler that processes Kubernetes admission webhook requests.  It acts as a host module that loads guest admission controller modules. |
| 30 | 15⬇ | `github.com/steffenbusch/caddy-placeholder-dump` | `http.handlers.placeholder_dump` | http.handlers.placeholder_dump is a Caddy module that dumps a placeholder to a file or logs it to a specified logger. It logs the resolved placeholder values to the specified file or logger. |
| 31 | 10⬇ | `github.com/Boomchainlab/vite-react-template/caddy-plugin` | `http.handlers.myplugin` |  |
| 32 | 8⬇ | `github.com/o1egl/paseto/v2` | `` |  |
| 33 | 7⬇ | `github.com/codyps/caddy-fs-archives` | `caddy.fs.archives` | caddy.fs.archives is a Caddy virtual filesystem module for handling archive files. |
| 34 | 4⬇ | `github.com/steffenbusch/caddy-metric-injector` | `http.handlers.metric_counter, http.handlers.metric_injector` | http.handlers.metric_counter is a Caddy HTTP middleware module that defines and increments custom Prometheus counters.  The module allows defining one or more counters that are incremented when incomi |
| 35 | 3⬇ | `github.com/ericls/certmatic` | `certmatic, http.handlers.certmatic_handler_admin, http.handlers.certmatic_handler_ask, ...` | http.handlers.certmatic_handler_portal is the Caddy module for the customer-facing portal.  Caddyfile usage:  	certmatic_portal  Dev mode is enabled by setting portal_dev_dir in the global certmatic b |
| 36 | 3⬇ | `github.com/luishfonseca/caddy-cname-sync` | `cname_sync` | cname_sync reconciles DNS CNAME records for HTTP routes in a given zone. |
| 37 | 2⬇ | `github.com/avvertix/caddy-content-negotiation` | `http.handlers.markdown_intercept` | http.handlers.markdown_intercept is a Caddy middleware that checks if the client accepts text/markdown. If so, it looks for a .md file corresponding to the requested path and serves it instead of dele |
| 38 | 1⬇ | `github.com/ip2location/ip2location-caddy` | `http.handlers.ip2location` |  |
| 39 | 1⬇ | `github.com/jaredfolkins/llmon` | `` |  |
| 40 | 0⬇ | `github.com/mhupfauer/caddy-md4agents` | `http.handlers.markdown_for_agents` | http.handlers.markdown_for_agents is the Caddy module. All durations and sizes are zero-value safe: an unset field falls back to a documented default in Provision. |

---

## 安装说明

所有插件通过 `xcaddy` 构建时包含：

```bash
# 安装 xcaddy
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

# 构建 Caddy + 插件
xcaddy build \
  --with github.com/mholt/caddy-l4 \
  --with github.com/mholt/caddy-ratelimit \
  --with github.com/caddy-dns/cloudflare
```

## 建议安装的插件

根据使用场景推荐：

### 反向代理 + Web 服务器
- `caddyserver/replace-response` — 响应体替换
- `caddyserver/cache-handler` — HTTP 缓存
- `mholt/caddy-ratelimit` — 速率限制
- `porech/caddy-maxmind-geolocation` — GeoIP 过滤
- `caddyserver/transform-encoder` — 日志格式化

### API 网关
- `greenpau/caddy-security` — 认证/授权
- `mholt/caddy-ratelimit` — 限流
- `corazawaf/coraza-caddy/v2` — WAF
- `ggicci/caddy-jwt` — JWT 认证
- `hslatman/caddy-openapi-validator` — API 验证

### 安全加固
- `corazawaf/coraza-caddy/v2` — Coraza WAF
- `hslatman/caddy-crowdsec-bouncer` — CrowdSec 封禁
- `greenpau/caddy-security` — 全功能安全管理
- `porech/caddy-maxmind-geolocation` — 地理封锁
- `mholt/caddy-ratelimit` — DDoS 防护

### Docker 环境
- `lucaslorentz/caddy-docker-proxy/v2` — Docker 自动配置
- `invzhi/caddy-docker-upstreams` — Docker 容器自动发现
- `darkweak/souin/plugins/caddy` — 分布式缓存
- `caddy-dns/cloudflare` — DNS 挑战

> 文档自动生成于 2026-07-20
> 数据来源: https://caddyserver.com/api/packages