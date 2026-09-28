#!/bin/sh
# 生成 frp 传输层 TLS 证书（CA + frps 服务端证书 + frpc 客户端证书）。
#
# 背景：frp 从 v0.50.0 起默认 transport.tls.enable = true，但不配证书时
# frps 用随机证书、frpc 也不校验 —— 能加密，但无法识别中间人。
# 配了下面这套证书后，frpc/frps 用同一个 CA 互相验证身份。
# 详见 https://gofrp.org/zh-cn/docs/features/common/network/network-tls/
#
# 用法：
#   ./gen-cert.sh                                   # 交互式，问你域名
#   ./gen-cert.sh frps.example.com                  # 只给 frps 签证书
#   ./gen-cert.sh frps.example.com client.example.com   # 两边都签
#   ./gen-cert.sh -d frps.example.com               # 等价于位置参数
#   ./gen-cert.sh -d '*.example.com,frps.example.com'  # 通配符 SAN
#   ./gen-cert.sh -d frps.example.com -o /etc/frp/certs -n 825
#
# 产物（默认 ./certs）：
#   ca.crt / ca.key         自签 CA，两端共享
#   server.crt / server.key frps 用，SAN = 你输入的域名
#   client.crt / client.key frpc 用（双向验证时）
#
set -eu

OUT_DIR="./certs"
# 私有 CA 自己控制有效期，没有 Let's Encrypt 那种 90 天上限，直接拉到最长。
# 36500 天 = 100 年。代价是私钥泄露后无法靠续期解决，只能整个 CA 重建重签。
DAYS_CA=36500
DAYS_CERT=36500
DOMAINS=""
NO_CLIENT=0
CA_CN="frp-ca"

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--domain) DOMAINS="${2:-}"; shift 2 ;;
        -o|--out)    OUT_DIR="${2:-}"; shift 2 ;;
        -n|--days)   DAYS_CERT="${2:-}"; shift 2 ;;
        --ca-cn)     CA_CN="${2:-}"; shift 2 ;;
        --server-only) NO_CLIENT=1; shift ;;
        -h|--help)   usage 0 ;;
        -*)          echo "未知参数: $1" >&2; usage 1 ;;
        *)           DOMAINS="${DOMAINS:+$DOMAINS,}$1"; shift ;;
    esac
done

# 没给域名就问
if [ -z "$DOMAINS" ]; then
    printf 'frps 的域名（可用逗号分隔多个 / 通配符，如 *.example.com）: '
    read -r DOMAINS
    [ -n "$DOMAINS" ] || { echo "域名不能为空" >&2; exit 1; }
fi

command -v openssl >/dev/null 2>&1 || { echo "需要 openssl，请先安装" >&2; exit 1; }

# 域名合法性：只允许字母数字、点、横线、下划线、星号
echo "$DOMAINS" | tr ',' '\n' | while read -r d; do
    case "$d" in
        *[!A-Za-z0-9.*_-]*) echo "域名含非法字符: $d" >&2; exit 1 ;;
    esac
done

# 生成 SAN 值列表：a.com,*.a.com → DNS:a.com,DNS:*.a.com ；10.0.0.5 → IP:10.0.0.5
# 注意这里只放值，"subjectAltName=" 前缀由下面配置文件的那行提供，不能重复写，
# 否则 OpenSSL 会报 unsupported option: name=subjectAltName=IP
echo "$DOMAINS" | tr ',' '\n' | while read -r d; do
    [ -n "$d" ] || continue
    case "$d" in
        *[!0-9.]*) printf 'DNS:%s,' "$d" ;;   # 含字母 → 域名
        *)         printf 'IP:%s,' "$d" ;;   # 纯数字点 → IP
    esac
done > /tmp/.frp_san.$$
SAN="$(sed 's/,$//' /tmp/.frp_san.$$)"
rm -f /tmp/.frp_san.$$
[ -n "$SAN" ] || { echo "SAN 为空，检查域名参数" >&2; exit 1; }

[ -f "$OUT_DIR/ca.key" ] && { echo "$OUT_DIR/ca.crt 已存在，不重复生成。如需重签请先删掉 $OUT_DIR" >&2; exit 1; }

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

