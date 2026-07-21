ARG LUNEL_VERSION=latest
FROM node:24-bookworm AS base

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends bash git ca-certificates curl unzip && \
    rm -rf /var/lib/apt/lists/* && \
    curl -fsSL https://bun.sh/install | bash

ENV BUN_INSTALL=/root/.bun
ENV PATH=$BUN_INSTALL/bin:$PATH

FROM base AS build
WORKDIR /build
RUN git clone --depth=1 https://github.com/lunel-dev/lunel.git .
RUN cd manager && bun install 2>/dev/null; cd ../proxy && bun install 2>/dev/null; true

FROM base
WORKDIR /app

COPY --from=build /build/manager /app/manager
COPY --from=build /build/proxy /app/proxy
COPY --from=build /build/cli /app/cli

RUN sed -i 's/if (parsed.protocol !== "https:")/if (false \/\* allow http for internal docker \*\/)/' /app/proxy/src/index.ts && \
    sed -i 's|managerUrl.replace(/^https:/, "wss:")|managerUrl.replace(/^http:/, "ws:").replace(/^https:/, "wss:")|' /app/proxy/src/index.ts && \
    sed -i 's/console.log(`\[proxy\] started/connectManagerControl();\nconsole.log(`[proxy] started/' /app/proxy/src/index.ts && \
    sed -i 's/if (parsed.protocol !== "https:")/if (false \/\* allow http for internal docker \*\/)/' /app/manager/src/index.ts

COPY install.sh /usr/local/bin/install.sh
RUN chmod +x /usr/local/bin/install.sh && install.sh setup-shell-source

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["lunel-manager"]
