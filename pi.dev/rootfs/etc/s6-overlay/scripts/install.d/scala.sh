#!/usr/bin/env bash
# =============================================================================
# install.d/scala.sh — Scala (scala-cli) installer (loaded by install.sh)
#   desc: Scala (scala-cli single binary; auto-installs the JDK first)
#   tool: scala
#   fn:   install_scala
#   usage: install.sh scala [--update]
# =============================================================================
# Depends on install.sh-provided: CACHE, GO_ARCH, FORCE, UPDATED_TAG, log, write_tool_env, install_java

install_scala() {
  if [ ! -x "$CACHE/jdk/bin/java" ]; then
    log "Scala depends on Java; cache/jdk/bin/java not found, installing Java first..."
    install_java
  fi
  local dir="$CACHE/scala"
  local ver="${SCALA_CLI_VERSION:-1.16.0}"
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/bin/scala-cli" ]; then
    log "Scala (scala-cli) already installed (skip download)"
  else
    [ "$FORCE" -eq 1 ] && rm -rf "$dir"
    mkdir -p "$dir/bin"
    log "Downloading and installing Scala (scala-cli ${ver}, install to $dir)..."
    SCALA_ARCH="$GO_ARCH"; [ "$SCALA_ARCH" = arm64 ] && SCALA_ARCH=aarch64; [ "$SCALA_ARCH" = amd64 ] && SCALA_ARCH=x86_64
    curl -fsSL "https://github.com/VirtusLab/scala-cli/releases/download/v${ver}/scala-cli-${SCALA_ARCH}-pc-linux.gz" -o /tmp/scala-cli.gz
    gzip -dc /tmp/scala-cli.gz > "$dir/bin/scala-cli"
    chmod +x "$dir/bin/scala-cli"
    rm -f /tmp/scala-cli.gz
    log "Scala (scala-cli ${ver}) installed${UPDATED_TAG}"
  fi
  write_tool_env "$dir" \
    "PATH=$dir/bin:\$PATH"
}