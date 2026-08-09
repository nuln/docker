#!/usr/bin/env bash
# =============================================================================
# install.d/rust.sh — Rust toolchain installer (loaded by install.sh)
#   desc: Rust toolchain (rustup minimal profile; direct install to $CACHE)
#   tool: rust
#   fn:   install_rust
#   usage: install.sh rust [--update]
# =============================================================================
# Depends on install.sh-provided: CACHE, FORCE, UPDATED_TAG, log, write_tool_env

install_rust() {
  local rustup_home="$CACHE/rustup"
  local cargo_home="$CACHE/cargo"
  local ver="${RUST_VERSION:-1.97.1}"
  if [ "$FORCE" -eq 0 ] && [ -x "$cargo_home/bin/cargo" ]; then
    log "Rust already installed (skip download)"
  elif [ "$FORCE" -eq 1 ] && [ -x "$cargo_home/bin/rustup" ]; then
    log "Updating Rust to pinned ${ver} ..."
    if ! RUSTUP_HOME="$rustup_home" CARGO_HOME="$cargo_home" "$cargo_home/bin/rustup" default "${ver}" >/dev/null 2>&1; then
      log "rustup switch to ${ver} failed (continuing with existing toolchain)"
    else
      log "Rust set to ${ver}"
    fi
  else
    mkdir -p "$rustup_home" "$cargo_home"
    log "Downloading and installing Rust ${ver} (directly into $rustup_home / $cargo_home)..."
    # Key: set RUSTUP_HOME/CARGO_HOME first, rustup installs straight into the target dir,
    # without touching ~/.rustup / ~/.cargo and without symlinks.
    export RUSTUP_HOME="$rustup_home"
    export CARGO_HOME="$cargo_home"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh
    RUSTUP_HOME="$rustup_home" CARGO_HOME="$cargo_home" \
      sh /tmp/rustup-init.sh -y --default-toolchain "${ver}" --profile minimal --no-modify-path
    rm -f /tmp/rustup-init.sh
    log "Rust ${ver} installed"
  fi
  write_tool_env "$cargo_home" \
    "RUSTUP_HOME=$rustup_home" \
    "CARGO_HOME=$cargo_home" \
    "PATH=$cargo_home/bin:\$PATH"
}