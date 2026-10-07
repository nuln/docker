# 精简版（默认镜像，:latest）：只编译核心必需插件
#
# CADDY_VERSION 必须传进 builder 阶段并交给 xcaddy，否则：
#   - 编译出的二进制是 xcaddy 解析到的「最新版」，与镜像 tag 脱钩；
#   - 旧的 ARG 声明只在 FROM 行生效，阶段内的 RUN 取不到它。
# 因此下面在 builder 阶段内重新声明一次 ARG，并把版本作为 xcaddy 的位置参数。
ARG CADDY_VERSION=2.11.7

FROM caddy:builder AS builder
ARG CADDY_VERSION
RUN xcaddy build v${CADDY_VERSION} \
  --with github.com/caddy-dns/cloudflare \
  --with github.com/nuln/caddy-plugins/alidns@v0.0.1 \
  --with github.com/mholt/caddy-l4 \
  --with github.com/mholt/caddy-dynamicdns

FROM caddy:${CADDY_VERSION}
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
