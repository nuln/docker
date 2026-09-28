#!/bin/sh
# 生成 frp 传输层 TLS 证书：CA + frps 服务端证书 + frpc 客户端证书。
#
# 背景：frp 从 v0.50.0 起默认 transport.tls.enable = true，但不配证书时
# frps 用随机生成的证书、frpc 也不校验 —— 能加密，但识别不了中间人。
# 这套证书让 frpc / frps 用同一个 CA 互相验证身份。
# 详见 https://gofrp.org/zh-cn/docs/features/common/network/network-tls/
#
# 用法：只给一个根域名，其余 SAN 自动生成
#   ./gen-cert.sh                    # 交互式，问你根域名
#   ./gen-cert.sh example.com
#   ./gen-cert.sh -d example.com
#   ./gen-cert.sh example.com -o /etc/frp/certs -n 3650
#
# 生成的内容（默认 ./certs）：
#   ca.crt / ca.key         私有 CA，frpc 和 frps 共用
#   server.crt / server.key frps 用，CN = frps.<根域名>
#   client.crt / client.key frpc 用，CN = frpc.<根域名>
#
# SAN 自动覆盖：根域名本身、*.根域名（任意子域）、frps./frpc.、localhost、
# 127.0.0.1。所以客户端连 frps.根域名、连根域名、连 IP 都能通过校验。
#
set -eu

OUT_DIR="./certs"
DAYS_CA=36500      # 100 年
DAYS_CERT=36500    # 100 年
ROOT=""

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--domain) ROOT="${2:-}"; shift 2 ;;
        -o|--out)    OUT_DIR="${2:-}"; shift 2 ;;
        -n|--days)   DAYS_CERT="${2:-}"; shift 2 ;;
        -h|--help)   usage 0 ;;
        -*)          echo "未知参数: $1" >&2; usage 1 ;;
        *)           ROOT="$1"; shift ;;
    esac
done

[ -n "$ROOT" ] || {
    printf '根域名（证书会覆盖 根域名 / *.根域名 / frps.根域名 / frpc.根域名）: '
    read -r ROOT
    [ -n "$ROOT" ] || { echo "域名不能为空" >&2; exit 1; }
}

# 校验根域名：去掉误粘的协议/路径/结尾斜杠，然后要求至少两段、每段合法
ROOT="${ROOT#*://}"
ROOT="${ROOT%%/*}"
ROOT="${ROOT%.}"
case "$ROOT" in
    *.*) ;;
    # 用 ${ROOT} 定界：紧跟全角字符时某些 shell 会把「ROOT」整体当成变量名
    *) echo "「${ROOT}」不像根域名（应形如 example.com）" >&2; exit 1 ;;
esac
if echo "$ROOT" | grep -qvE '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$'; then
    echo "根域名含非法字符: ${ROOT}" >&2
    echo "只允许字母、数字、连字符和点" >&2
    exit 1
fi
case "$ROOT" in
    *.*.*.*.*.*) echo "层级太深，不像根域名: ${ROOT}" >&2; exit 1 ;;
esac

command -v openssl >/dev/null 2>&1 || { echo "需要 openssl，请先安装" >&2; exit 1; }
case "$DAYS_CERT" in
    ''|*[!0-9]*) echo "-n 需要是正整数天数" >&2; exit 1 ;;
esac

if [ -f "$OUT_DIR/ca.key" ]; then
    echo "$OUT_DIR/ca.crt 已存在，不重复生成。如需重签请先删掉 $OUT_DIR" >&2
    exit 1
fi

# SAN：根域名 + 通配符 + 两个约定子域 + 本机
SAN="DNS:$ROOT,DNS:*.$ROOT,DNS:frps.$ROOT,DNS:frpc.$ROOT,DNS:localhost,IP:127.0.0.1"

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

# Go 1.15+ 忽略 CN，必须带 SAN
cat > san.cnf <<EOF
[ req ]
distinguished_name = dn
req_extensions     = v3_req
prompt             = no
[ dn ]
# 这个 CN 实际不生效，openssl req 的 -subj 优先级更高；
# 保留该段落只是因为 prompt = no 要求 distinguished_name 必须存在
CN = unused
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage         = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName   = $SAN
EOF

echo "==> 根域名: $ROOT"
echo "==> SAN    : $SAN"
echo
echo "==> 生成 CA"
openssl genrsa -out ca.key 2048 2>/dev/null
openssl req -x509 -new -nodes -key ca.key -subj "/CN=frp-ca" \
    -days "$DAYS_CA" -out ca.crt 2>/dev/null

sign() {
    _name="$1"; _cn="$2"
    echo "==> 生成 $_name 证书 (CN=$_cn)"
    openssl genrsa -out "$_name.key" 2048 2>/dev/null
    openssl req -new -key "$_name.key" -subj "/CN=$_cn" -config san.cnf -out "$_name.csr" 2>/dev/null
    openssl x509 -req -in "$_name.csr" -CA ca.crt -CAkey ca.key -CAcreateserial \
        -days "$DAYS_CERT" -sha256 -extfile san.cnf -extensions v3_req \
        -out "$_name.crt" 2>/dev/null
    # 不带 -extensions v3_req 的话签出来一个扩展都没有（无 SAN），
    # Go 1.15+ 忽略 CN，frp 必然校验失败 —— 所以当场验一下
    openssl x509 -in "$_name.crt" -noout -ext subjectAltName 2>/dev/null \
        | grep -q "Subject Alternative Name" \
        || { echo "生成的 $_name.crt 缺少 SAN 扩展，frp 会校验失败" >&2; exit 1; }
    rm -f "$_name.csr"
    chmod 600 "$_name.key"
}

sign server "frps.$ROOT"
sign client "frpc.$ROOT"

rm -f san.cnf ca.srl
chmod 600 ca.key

echo
echo "==> 校验"
for f in server client; do
    printf "  %-12s %s\n" "$f.crt" "$(openssl x509 -in "$f.crt" -noout -subject | sed 's/subject=//')"
    printf "  %-12s 到期 %s\n" "" "$(openssl x509 -in "$f.crt" -noout -enddate | sed 's/notAfter=//')"
done
printf "  %-12s %s\n" "签名关系" "$(openssl verify -CAfile ca.crt server.crt client.crt 2>/dev/null | sed 's|.*: ||')"
printf "  %-12s %s\n" "SAN" "$(openssl x509 -in server.crt -noout -ext subjectAltName 2>/dev/null | tail -1 | sed 's/^ *//')"
printf "  %-12s %s\n" "CA 到期" "$(openssl x509 -in ca.crt -noout -enddate | sed 's/notAfter=//')"

echo
echo "==> 产物在 $(pwd)"
find . -maxdepth 1 -type f | sed 's|^\./|  |' | sort

cat <<EOF

==> 挂载到容器
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
  # frps 配了 trustedCaFile 就自动 force = true，开始校验客户端身份
  trustedCaFile = "/etc/frp/certs/ca.crt"

==> frpc.toml
  serverAddr = "frps.$ROOT"
  serverPort = 7000
  [auth]
  method = "token"
  token = "你的 token"

  [transport.tls]
  trustedCaFile = "/etc/frp/certs/ca.crt"
  certFile      = "/etc/frp/certs/client.crt"
  keyFile       = "/etc/frp/certs/client.key"

  # 客户端要连别的名字（IP、容器名、另一个域名）时加这行跳过主机名校验：
  # insecureSkipVerify = true
EOF
