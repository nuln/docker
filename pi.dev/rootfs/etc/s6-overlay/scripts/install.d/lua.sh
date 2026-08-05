#!/usr/bin/env bash
# =============================================================================
# install.d/lua.sh — Lua 5.4 installer (official source build, loaded by install.sh)
#   desc: Lua 5.4 (official source build; uses the image's bundled gcc/make)
#   tool: lua
#   fn:   install_lua
#   usage: install.sh lua [--update]
# =============================================================================
# Depends on install.sh-provided: CACHE, FORCE, UPDATED_TAG, log, write_tool_env

install_lua() {
  local dir="$CACHE/lua"
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/bin/lua" ]; then
    log "Lua already installed (skip download)"
  else
    [ "$FORCE" -eq 1 ] && rm -rf "$dir"
    mkdir -p "$dir"
    log "Downloading and compiling Lua (install to $dir)..."
    LUA_VER="5.4.7"
    # Primary source is www.lua.org; fall back to the GitHub mirror (same tree, `make` compatible)
    # because some environments (e.g. GitHub Actions runners) cannot reach www.lua.org.
    if ! curl -fsSL "https://www.lua.org/ftp/lua-${LUA_VER}.tar.gz" -o /tmp/lua.tar.gz 2>/dev/null; then
      log "www.lua.org unreachable, falling back to GitHub mirror"
      curl -fsSL "https://github.com/lua/lua/archive/refs/tags/v${LUA_VER}.tar.gz" -o /tmp/lua.tar.gz
      # GitHub tarball tops out at lua-<ver>/ as well, so the same dir is used below.
    fi
    tar -C /tmp -xzf /tmp/lua.tar.gz
    ( cd "/tmp/lua-${LUA_VER}" && make linux MYCFLAGS="-O2" && make install INSTALL_TOP="$dir" >/dev/null 2>&1 )
    rm -rf "/tmp/lua-${LUA_VER}" /tmp/lua.tar.gz
    log "Lua $LUA_VER installed${UPDATED_TAG}"
  fi
  write_tool_env "$dir" \
    "PATH=$dir/bin:\$PATH"
}