#!/usr/bin/env bash
# =============================================================================
# setup.sh — build-time only (Dockerfile RUN, as root). Installs the base layer:
#   1. apt tools + s6-overlay v3 (the process supervisor; /init becomes PID 1)
#   2. pi CLI + remote-pi CLI + system user `pi` (uid 1000) + home dirs
#   3. PATH symlinks + BASH_ENV bootstrap (needs install.d/ from rootfs)
#   4. bake the curated plugins into the image-layer store /home/pi/.pi-plugins
#
# Runs AFTER COPY rootfs/ (s6 tar merge semantics: the tarball only adds files,
# never deletes our rootfs files). Build-time only — deletes itself at the end.
# =============================================================================
set -euo pipefail

S6_OVERLAY_VERSION="${S6_OVERLAY_VERSION:-3.2.0.0}"
PI_VERSION="${PI_VERSION:-latest}"
TARGETARCH="${TARGETARCH:-amd64}"

log() { printf '\n== [setup] %s ==\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. System layer: apt tools + s6-overlay v3
# ---------------------------------------------------------------------------
log "apt tools"
apt-get update
apt-get install -y --no-install-recommends make git zsh ca-certificates curl ripgrep tmux less xz-utils jq
rm -rf /var/lib/apt/lists/*

userdel node

log "s6-overlay v${S6_OVERLAY_VERSION}"
case "${TARGETARCH:-amd64}" in
  amd64) S6_ARCH=x86_64 ;;
  arm64) S6_ARCH=aarch64 ;;
  *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac
curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" -o /tmp/s6-noarch.tar.xz
curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" -o /tmp/s6-arch.tar.xz
tar -C / -Jxpf /tmp/s6-noarch.tar.xz
tar -C / -Jxpf /tmp/s6-arch.tar.xz
rm -f /tmp/s6-noarch.tar.xz /tmp/s6-arch.tar.xz

# ---------------------------------------------------------------------------
# 2. pi CLIs + user
# ---------------------------------------------------------------------------
log "pi CLI + remote-pi CLI"
npm i -g "@earendil-works/pi-coding-agent@${PI_VERSION}" remote-pi \
    --allow-scripts=@google/genai,protobufjs,remote-pi

log "wrangler CLI (Cloudflare)"
npm i -g wrangler

log "GitHub CLI (gh)"
case "${TARGETARCH:-amd64}" in
  amd64) GH_ARCH=amd64 ;;
  arm64) GH_ARCH=arm64 ;;
  *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac
GH_VER="$(curl -fsSL "https://api.github.com/repos/cli/cli/releases/latest" | jq -r .tag_name)"
curl -fsSL "https://github.com/cli/cli/releases/download/${GH_VER}/gh_${GH_VER#v}_linux_${GH_ARCH}.tar.gz" -o /tmp/gh.tar.gz
tar -C /usr/local -xzf /tmp/gh.tar.gz --strip-components=1 "gh_${GH_VER#v}_linux_${GH_ARCH}/bin/gh"
rm -f /tmp/gh.tar.gz

log "user pi"
useradd -m -u 1000 -s /bin/bash pi
mkdir -p /home/pi/.pi/agent /home/pi/cache /home/pi/dev
chown -R pi:pi /home/pi

# ---------------------------------------------------------------------------
# 3. PATH symlinks + BASH_ENV bootstrap
# ---------------------------------------------------------------------------
log "PATH symlinks"
ln -sf /etc/s6-overlay/scripts/install.sh /usr/local/bin/install.sh
ln -sf /etc/s6-overlay/scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

log "BASH_ENV bootstrap"
/usr/local/bin/install.sh setup-bash-env

# ---------------------------------------------------------------------------
# 4. Bake curated plugins into the image-layer store (as user pi)
# ---------------------------------------------------------------------------
log "bake curated plugins"
su -s /bin/bash pi -c '/usr/local/bin/install.sh plugins all'
sed -i -E 's|"npm:([^"]+)"|"/home/pi/.pi-plugins/npm/node_modules/\1"|g' \
    /home/pi/.pi/agent/settings.json
mv /home/pi/.pi/agent /home/pi/.pi-plugins
mkdir -p /home/pi/.pi/agent
chown -R pi:pi /home/pi/.pi /home/pi/.pi-plugins

# ---------------------------------------------------------------------------
# 5. Cleanup
# ---------------------------------------------------------------------------
log "done"
rm -f "$0"