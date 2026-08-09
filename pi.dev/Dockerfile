# syntax=docker/dockerfile:1
# Build = COPYs + one RUN (all logic in rootfs/etc/s6-overlay/scripts/setup.sh).
# Versions are pinned, not 'latest': bump deliberately for reproducible builds.
ARG PI_VERSION=0.84.1
ARG S6_OVERLAY_VERSION=3.2.0.0
ARG WRANGLER_VERSION=4.120.0
ARG GH_VERSION=v2.97.0
FROM node:24-bookworm

WORKDIR /home/pi/dev

# ---- layer 1 (build-time, changes rarely): build scripts only ----
# setup.sh (and install.d/) must exist before the RUN, so this COPY is first.
COPY rootfs/etc/s6-overlay/scripts /etc/s6-overlay/scripts

# ---- layer 2: one RUN does the whole base setup and pins versions ----
ARG PI_VERSION
ARG S6_OVERLAY_VERSION
ARG WRANGLER_VERSION
ARG GH_VERSION
ENV PI_VERSION=$PI_VERSION \
    S6_OVERLAY_VERSION=$S6_OVERLAY_VERSION \
    WRANGLER_VERSION=$WRANGLER_VERSION \
    GH_VERSION=$GH_VERSION
RUN /etc/s6-overlay/scripts/setup.sh

# ---- layers 3+: runtime-only content (large / rarely-changed) ----
# Placed AFTER the expensive RUN so edits to plugins/templates/providers/s6
# service defs reuse the built base layer (no apt/npm rebuild).
COPY rootfs/etc/s6-overlay/plugins /etc/s6-overlay/plugins
COPY rootfs/etc/s6-overlay/templates /etc/s6-overlay/templates
COPY rootfs/etc/s6-overlay/providers /etc/s6-overlay/providers
COPY rootfs/etc/s6-overlay/s6-rc.d /etc/s6-overlay/s6-rc.d

ENV BASH_ENV=/etc/pi-env.sh

ENTRYPOINT ["/init"]
CMD ["/usr/local/bin/entrypoint.sh"]

# Health: web UI :3141 when PI_AUTOSTART_WEB=true (default), else liveness.
# interval/start_period tuned so first-boot wiring (apt-free image) finishes first.
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD ["/etc/s6-overlay/scripts/healthcheck.sh"]

# Usage:
#   docker compose up -d                      # first boot: s6 wires baked plugins + auto-starts web
#   docker compose exec -it pi pi             # open the pi TUI
#   docker compose exec pi install.sh go      # install a coding environment on demand
#   docker compose exec pi install.sh plugins --im   # (re)install one plugin group