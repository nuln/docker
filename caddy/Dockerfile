ARG CADDY_VERSION=latest
FROM caddy:builder AS builder
RUN xcaddy build \
  --with github.com/caddy-dns/cloudflare \
  --with github.com/caddy-dns/alidns \
  --with github.com/mholt/caddy-l4 \
  --with github.com/baldinof/caddy-supervisor \
  --with github.com/mholt/caddy-ratelimit \
  --with github.com/caddyserver/cache-handler \
  --with github.com/caddyserver/transform-encoder \
  --with github.com/greenpau/caddy-security

FROM caddy:${CADDY_VERSION}
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
