ARG OPENCODE_VERSION=latest
FROM node:24-bookworm

WORKDIR /app

# One-shot script to install coding environments (baked into the image; run `install.sh` inside the container)
COPY install.sh /usr/local/bin/install.sh

# Base tools (make/git/zsh) are installed directly in the image as base dependencies, not via the on-demand script.
RUN apt-get update && \
    apt-get install -y --no-install-recommends make git zsh ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

# Done in one pass (all in the root stage): install opencode, create user and directories, set permissions, and build the bash wrapper.
# See install.sh setup-bash-wrap for the bash wrapper: this opencode version runs commands via /bin/bash without -l
# (empirically it does not read ~/.profile / /etc/profile.d), so we wrap /usr/bin/bash with a layer that sources
# each tool's env.sh on startup, letting the opencode process auto-load installed tool environment variables.
# OPENCODE_VERSION defaults to latest (installs npm latest); pin it with --build-arg OPENCODE_VERSION=x.y.z.
RUN npm i -g "opencode-ai@${OPENCODE_VERSION}" && \
    useradd -m opencode && \
    mkdir -p /home/opencode/.local/share/opencode \
             /home/opencode/.local/state/opencode \
             /home/opencode/.config/opencode \
             /home/opencode/cache && \
    chown -R opencode:opencode /home/opencode && \
    chmod +x /usr/local/bin/install.sh && \
    install.sh setup-bash-wrap

USER opencode

# Default to starting the web service (port 4096, bound to all interfaces for local access)
# The coding environment is installed by the user at their own discretion (the container itself installs nothing on start):
#   docker exec <container> install.sh go
EXPOSE 4096
CMD ["opencode", "web", "--hostname", "0.0.0.0", "--port", "4096"]
