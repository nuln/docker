#!/usr/bin/env python3
"""
Caddy 插件文档更新工具
从 https://caddyserver.com/api/packages 拉取所有插件数据，生成完整文档。

用法:
  python3 scripts/update-plugins.py                  # 仅更新文档
  python3 scripts/update-plugins.py --commit          # 更新并提交
  python3 scripts/update-plugins.py --push            # 更新、提交并推送
"""
import sys, json, os, datetime, subprocess, tempfile, urllib.request

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, '..'))
DOC_FILE = os.path.join(PROJECT_DIR, 'plugins.md')
API_URL = 'https://caddyserver.com/api/packages'

CATEGORIES = {
    '01-security': '1. 安全认证 (Security/Auth)',
    '02-dns': '2. DNS 提供商 (DNS Providers)',
    '03-l4': '3. Layer4 TCP/UDP 代理',
    '04-proxy': '4. Layer7 反向代理增强',
    '05-cache': '5. 缓存 (Cache)',
    '06-storage': '6. 存储后端 (Storage)',
    '07-transform': '7. 响应处理/过滤 (Response Transform)',
    '08-logging': '8. 日志与监控 (Logging & Monitoring)',
    '09-ratelimit': '9. 速率限制 (Rate Limit)',
    '10-geoip': '10. GeoIP/地理位置 (Geo Location)',
    '11-ip': '11. IP 管理 (IP Sources & Real IP)',
    '12-realtime': '12. 实时通信 (Realtime)',
    '13-apphost': '13. 应用托管 (App Hosting)',
    '14-compress': '14. 压缩 (Compression)',
    '15-tls': '15. TLS/证书 (TLS & Certificates)',
    '16-webhook': '16. Webhook 与事件 (Webhook & Events)',
    '17-exec': '17. 命令行执行 (Execute)',
    '18-git': '18. Git 集成 (Git Integration)',
    '19-db': '19. 数据库 (Database)',
    '20-ssh': '20. SSH 服务器 (SSH Server)',
    '21-dyndns': '21. 动态 DNS (Dynamic DNS)',
    '22-media': '22. 媒体处理 (Media Processing)',
    '23-config': '23. 配置适配器与格式 (Config & Adapters)',
    '24-util': '24. 实用工具 (Utilities)',
    '99-other': '25. 其他 (Other)',
}


def fetch_plugins():
    print(f'正在从 Caddy API 拉取插件数据...')
    req = urllib.request.Request(API_URL, headers={'User-Agent': 'Caddy-Plugin-Updater/1.0'})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode())
    print(f'拉取成功，共 {len(data["result"])} 个插件')
    return data['result']


