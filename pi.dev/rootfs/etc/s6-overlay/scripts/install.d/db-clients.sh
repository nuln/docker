#!/usr/bin/env bash
# =============================================================================
# install.d/db-clients.sh — database & storage CLI clients (loaded by install.sh)
#   desc: DB/storage clients: mysql postgres redis sqlite3 minio-mc (apt + binaries)
#   tool: db-clients
#   fn:   install_db_clients
#   usage: install.sh db-clients [--update]
# =============================================================================
# NOT installed by default — run `install.sh db-clients` to install.
# Depends on install.sh-provided: CACHE, FORCE, log, write_tool_env

install_db_clients() {
  local dir="$CACHE/db-clients"

  if [ "$FORCE" -eq 0 ] && [ -x "$dir/bin/mc" ] && command -v mysql >/dev/null 2>&1; then
    log "DB clients already installed (skip)"
  else
    [ "$FORCE" -eq 1 ] && rm -rf "$dir"
    mkdir -p "$dir/bin"

    log "Installing MySQL client + PostgreSQL client + redis via apt..."
    DEBIAN_FRONTEND=noninteractive apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      default-mysql-client postgresql-client redis-tools sqlite3 ca-certificates
    rm -rf /var/lib/apt/lists/*

    log "Installing MinIO client (mc) to $dir/bin..."
    curl -fsSL "https://dl.min.io/client/mc/release/linux-${GO_ARCH}/mc" -o "$dir/bin/mc"
    chmod +x "$dir/bin/mc"

    log "DB clients installed${UPDATED_TAG}"
  fi

  write_tool_env "$dir" \
    "PATH=$dir/bin:\$PATH"
}