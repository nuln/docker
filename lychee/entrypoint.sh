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

# 默认把原图与预览图分到不同目录 / 磁盘（镜像核心能力，无需开关）。
#   LYCHEE_ORIGINALS_DIR 默认 /data/originals（原图 / 大图：HDD）
#   LYCHEE_PREVIEWS_DIR  默认 /data/previews（缩略图 / 小图：SSD）
# Lychee 的 images 磁盘根是 public/uploads，镜像把其中的 <变体> 子目录
# 变为指向上述目录的软链，Lychee 本身无感，升级 Lychee 也不受影响。
ORIGINALS_DIR="${LYCHEE_ORIGINALS_DIR:-/data/originals}"
PREVIEWS_DIR="${LYCHEE_PREVIEWS_DIR:-/data/previews}"
PHOTOS_DIR="/app/public/uploads"

mkdir -p "$ORIGINALS_DIR" "$PREVIEWS_DIR"
# 原图 / 大图变体 → ORIGINALS_DIR（HDD）
for v in original medium medium2x; do
  rm -rf "$PHOTOS_DIR/$v"
  mkdir -p "$ORIGINALS_DIR/$v"
  ln -sfn "$ORIGINALS_DIR/$v" "$PHOTOS_DIR/$v"
done
# 预览 / 缩略图变体 → PREVIEWS_DIR（SSD）
for v in thumb small small2x thumb2x; do
  rm -rf "$PHOTOS_DIR/$v"
  mkdir -p "$PREVIEWS_DIR/$v"
  ln -sfn "$PREVIEWS_DIR/$v" "$PHOTOS_DIR/$v"
done

exec /usr/local/bin/entrypoint.sh "$@"
