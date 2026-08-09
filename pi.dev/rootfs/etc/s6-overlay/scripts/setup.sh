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

INSTALL_D="${PI_INSTALL_D:-/etc/s6-overlay/scripts/install.d}"
if [ -r "$INSTALL_D/versions.env" ]; then
  . "$INSTALL_D/versions.env"
else
  echo "[setup] WARN: $INSTALL_D/versions.env missing" >&2
fi

S6_OVERLAY_VERSION="${S6_OVERLAY_VERSION:-3.2.0.0}"
PI_VERSION="${PI_VERSION:-0.84.1}"
# Pinned via versions.env for reproducible builds (fallback = current stable).
WRANGLER_VERSION="${WRANGLER_VERSION:-4.120.0}"
GH_VERSION="${GH_VERSION:-v2.97.0}"
TARGETARCH="${TARGETARCH:-amd64}"

log() { printf '\n== [setup] %s ==\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. System layer: apt tools + s6-overlay v3
# ---------------------------------------------------------------------------
log "apt tools"
apt-get update
apt-get install -y --no-install-recommends make git zsh ca-certificates curl ripgrep tmux less xz-utils jq tzdata
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
npm i -g "@earendil-works/pi-coding-agent@${PI_VERSION}" "remote-pi@${REMOTE_PI_VERSION:-0.5.5}" \
    --allow-scripts=@google/genai,protobufjs,remote-pi

log "wrangler CLI (Cloudflare), pinned ${WRANGLER_VERSION}"
npm i -g "wrangler@${WRANGLER_VERSION}"

log "GitHub CLI (gh, ${GH_VERSION})"
case "${TARGETARCH:-amd64}" in
  amd64) GH_ARCH=amd64 ;;
  arm64) GH_ARCH=arm64 ;;
  *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;;
esac
GH_VER="${GH_VERSION}"
curl -fsSL "https://github.com/cli/cli/releases/download/${GH_VER}/gh_${GH_VER#v}_linux_${GH_ARCH}.tar.gz" -o /tmp/gh.tar.gz
tar -C /usr/local -xzf /tmp/gh.tar.gz --strip-components=1 "gh_${GH_VER#v}_linux_${GH_ARCH}/bin/gh"
rm -f /tmp/gh.tar.gz

log "user pi"
useradd -m -u 1000 -s /bin/bash pi
mkdir -p /home/pi/.pi/agent /home/pi/cache /home/pi/dev
chown -R pi:pi /home/pi

# ---------------------------------------------------------------------------
# 2b. oh-my-zsh + user shell (as user pi). We bake it into the image layer so
# every container starts with a richer CLI (syntax highlighting, autosuggest,
# git aliases) after `docker compose exec -it pi zsh` / a `pi` shell. Default
# shell of user `pi` is switched to zsh so interactive exec lands in it.
# ---------------------------------------------------------------------------
log "oh-my-zsh"
su -s /bin/bash pi -c '
  set -euo pipefail
  ZXD_DIR="$HOME/.oh-my-zsh"
  OMZ_COMMIT="${OMZ_COMMIT:-99aaf58d007f1378d1e0609bcd9baf8abbbaf327}"
  ZSH_SYNTAX_VERSION="${ZSH_SYNTAX_VERSION:-0.8.0}"
  ZSH_AUTOSUGGEST_VERSION="${ZSH_AUTOSUGGEST_VERSION:-0.7.1}"
  # oh-my-zsh is a rolling repo (no release tags): pin the exact master commit.
  if [ ! -d "$ZXD_DIR" ]; then
    git init -q "$ZXD_DIR"
    git -C "$ZXD_DIR" remote add origin https://github.com/ohmyzsh/ohmyzsh.git
    git -C "$ZXD_DIR" fetch -q --depth=1 origin "$OMZ_COMMIT"
    git -C "$ZXD_DIR" checkout -q FETCH_HEAD
  fi
  # two batteries-included plugins: syntax highlighting + autosuggestions (pinned tags)
  mkdir -p "$ZXD_DIR/custom/plugins"
  clone_plg() { [ -d "$ZXD_DIR/custom/plugins/$1" ] || git clone -q --depth=1 --branch "$3" "$2" "$ZXD_DIR/custom/plugins/$1" || true; }
  clone_plg zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_SYNTAX_VERSION"
  clone_plg zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git "v${ZSH_AUTOSUGGEST_VERSION}"
  # .zshrc: load the toolchain env (same file pi uses via BASH_ENV) + oh-my-zsh
  # Use the ABSOLUTE path (not $HOME) so sourcing it works for any user incl.
  # root (CI validation, docker exec) — $HOME here would point at /root.
  cat > "$HOME/.zshrc" <<'"'"'ZSHRC'"'"'
