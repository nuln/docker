# frpc 和 frps 都装进镜像，启动哪个由 entrypoint 的参数（compose 的 command）决定。
# 版本 pin 在这里，升级改这一个数字。
ARG ALPINE_VERSION=3.22
ARG FRP_VERSION=0.71.0
ARG UPX_VERSION=5.2.1

# ---- 构建阶段：下载 + 校验 + 压缩。工具链不进最终镜像 ----
FROM alpine:${ALPINE_VERSION} AS build
ARG FRP_VERSION
ARG UPX_VERSION
ARG TARGETARCH

RUN apk add --no-cache curl xz

RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) A=amd64 ;; arm64) A=arm64 ;; \
      *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    NAME="frp_${FRP_VERSION}_linux_${A}"; \
    URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}"; \
    curl -fsSL -o "/tmp/$NAME.tar.gz" "$URL/$NAME.tar.gz"; \
    curl -fsSL -o /tmp/sums.txt "$URL/frp_sha256_checksums.txt"; \
    cd /tmp && grep " $NAME.tar.gz\$" sums.txt | sha256sum -c -; \
    tar -xzf "/tmp/$NAME.tar.gz" -C /tmp; \
    curl -fsSL -o /tmp/upx.tar.xz \
      "https://github.com/upx/upx/releases/download/v${UPX_VERSION}/upx-${UPX_VERSION}-${A}_linux.tar.xz"; \
    tar -xJf /tmp/upx.tar.xz -C /tmp; \
    UPX="$(echo /tmp/upx-*/upx)"; \
    mkdir -p /out; \
    for b in frpc frps; do \
      cp "/tmp/$NAME/$b" "/tmp/$b"; chmod +x "/tmp/$b"; \
      "$UPX" --best --quiet "/tmp/$b" 2>/dev/null || true; \
      "/tmp/$b" -v >/dev/null 2>&1 || cp "/tmp/$NAME/$b" "/tmp/$b"; \
      install -m755 "/tmp/$b" "/out/$b"; \
    done

# ---- 运行阶段 ----
FROM alpine:${ALPINE_VERSION}
# ca-certificates 供访问 https 目标，tzdata 让日志时区正确
RUN apk add --no-cache ca-certificates tzdata

COPY --from=build /out/ /usr/local/bin/
COPY --chmod=755 entrypoint.sh /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s \
  CMD ["/entrypoint.sh", "healthcheck"]

ENTRYPOINT ["/entrypoint.sh"]
