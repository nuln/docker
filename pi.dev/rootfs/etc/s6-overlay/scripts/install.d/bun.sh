#!/usr/bin/env bash
# =============================================================================
# install.d/bun.sh — Bun JS/TS runtime installer (loaded by install.sh)
#   desc: Bun JS/TS runtime (single binary, extracts into $CACHE/bun)
#   tool: bun
#   fn:   install_bun
#   usage: install.sh bun [--update]
# =============================================================================
# Depends on install.sh-provided: CACHE, GO_ARCH, FORCE, UPDATED_TAG, log, write_tool_env

install_bun() {
  local dir="$CACHE/bun"
  local ver="${BUN_VERSION:-1.3.14}"
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/bin/bun" ]; then
    log "Bun already installed (skip download)"
  else
    [ "$FORCE" -eq 1 ] && rm -rf "$dir"
    mkdir -p "$dir"
    log "Downloading and installing Bun ${ver} (extract to $dir)..."
    BUN_ARCH="$GO_ARCH"; [ "$BUN_ARCH" = arm64 ] && BUN_ARCH=aarch64; [ "$BUN_ARCH" = amd64 ] && BUN_ARCH=x64
    TMP="/tmp/bun-${ver}.linux-${GO_ARCH}.zip"
    curl -fsSL "https://github.com/oven-sh/bun/releases/download/bun-v${ver}/bun-linux-${BUN_ARCH}.zip" -o "$TMP"
    ( cd "$dir" && unzip -oq "$TMP" )
    rm -f "$TMP"
    # Unzip yields bun-linux-<arch>/bun; move it to dir/bin for PATH (dir name not fixed, locate via find)
    mkdir -p "$dir/bin"
    local bun_bin
    bun_bin="$(find "$dir" -name bun -type f 2>/dev/null | head -1)"
    if [ -n "$bun_bin" ]; then
      cp "$bun_bin" "$dir/bin/bun"
      chmod +x "$dir/bin/bun"
    fi
    rm -rf "$dir"/bun-linux-* 2>/dev/null || true
    log "Bun $ver installed${UPDATED_TAG}"
  fi
  write_tool_env "$dir" \
    "PATH=$dir/bin:\$PATH"
}