# Go 1.15+ 忽略 CN，必须用 SAN
cat > san.cnf <<EOF
[ req ]
distinguished_name = dn
req_extensions     = v3_req
prompt             = no
[ dn ]
CN = frp-local
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage         = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName   = $SAN
EOF
echo "  SAN = $SAN"

echo "==> 生成 CA"
openssl genrsa -out ca.key 2048 2>/dev/null
openssl req -x509 -new -nodes -key ca.key -subj "/CN=$CA_CN" \
    -days "$DAYS_CA" -out ca.crt 2>/dev/null

sign() {
    _name="$1"; _cn="$2"
    echo "==> 生成 $_name 证书"
    openssl genrsa -out "$_name.key" 2048 2>/dev/null
    openssl req -new -key "$_name.key" -subj "/CN=$_cn" -config san.cnf -out "$_name.csr" 2>/dev/null
    openssl x509 -req -in "$_name.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
        -days "$DAYS_CERT" -sha256 -extfile san.cnf -extensions v3_req \
        -out "$_name.crt" 2>/dev/null
    # 不带 -extensions v3_req 的话，签出来的证书一个扩展都没有（无 SAN）。
    # Go 1.15+ 忽略 CN，frp 会直接判定校验失败 —— 所以这里当场验一下。
    openssl x509 -in "$_name.crt" -noout -ext subjectAltName 2>/dev/null \
        | grep -q "Subject Alternative Name" \
        || { echo "生成的 $_name.crt 缺少 SAN 扩展，frp 会校验失败" >&2; exit 1; }
    rm -f "$_name.csr"
    chmod 600 "$_name.key"
}

sign server "$(echo "$DOMAINS" | cut -d, -f1)"
[ "$NO_CLIENT" = 0 ] && sign client frpc

rm -f san.cnf ca.srl
chmod 600 ca.key

echo
echo "==> 校验"
for f in server client; do
    [ -f "$f.crt" ] || continue
    printf "  %-12s %s\n" "$f.crt" "$(openssl x509 -in "$f.crt" -noout -subject | sed 's/subject=//')"
    printf "  %-12s SAN: %s\n" "" "$(openssl x509 -in "$f.crt" -noout -ext subjectAltName 2>/dev/null | tail -1 | sed 's/^ *//')"
    printf "  %-12s 到期: %s\n" "" "$(openssl x509 -in "$f.crt" -noout -enddate | sed 's/notAfter=//')"
done
printf "  %-12s %s\n" "签名关系" "$(openssl verify -CAfile ca.crt server.crt 2>/dev/null | sed 's|.*: ||')"
printf "  %-12s %s\n" "CA 到期" "$(openssl x509 -in ca.crt -noout -enddate | sed 's/notAfter=//')"

echo
echo "==> 产物在 $(pwd)"
find . -maxdepth 1 -type f | sed 's|^\./|  |' | sort

cat <<EOF

==> 挂载到容器（假设配置目录 ./conf 里放 frps.toml）
  volumes:
    - ./conf:/etc/frp:ro
    - $(pwd):/etc/frp/certs:ro

==> frps.toml
  bindPort = 7000
  [auth]
  method = "token"
  token = "你的 token"

  [transport.tls]
  certFile      = "/etc/frp/certs/server.crt"
  keyFile       = "/etc/frp/certs/server.key"
  # frps 配了 trustedCaFile 就会自动 force = true，开始校验客户端身份
  trustedCaFile = "/etc/frp/certs/ca.crt"

==> frpc.toml
  serverAddr = "$DOMAINS"
  serverPort = 7000
  [auth]
  method = "token"
  token = "你的 token"

  [transport.tls]
  trustedCaFile = "/etc/frp/certs/ca.crt"
EOF

if [ "$NO_CLIENT" = 0 ]; then
cat <<EOF
  certFile = "/etc/frp/certs/client.crt"
  keyFile  = "/etc/frp/certs/client.key"
EOF
fi

cat <<'EOF'

⚠️  frpc 的 serverAddr 必须与 server.crt 的 SAN 对得上，否则登录失败：
      frpc: connect to server error: session shutdown
      frps: remote error: tls: bad certificate
    确实要用 IP 或容器名连接时，在 frpc 侧开 insecureSkipVerify = true
EOF
