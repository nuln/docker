#!/bin/bash

CONFIG_DIR="${CONFIG_DIR:-/config}"
APP_KEY_FILE="$CONFIG_DIR/APP_KEY"

if [ ! -f "$APP_KEY_FILE" ]; then
  APP_KEY="base64:$(php -r 'echo base64_encode(random_bytes(32));')"
  mkdir -p "$CONFIG_DIR"
  echo -n "$APP_KEY" > "$APP_KEY_FILE"
fi

APP_KEY="$(cat "$APP_KEY_FILE")"
export APP_KEY

if [ -f /app/.env ]; then
  grep -q "^APP_KEY=" /app/.env || echo "APP_KEY=$APP_KEY" >> /app/.env
else
  echo "APP_KEY=$APP_KEY" > /app/.env
fi

# 信任反向代理：让 Laravel 读取 X-Forwarded-Proto/-Host，生成 https:// 与 secure cookie。
# 默认信任所有直连代理（*），可用容器环境变量 TRUSTED_PROXIES 覆盖（如具体网段 172.16.0.0/12）。
TRUSTED_PROXIES_VAL="${TRUSTED_PROXIES:-*}"
if ! grep -q "^TRUSTED_PROXIES=" /app/.env; then
  echo "TRUSTED_PROXIES=$TRUSTED_PROXIES_VAL" >> /app/.env
fi

exec /usr/local/bin/entrypoint.sh "$@"
