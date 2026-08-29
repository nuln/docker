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

exec /usr/local/bin/entrypoint.sh "$@"
