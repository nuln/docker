# 精简版（默认镜像，:latest）：只编译核心必需插件
# Pinned, not 'latest': bump deliberately for reproducible builds.
ARG CADDY_VERSION=2.11.4
FROM caddy:builder AS builder
RUN xcaddy build \
  --with github.com/caddy-dns/cloudflare \
  --with github.com/caddy-dns/alidns \
  --with github.com/mholt/caddy-l4 \
  --with github.com/mholt/caddy-dynamicdns

FROM caddy:${CADDY_VERSION}
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
