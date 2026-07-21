#!/bin/bash
set -euo pipefail

case "${1:-}" in
  lunel-manager)
    shift
    cd /app/manager

    DB_PATH="${MANAGER_DB_PATH:-manager.db}"

    # Start Manager in background, seed proxy passwords, then bring to foreground
    if [ -n "${PROXIES:-}" ] && [ -n "${PROXY_PASSWORD:-}" ]; then
      mkdir -p "$(dirname "$DB_PATH")"

      # Start Manager in background
      bun run src/index.ts "$@" &
      MANAGER_PID=$!

      # Wait for Manager to be healthy
      for i in $(seq 1 30); do
        if [ -f "$DB_PATH" ] && curl -sf http://localhost:${PORT:-8899}/health >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      # Seed each proxy password directly via SQLite (Manager has already created the schema)
      IFS=',' read -ra PROXY_LIST <<< "$PROXIES"
      for proxy_url in "${PROXY_LIST[@]}"; do
        proxy_url="$(echo "$proxy_url" | xargs)"
        echo "[entrypoint] seeding proxy password for: $proxy_url"
        bun -e "
          const { Database } = require('bun:sqlite');
          const db = new Database('$DB_PATH');
          db.run('INSERT OR REPLACE INTO proxies (url, password, state, state_source) VALUES (?, ?, \"active\", \"manual\")', ['$proxy_url', '$PROXY_PASSWORD']);
          console.log('seeded:', '$proxy_url');
        " 2>&1 || echo "[entrypoint] warning: failed to seed $proxy_url"
      done

      # Notify Manager to reload (trigger ring update)
      curl -sf "http://localhost:${PORT:-8899}/v1/admin/proxy-state?password=${MANAGER_ADMIN_PASSWORD}" \
        -X POST -H "Content-Type: application/json" \
        -d "{\"url\":\"${PROXY_LIST[0]}\",\"state\":\"active\"}" \
        >/dev/null 2>&1 || true

      wait $MANAGER_PID
    else
      exec bun run src/index.ts "$@"
    fi
    ;;
  lunel-proxy)
    shift
    cd /app/proxy
    # 内部 Docker 网络允许 HTTP（生产环境应使用 HTTPS）
    export MANAGER_URL=${MANAGER_URL:-}
    export PUBLIC_URL=${PUBLIC_URL:-}
    exec bun run src/index.ts "$@"
    ;;
  *)
    exec "$@"
    ;;
esac
