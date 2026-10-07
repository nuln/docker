# 精简版（默认镜像，:latest）：只编译核心必需插件
#
# CADDY_VERSION 默认 latest：
#   - 本地 `docker build` 不传参数 → 编译当时的最新稳定版；
#   - CI 解析出最新版本后通过 --build-arg 传入，使镜像 tag 与实际内容一致；
#   - 需要复现或回退时显式传入，例如 --build-arg CADDY_VERSION=2.11.7。
#
# 该 ARG 必须传进 builder 阶段并交给 xcaddy：在第一个 FROM 之前声明的 ARG
# 只对 FROM 行生效，阶段内的 RUN 取不到它，那样 xcaddy 会自行解析 latest，
# 编译产物与镜像 tag 再次脱钩。
ARG CADDY_VERSION=latest

FROM caddy:builder AS builder
ARG CADDY_VERSION
# xcaddy 要的是 git ref：字面量 latest，或 v<version>。
RUN set -eux; \
    if [ "${CADDY_VERSION}" = "latest" ]; then \
      ref=latest; \
    else \
      ref="v${CADDY_VERSION}"; \
    fi; \
    xcaddy build "${ref}" \
      --with github.com/caddy-dns/cloudflare \
      --with github.com/nuln/caddy-plugins/alidns@v0.0.1 \
      --with github.com/mholt/caddy-l4 \
      --with github.com/mholt/caddy-dynamicdns

FROM caddy:${CADDY_VERSION}
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
