#!/usr/bin/env bash
# =============================================================================
# install.d/go.sh — Go toolchain installer (loaded by install.sh)
#   desc: Go toolchain (extracts into $CACHE/go, adds GOROOT/GOPATH/GOCACHE)
#   tool: go
#   fn:   install_go
#   usage: install.sh go [--update]
# =============================================================================
# Depends on install.sh-provided: CACHE, GO_ARCH, FORCE, UPDATED_TAG, log, write_tool_env

install_go() {
  local dir="$CACHE/go"
  local ver="${GO_VERSION:-1.26.5}"
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/bin/go" ]; then
    log "Go already installed (skip download)"
  else
    [ "$FORCE" -eq 1 ] && rm -rf "$dir"
    mkdir -p "$dir"
    log "Downloading and installing Go ${ver} (extract to $dir)..."
    TMP="/tmp/go-${ver}.linux-${GO_ARCH}.tar.gz"
    curl -fsSL "https://go.dev/dl/go${ver}.linux-${GO_ARCH}.tar.gz" -o "$TMP"
    # Extract directly to the target dir, strip the top-level go/ prefix, no symlinks
    tar -C "$dir" -xzf "$TMP" --strip-components=1
    rm -f "$TMP"
    log "Go $ver installed${UPDATED_TAG}"
  fi
  write_tool_env "$dir" \
    "GOROOT=$dir" \
    "GOPATH=$CACHE/go-pkg" \
    "GOCACHE=$CACHE/go-build" \
    "GOFLAGS=-mod=mod" \
    "PATH=$dir/bin:$CACHE/go-pkg/bin:\$PATH"
}