# glob with no matches (e.g. no toolchains yet) must not error in zsh
setopt nonomatch 2>/dev/null || true

# source each toolchain env.sh (same list BASH_ENV uses for pi)
for __f in /home/pi/cache/*/env.sh; do [ -r "$__f" ] && . "$__f"; done
[ -f /etc/pi-env.sh ] && . /etc/pi-env.sh

export ZSH=/home/pi/.oh-my-zsh
ZSH_THEME="robbyrussell"
plugins=(git zsh-syntax-highlighting zsh-autosuggestions)
source "$ZSH/oh-my-zsh.sh"
ZSHRC
  chmod 644 "$HOME/.zshrc"
'
chsh -s /usr/bin/zsh pi
log "oh-my-zsh installed, pi default shell: zsh"

# ---------------------------------------------------------------------------
# 3. PATH symlinks + BASH_ENV bootstrap
# ---------------------------------------------------------------------------
log "PATH symlinks"
ln -sf /etc/s6-overlay/scripts/install.sh /usr/local/bin/install.sh
ln -sf /etc/s6-overlay/scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
ln -sf /etc/s6-overlay/scripts/new-project.sh /usr/local/bin/new-project
ln -sf /etc/s6-overlay/scripts/skills.sh /usr/local/bin/skills

log "BASH_ENV bootstrap"
/usr/local/bin/install.sh setup-bash-env

# ---------------------------------------------------------------------------
# 4. Bake curated plugins into the image-layer store (as user pi)
# ---------------------------------------------------------------------------
log "bake curated plugins"
su -s /bin/bash pi -c '/usr/local/bin/install.sh plugins all'
# Rewrite plugin refs from relative "npm:" to absolute store paths. The store
# root is derived from the FIRST generated package path (never hardcoded), so
# it tracks pi's actual npm layout across package-manager changes. The derived
# root is persisted to /etc/s6-overlay/store-path for wire-plugins to consume.
SETTINGS=/home/pi/.pi/agent/settings.json
# Rewrite plugin refs from relative "npm:" (possibly "@scope/name@ver") to absolute
# store paths. Strip the @version suffix first (the on-disk dir keeps no version;
# /home/pi/.pi-plugins/npm/node_modules/<name>). The store root is derived from the
# FIRST generated package path (never hardcoded), so it tracks pi's actual npm
# layout across package-manager changes. The derived root is persisted to
# /etc/s6-overlay/store-path for wire-plugins to consume.
STORE_ROOT=/home/pi/.pi-plugins/npm/node_modules
jq --arg root "$STORE_ROOT" '
  .packages |= map(
    sub("^npm:"; "") as $ref |
    ($ref | capture("^(?<name>@[^@/]+/[^@]+|[^@]+)(@.*)?$").name) as $dir |
    $root + "/" + $dir
  )
' "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
STORE_SRC="$(jq -r '.packages[0] | capture("^(?<root>.*/node_modules)/").root' "$SETTINGS" 2>/dev/null || true)"
if [ -z "${STORE_SRC}" ]; then
  echo "[setup] WARN: could not derive baked store root from settings.json — falling back" >&2
  STORE_SRC="${STORE_ROOT}"
fi
echo "${STORE_SRC}" > /etc/s6-overlay/store-path
mv /home/pi/.pi/agent /home/pi/.pi-plugins
mkdir -p /home/pi/.pi/agent
chown -R pi:pi /home/pi/.pi /home/pi/.pi-plugins
log "baked plugin store: ${STORE_SRC}"

# ---------------------------------------------------------------------------
# 5. Cleanup
# ---------------------------------------------------------------------------
log "done"
rm -f "$0"