def categorize(path, modules):
    module_str = ' '.join([m['name'] for m in modules])
    low_path = path.lower()

    if any(x in module_str for x in ['layer4', 'tcp', 'udp']) or 'caddy-l4' in low_path:
        return '03-l4'
    if any(x in module_str for x in ['reverse_proxy', 'transport', 'handler.proxy']) \
            or any(x in low_path for x in ['ntlm', 'uwsgi', 'forwardproxy', 'gbox', 'scgi', 's3-proxy', 'docker-proxy', 'docker-upstreams', 'acmeproxy']):
        return '04-proxy'
    if any(x in module_str for x in ['caddy.storage']) or 'storage' in low_path or 'certmagic-s3' in low_path:
        return '06-storage'
    if any(x in module_str for x in ['authentication', 'auth', 'jwt', 'oauth', 'oidc', 'saml', 'login', 'authorize', 'paseto', 'discord', 'basicauth2fa', 'basicauthtotp', 'password', 'ldap_basic']) \
            or any(x in low_path for x in ['/security', '/auth', 'authelia', 'kadeessh', 'tailscale-auth', 'oidc']):
        return '01-security'
    if any(x in module_str for x in ['waf', 'crowdsec', 'fail2ban', 'blockaws', 'block', 'geoblock', 'guard']) \
            or any(x in low_path for x in ['waf', 'crowdsec', 'fail2ban']):
        return '01-security'
    if any(x in module_str for x in ['ratelimit', 'rate_limit', 'quantity_limiter']) or 'ratelimit' in low_path:
        return '09-ratelimit'
    if 'caddy-dns/' in path or any(x in module_str for x in ['dns.provider', 'dns01proxy']) \
            or any(x in low_path for x in ['acmeproxy', 'dns-ip', 'dns-fetcher', 'zone-manager', 'cname_sync']) \
            or any(x in module_str for x in ['dns_zone']):
        return '02-dns'
    if any(x in module_str for x in ['http.handlers.cache', 'http_cache']) or 'souin' in low_path or 'cdp-cache' in low_path:
        return '05-cache'
    if any(x in module_str for x in ['geoip', 'geolocation', 'client_asn', 'client_country', 'geofence', 'geo_ops', 'ipfilter_geolocation', 'geojs', 'geocity', 'geocn']) \
            or any(x in low_path for x in ['geoip', 'geolocation', 'maxmind', 'ipfilter', 'geocn', 'geofence', 'geo-ops', 'geoblock']):
        return '10-geoip'
    if any(x in module_str for x in ['realip', 'ip_sources', 'ip_map', 'ipfilter', 'ipgate', 'proxy_protocol', 'ipset', 'ip_list', 'ip_filter', 'dynamic_client_ip', 'dynamic_remote_ip', 'remote_host', 'dynamic_host']) \
            or any(x in low_path for x in ['realip', 'proxyprotocol', 'cloudflare-ip', 'caddy-ip-list', 'cdn-ranges', 'bunny-ip', 'cloudfront', 'edgeone-ip', 'parspack', 'ipfilter', 'ip-map', 'ipmap', 'bunnynet', 'combine-ip']):
        return '11-ip'
    if any(x in module_str for x in ['grpc', 'mercure', 'vulcain']) \
            or any(x in low_path for x in ['mercure', 'vulcain', 'grpc']):
        return '12-realtime'
    if any(x in module_str for x in ['webdav', 'cgi', 'php', 'upload', 's3proxy', 'pocketbase', 'imageproxy']) \
            or any(x in low_path for x in ['webdav', 'cgi', 'frankenphp', 'upload', 'pocketbase', 'imageproxy', 's3-browser']):
        return '13-apphost'
    if any(x in module_str for x in ['encoders.br']) or any(x in low_path for x in ['brotli', 'cbrotli']):
        return '14-compress'
    if any(x in module_str for x in ['tls.get_certificate', 'tls.issuance', 'tls.client_auth', 'tls.permission', 'certificate']) \
            or any(x in low_path for x in ['tls-file', 'pfx-cert', 'certsrv', 'tls-format', 'tls-san', 'tls-issuer', 'tls-permission', 'forticertsync', 'get-certificate-cache', 'revocation-validator', 'fnmt', 'ldap-validator']):
        return '15-tls'
    if 'webhook' in low_path or any(x in module_str for x in ['events.handlers']):
        return '16-webhook'
    if any(x in module_str for x in ['exec', 'command']):
        return '17-exec'
    if 'caddy-git' in low_path or 'git-fs' in low_path:
        return '18-git'
    if any(x in module_str for x in ['sqlite', 'postgres', 'mysql', 'redis', 'nats']) \
            or any(x in low_path for x in ['sqlite', 'pocketbase', 'postgres-storage', 'mysql-storage', 'redis-storage', 'nats']):
        return '19-db'
    if 'kadeessh' in low_path or any(x in module_str for x in ['ssh']):
        return '20-ssh'
    if 'dynamicdns' in low_path:
        return '21-dyndns'
    if any(x in module_str for x in ['image_processor', 'imagefilter', 'pixbooster']) \
            or any(x in low_path for x in ['imagefilter', 'image-processor', 'imageproxy', 'pixbooster', 'pmtiles']):
        return '22-media'
    if any(x in low_path for x in ['nginx-adapter', 'json-parse', 'yaml', 'json-schema', 'jsonc-adapter', 'hcl', 'mysql-adapter', 'olaf', 'named-routes']) \
            or any(x in module_str for x in ['config_loaders']):
        return '23-config'
    if any(x in module_str for x in ['logging.encoders', 'logging.writers', 'trace']) \
            or any(x in low_path for x in ['transform-encoder', 'trace', 'log-', 'influx_log', 'graphite', 'elastic-encoder', 'simpletrace', 'umami']):
        return '08-logging'
    if any(x in module_str for x in ['filter', 'replace_response']) \
            or any(x in low_path for x in ['filter', 'replace-response']):
        return '07-transform'
    if any(x in module_str for x in ['supervisor']) or 'supervisor' in low_path:
        return '24-util'
    if any(x in module_str for x in ['request_id', 'uuid', 'random']) or 'requestid' in low_path:
        return '24-util'
    if any(x in module_str for x in ['openapi', 'validator']) \
            or any(x in low_path for x in ['validator', 'openapi', 'conneg']):
        return '24-util'

    known_util_keywords = ['trojan', 'teapot', 'wol', 'sablier', 'nobots', 'jailbait', 'floaty',
                           'trapdoor', 'redir-dns', 'speedtest', 'lura', 'plausible', 'minifier',
                           'argsort', 'inspect', 'mirror', 'extra_placeholders', 'placeholder_dump',
                           'cookieflag', 'cookiecrypt', 'signed-urls', 'hitcounter', 'hitkeep',
                           'bot_barrier', 'postauth-2fa', 'jwt-issuer', 'i18n', 'defender', 'cerberus',
                           'gopkg', 's3browser', 'scion', 'nats-bridge', 'discord', 'listencaddy',
                           'listen', 'pmtiles', 'guard', 'http-service', 'mcp']
    if any(x in low_path for x in known_util_keywords):
        return '24-util'

    return '99-other'


