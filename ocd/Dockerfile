# syntax=docker/dockerfile:1
# Pinned versions: bump deliberately for reproducible builds.
ARG DEBIAN_VERSION=bookworm-slim
ARG OCD_VERSION=0.2.1

FROM debian:${DEBIAN_VERSION} AS runtime

ARG TARGETARCH
ARG OCD_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    HOME=/home/ocd

# Combine installation, libc dependency resolution, user creation, and download into minimal layers
RUN echo "deb http://deb.debian.org/debian trixie main" >> /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends -t trixie \
      libc6 \
      libstdc++6 \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      tini \
      tzdata \
      jq \
      procps \
    && rm -rf /var/lib/apt/lists/* \
    && ARCH="${TARGETARCH:-}" \
    && if [ -z "${ARCH}" ]; then \
         ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"; \
       fi \
    && case "${ARCH}" in \
         amd64|x86_64) OCD_ARCH="linux-x64" ;; \
         arm64|aarch64) OCD_ARCH="linux-arm64" ;; \
         *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
       esac \
    && DOWNLOAD_URL="https://github.com/elliothux/open-compute/releases/download/v${OCD_VERSION}/ocd-v${OCD_VERSION}-${OCD_ARCH}" \
    && echo "Downloading ${DOWNLOAD_URL}..." \
    && curl -fsSL --retry 3 "${DOWNLOAD_URL}" -o /usr/local/bin/ocd \
    && chmod 755 /usr/local/bin/ocd \
    && printf '#!/bin/sh\ncase "$*" in\n  *is-active*)\n    pgrep ocd >/dev/null 2>&1 && exit 0 || exit 3\n    ;;\n  *show*)\n    echo "ActiveState=active"\n    echo "SubState=running"\n    exit 0\n    ;;\n  *start\\ dev.open-compute.ocd.*)\n    CONF=$(find "$HOME/.config/open-compute" -name "config.toml" 2>/dev/null | head -n 1)\n    if [ -n "$CONF" ]; then\n      ocd --config "$CONF" run &\n    fi\n    ;;\nesac\nexit 0\n' > /usr/local/bin/systemctl \
    && chmod 755 /usr/local/bin/systemctl \
    && useradd -m -u 1000 -s /bin/bash ocd \
    && mkdir -p /var/lib/open-compute /home/ocd/.config /home/ocd/.local \
    && chown -R ocd:ocd /home/ocd /var/lib/open-compute

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

WORKDIR /home/ocd

# 8787: Public Worker runtime & Cloudflare-compatible v4 API
# 18787: Optional Dashboard / Admin port
EXPOSE 8787 18787

VOLUME ["/home/ocd"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["ocd", "run"]
