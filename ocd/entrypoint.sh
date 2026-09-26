#!/bin/bash
set -eo pipefail

HOME_DIR="/home/ocd"
CONFIG_DIR="${HOME_DIR}/.config/open-compute"
DATA_DIR="${HOME_DIR}/.local/share/open-compute"
SECRETS_DIR="${DATA_DIR}/secrets"
CONFIG_FILE="${CONFIG_DIR}/config.toml"

PUBLIC_BIND="${OCD_PUBLIC_BIND:-${OPEN_COMPUTE_PUBLIC_BIND:-0.0.0.0:8787}}"
ADMIN_TOKEN="${OCD_ADMIN_TOKEN:-${OPEN_COMPUTE_ADMIN_TOKEN:-}}"
DEPLOYER_TOKEN="${OCD_DEPLOYER_TOKEN:-${OPEN_COMPUTE_DEPLOYER_TOKEN:-}}"
READ_ONLY_TOKEN="${OCD_READ_ONLY_TOKEN:-${OPEN_COMPUTE_READ_ONLY_TOKEN:-}}"

# Ensure base directories exist and set appropriate permissions
mkdir -p "${CONFIG_DIR}" "${DATA_DIR}" "${HOME_DIR}/.local/state/open-compute"
if [ "$(id -u)" = "0" ]; then
  chown -R ocd:ocd "${HOME_DIR}"
  chmod 700 "${HOME_DIR}" "${CONFIG_DIR}" "${DATA_DIR}"
fi

# Helper function to run commands as ocd user
run_as_ocd() {
  if [ "$(id -u)" = "0" ]; then
    runuser -u ocd -- "$@"
  else
    "$@"
  fi
}

# 1. Initialize configuration and secrets if not already created
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "==> First startup detected: initializing open-compute instance..."
  run_as_ocd ocd setup --yes || true
  pkill -9 ocd 2>/dev/null || true
  sleep 1

  if [ -f "${CONFIG_FILE}" ]; then
    echo "==> Configuring public bind: ${PUBLIC_BIND}"
    sed -i "s|public_bind = .*|public_bind = \"${PUBLIC_BIND}\"|" "${CONFIG_FILE}"
  fi
fi

# 2. Apply custom secret tokens if supplied via environment variables
if [ -d "${SECRETS_DIR}" ]; then
  if [ -n "${ADMIN_TOKEN}" ]; then
    printf '%s' "${ADMIN_TOKEN}" > "${SECRETS_DIR}/admin.token"
    chmod 600 "${SECRETS_DIR}/admin.token"
    chown ocd:ocd "${SECRETS_DIR}/admin.token" 2>/dev/null || true
  fi
  if [ -n "${DEPLOYER_TOKEN}" ]; then
    printf '%s' "${DEPLOYER_TOKEN}" > "${SECRETS_DIR}/deployer.token"
    chmod 600 "${SECRETS_DIR}/deployer.token"
    chown ocd:ocd "${SECRETS_DIR}/deployer.token" 2>/dev/null || true
  fi
  if [ -n "${READ_ONLY_TOKEN}" ]; then
    printf '%s' "${READ_ONLY_TOKEN}" > "${SECRETS_DIR}/read-only.token"
    chmod 600 "${SECRETS_DIR}/read-only.token"
    chown ocd:ocd "${SECRETS_DIR}/read-only.token" 2>/dev/null || true
  fi

  echo "================================================================="
  echo "  Open Compute daemon (ocd) initialized successfully"
  echo "  - Config: ${CONFIG_FILE}"
  echo "  - Data Directory: ${DATA_DIR}"
  if [ -f "${SECRETS_DIR}/admin.token" ]; then
    echo "  - Admin Token: $(cat "${SECRETS_DIR}/admin.token")"
  fi
  if [ -f "${SECRETS_DIR}/deployer.token" ]; then
    echo "  - Deployer Token: $(cat "${SECRETS_DIR}/deployer.token")"
  fi
  echo "================================================================="
fi

# 3. Launch ocd daemon
if [ "$1" = "ocd" ] && { [ "$#" -eq 1 ] || [ "$2" = "run" ]; }; then
  echo "==> Starting ocd daemon..."
  if [ "$(id -u)" = "0" ]; then
    exec runuser -u ocd -- ocd --config "${CONFIG_FILE}" run
  else
    exec ocd --config "${CONFIG_FILE}" run
  fi
fi

if [ "$(id -u)" = "0" ]; then
  exec runuser -u ocd -- "$@"
else
  exec "$@"
fi
