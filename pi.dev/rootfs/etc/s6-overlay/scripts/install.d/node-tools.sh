#!/usr/bin/env bash
# =============================================================================
# install.d/node-tools.sh — Node global tools installer (loaded by install.sh)
#   desc: TypeScript & other npm global tools (Node itself from the base image)
#   tool: node-tools | ts
#   fn:   install_node_tools
#   usage: install.sh node-tools [--update]
# =============================================================================
# Depends on install.sh-provided: CACHE, FORCE, UPDATED_TAG, log, write_tool_env

install_node_tools() {
  local dir="$CACHE/npm-global"
  local ver="${TYPESCRIPT_VERSION:-7.0.2}"
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/bin/tsc" ]; then
    log "TypeScript already installed (skip download)"
  else
    mkdir -p "$dir"
    log "Installing TypeScript ${ver} (npm --prefix $dir)..."
    npm i -g --prefix "$dir" "typescript@${ver}"
    log "TypeScript ${ver} installed${UPDATED_TAG}"
  fi
  write_tool_env "$dir" \
    "npm_config_cache=$CACHE/npm" \
    "npm_config_prefix=$dir" \
    "PATH=$dir/bin:\$PATH"
}