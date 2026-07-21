ARG PASEO_VERSION=latest
FROM ghcr.io/getpaseo/paseo:${PASEO_VERSION}

COPY install.sh /usr/local/bin/install.sh
RUN chmod +x /usr/local/bin/install.sh && \
    PASEO_CACHE=/opt/paseo-cache install.sh setup-bash-wrap && \
    PASEO_CACHE=/opt/paseo-cache install.sh claude-code opencode && \
    mv /opt/paseo-cache/opencode/bin/opencode /opt/paseo-cache/opencode/bin/opencode.real && \
    printf '#!/bin/bash\nREAL="$(dirname "$0")/opencode.real"\nif [[ "$*" == *"serve"* ]]; then\n  PORT=$(echo "$*" | grep -oP -- "--port \\K\\d+")\n  [ -n "$PORT" ] && export XDG_DATA_HOME="/home/paseo/.local/share/opencode-${PORT}"\nfi\nexec "$REAL" "$@"\n' > /opt/paseo-cache/opencode/bin/opencode && \
    chmod +x /opt/paseo-cache/opencode/bin/opencode

USER paseo
