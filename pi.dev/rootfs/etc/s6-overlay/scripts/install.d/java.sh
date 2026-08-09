#!/usr/bin/env bash
# =============================================================================
# install.d/java.sh — Java (Adoptium Temurin JDK) installer (loaded by install.sh)
#   desc: Java (Temurin JDK, extracts into $CACHE/jdk, sets JAVA_HOME)
#   tool: java
#   fn:   install_java
#   usage: install.sh java [--update]
# =============================================================================
# Depends on install.sh-provided: CACHE, GO_ARCH, FORCE, UPDATED_TAG, log, write_tool_env

install_java() {
  local dir="$CACHE/jdk"
  local ver="${JAVA_VERSION:-26}"
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/bin/java" ]; then
    log "Java already installed (skip download)"
  else
    [ "$FORCE" -eq 1 ] && rm -rf "$dir"
    mkdir -p "$dir"
    log "Downloading and installing Java (Temurin JDK ${ver}, extract to $dir)..."
    # Pick the archive per architecture: x64/aarch64
    case "$GO_ARCH" in amd64) JAVA_ARCH=x64 ;; arm64) JAVA_ARCH=aarch64 ;; *) JAVA_ARCH="$GO_ARCH" ;; esac
    local api="https://api.adoptium.net/v3/binary/latest/${ver}/ga/linux/${JAVA_ARCH}/jdk/hotspot/normal/eclipse"
    TMP="/tmp/jdk-${ver}.linux-${JAVA_ARCH}.tar.gz"
    curl -fsSL -L "$api" -o "$TMP"
    tar -C "$dir" -xzf "$TMP" --strip-components=1
    rm -f "$TMP"
    log "Java (JDK $ver) installed${UPDATED_TAG}"
  fi
  write_tool_env "$dir" \
    "JAVA_HOME=$dir" \
    "PATH=$dir/bin:\$PATH"
}