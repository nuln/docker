# syntax=docker/dockerfile:1
# Build = one COPY + one RUN (all logic in rootfs/etc/s6-overlay/scripts/setup.sh).
ARG PI_VERSION=latest
ARG S6_OVERLAY_VERSION=3.2.0.0
FROM node:24-bookworm

WORKDIR /home/pi/dev

# rootfs mirrors the container root: s6 service defs (wire-plugins/pi-web) + scripts
# (incl. setup.sh). One RUN does the whole base setup (apt/s6/pi CLIs/user/bake), then deletes itself.
COPY rootfs/ /
RUN /etc/s6-overlay/scripts/setup.sh

ENV BASH_ENV=/etc/pi-env.sh

ENTRYPOINT ["/init"]
CMD ["/usr/local/bin/entrypoint.sh"]

# Usage:
#   docker compose up -d                      # first boot: s6 wires baked plugins + auto-starts web
#   docker compose exec -it pi pi             # open the pi TUI
#   docker compose exec pi install.sh go      # install a coding environment on demand
#   docker compose exec pi install.sh plugins --im   # (re)install one plugin group
