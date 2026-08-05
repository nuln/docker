#!/usr/bin/env bash
# =============================================================================
# install.d/setup-bash-env.sh — BASH_ENV bootstrap (loaded by install.sh)
#   desc: build-time only — write /etc/pi-env.sh sourcing each tool's env.sh
#   tool: setup-bash-env
#   fn:   install_setup_bash_env
#   usage: install.sh setup-bash-env        (must run as root, build-time)
#
# This pi version runs commands via `bash -c` (no -l). Empirically it does not read
# ~/.profile or /etc/profile.d. For non-interactive shells, bash reads the file pointed
# to by $BASH_ENV. So we write /etc/pi-env.sh that sources each tool's env.sh, and the
# Dockerfile sets ENV BASH_ENV=/etc/pi-env.sh. This replaces the old approach of
# renaming/wrapping /usr/bin/bash — no system bash tampering needed.
# =============================================================================
# Depends on install.sh-provided: CACHE, log

install_setup_bash_env() {
  cat > /etc/pi-env.sh <<EOF
for __f in ${CACHE}/*/env.sh; do [ -r "\$__f" ] && . "\$__f"; done
EOF
  chmod 644 /etc/pi-env.sh
  log "BASH_ENV bootstrap ready (/etc/pi-env.sh sources ${CACHE}/*/env.sh)"
}