def extract_docs(modules):
    for m in modules:
        if m.get('docs') and len(m['docs']) > 20:
            text = m['docs']
            idx = text.find('.')
            if idx > 15:
                return text[:idx + 1].replace('|', '/').replace('\n', ' ')
            return text[:200].strip().replace('|', '/').replace('\n', ' ')
    return ''


def generate_doc(plugins):
    today = datetime.date.today().strftime('%Y-%m-%d')
    grouped = {k: [] for k in CATEGORIES}
    for p in plugins:
        cat = categorize(p['path'], p.get('modules', []))
        grouped[cat].append(p)

    md = []
    md.append('# Caddy 插件完全手册')
    md.append('')
    md.append(f'> 数据来源: {API_URL}')
    md.append(f'> 总插件数: {len(plugins)}')
    md.append('')
    md.append('本文档列出了 Caddy 官方插件市场所有可用插件的完整列表，按功能分类整理。')
    md.append('')
    md.append('---')
    md.append('')
    md.append('## 目录')
    md.append('')
    for key in sorted(CATEGORIES):
        if grouped[key]:
            name = CATEGORIES[key]
            md.append(f'- [{name.split(". ", 1)[1]}](#{key}_{name.split(". ", 1)[1].lower().replace("/", "").replace(" ", "-").replace("(", "").replace(")", "")})')
    md.append('')
    md.append(f'_最后更新: {today}_')
    md.append('')

    for key in sorted(CATEGORIES):
        plugs = grouped[key]
        if not plugs:
            continue
        name = CATEGORIES[key]
        md.append(f'## {name}')
        md.append('')
        md.append(f'> 共 {len(plugs)} 个插件')
        md.append('')
        md.append('| # | 下载量 | 插件路径 | 模块 | 功能说明 |')
        md.append('|---|--------|----------|------|----------|')
        for i, p in enumerate(sorted(plugs, key=lambda x: -x['downloads']), 1):
            modules = p.get('modules', [])
            mod_names = ', '.join([m['name'] for m in modules[:3]])
            if len(modules) > 3:
                mod_names += ', ...'
            docs = extract_docs(modules)
            if len(docs) > 250:
                docs = docs[:250] + '...'
            md.append(f'| {i} | {p["downloads"]}⬇ | `{p["path"]}` | `{mod_names}` | {docs} |')
        md.append('')

    md.append('---')
    md.append('')
    md.append('## 安装说明')
    md.append('')
    md.append('所有插件通过 `xcaddy` 构建时包含：')
    md.append('')
    md.append('```bash')
    md.append('# 安装 xcaddy')
    md.append('go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest')
    md.append('')
    md.append('# 构建 Caddy + 插件')
    md.append('xcaddy build \\')
    md.append('  --with github.com/mholt/caddy-l4 \\')
    md.append('  --with github.com/mholt/caddy-ratelimit \\')
    md.append('  --with github.com/caddy-dns/cloudflare')
    md.append('```')
    md.append('')
    md.append('## 建议安装的插件')
    md.append('')
    md.append('根据使用场景推荐：')
    md.append('')
    md.append('### 反向代理 + Web 服务器')
    md.append('- `caddyserver/replace-response` — 响应体替换')
    md.append('- `caddyserver/cache-handler` — HTTP 缓存')
    md.append('- `mholt/caddy-ratelimit` — 速率限制')
    md.append('- `porech/caddy-maxmind-geolocation` — GeoIP 过滤')
    md.append('- `caddyserver/transform-encoder` — 日志格式化')
    md.append('')
    md.append('### API 网关')
    md.append('- `greenpau/caddy-security` — 认证/授权')
    md.append('- `mholt/caddy-ratelimit` — 限流')
    md.append('- `corazawaf/coraza-caddy/v2` — WAF')
    md.append('- `ggicci/caddy-jwt` — JWT 认证')
    md.append('- `hslatman/caddy-openapi-validator` — API 验证')
    md.append('')
    md.append('### 安全加固')
    md.append('- `corazawaf/coraza-caddy/v2` — Coraza WAF')
    md.append('- `hslatman/caddy-crowdsec-bouncer` — CrowdSec 封禁')
    md.append('- `greenpau/caddy-security` — 全功能安全管理')
    md.append('- `porech/caddy-maxmind-geolocation` — 地理封锁')
    md.append('- `mholt/caddy-ratelimit` — DDoS 防护')
    md.append('')
    md.append('### Docker 环境')
    md.append('- `lucaslorentz/caddy-docker-proxy/v2` — Docker 自动配置')
    md.append('- `invzhi/caddy-docker-upstreams` — Docker 容器自动发现')
    md.append('- `darkweak/souin/plugins/caddy` — 分布式缓存')
    md.append('- `caddy-dns/cloudflare` — DNS 挑战')
    md.append('')
    md.append(f'> 文档自动生成于 {today}')
    md.append(f'> 数据来源: {API_URL}')

    return '\n'.join(md)


def main():
    action = 'generate'
    if len(sys.argv) > 1:
        action = sys.argv[1].lstrip('-')

    plugins = fetch_plugins()

    print('正在生成文档...')
    content = generate_doc(plugins)

    with open(DOC_FILE, 'w', encoding='utf-8') as f:
        f.write(content)

    plugin_count = content.count('⬇')
    print(f'文档已生成: {DOC_FILE}')
    print(f'文档包含 {plugin_count} 个插件条目')

    if action in ('commit', 'push'):
        os.chdir(PROJECT_DIR)
        subprocess.run(['git', 'add', 'plugins.md'], check=True)
        result = subprocess.run(['git', 'diff', '--cached', '--quiet'])
        if result.returncode == 0:
            print('无变化，跳过提交')
        else:
            subprocess.run(['git', 'commit', '-m', f'docs(caddy): update plugins list ({len(plugins)} plugins)'], check=True)
            print('已提交更新')
            if action == 'push':
                subprocess.run(['git', 'push'], check=True)
                print('已推送')

    print('完成')


if __name__ == '__main__':
    main()
