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
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/bin/tsc" ]; then
    log "TypeScript already installed (skip download)"
  else
    mkdir -p "$dir"
    log "Installing TypeScript (npm --prefix $dir)..."
    if [ "$FORCE" -eq 1 ]; then npm i -g --prefix "$dir" typescript@latest; else npm i -g --prefix "$dir" typescript; fi
    log "TypeScript installed${UPDATED_TAG}"
  fi
  write_tool_env "$dir" \
    "npm_config_cache=$CACHE/npm" \
    "npm_config_prefix=$dir" \
    "PATH=$dir/bin:\$PATH"
}