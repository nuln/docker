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
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/bin/java" ]; then
    log "Java already installed (skip download)"
  else
    [ "$FORCE" -eq 1 ] && rm -rf "$dir"
    mkdir -p "$dir"
    log "Downloading and installing Java (Temurin JDK, extract to $dir)..."
    # Get the latest feature release version (API returns it; read from file to avoid SIGPIPE)
    curl -fsSL 'https://api.adoptium.net/v3/info/available_releases' -o /tmp/java-rel.json
    JAVA_VER="$(awk -F'"' '/most_recent_feature_release/{gsub(/[^0-9]/,"",$3); print $3; exit}' /tmp/java-rel.json)"
    rm -f /tmp/java-rel.json
    # Pick the archive per architecture: x64/aarch64
    case "$GO_ARCH" in amd64) JAVA_ARCH=x64 ;; arm64) JAVA_ARCH=aarch64 ;; *) JAVA_ARCH="$GO_ARCH" ;; esac
    local api="https://api.adoptium.net/v3/binary/latest/${JAVA_VER}/ga/linux/${JAVA_ARCH}/jdk/hotspot/normal/eclipse"
    TMP="/tmp/jdk-${JAVA_VER}.linux-${JAVA_ARCH}.tar.gz"
    curl -fsSL -L "$api" -o "$TMP"
    tar -C "$dir" -xzf "$TMP" --strip-components=1
    rm -f "$TMP"
    log "Java (JDK $JAVA_VER) installed${UPDATED_TAG}"
  fi
  write_tool_env "$dir" \
    "JAVA_HOME=$dir" \
    "PATH=$dir/bin:\$PATH"
}