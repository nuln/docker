#!/usr/bin/env bash
# =============================================================================
# install.d/kotlin.sh — Kotlin (kotlin-compiler) installer (loaded by install.sh)
#   desc: Kotlin (kotlin-compiler single archive; auto-installs the JDK first)
#   tool: kotlin
#   fn:   install_kotlin
#   usage: install.sh kotlin [--update]
# =============================================================================
# Depends on install.sh-provided: CACHE, FORCE, UPDATED_TAG, log, write_tool_env, install_java

install_kotlin() {
  if [ ! -x "$CACHE/jdk/bin/java" ]; then
    log "Kotlin depends on Java; cache/jdk/bin/java not found, installing Java first..."
    install_java
  fi
  local dir="$CACHE/kotlin"
  local ver="${KOTLIN_VERSION:-2.4.10}"
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/kotlinc/bin/kotlin" ]; then
    log "Kotlin already installed (skip download)"
  else
    [ "$FORCE" -eq 1 ] && rm -rf "$dir"
    mkdir -p "$dir"
    log "Downloading and installing Kotlin ${ver} (extract to $dir)..."
    TMP="/tmp/kotlin-${ver}.zip"
    curl -fsSL "https://github.com/JetBrains/kotlin/releases/download/v${ver}/kotlin-compiler-${ver}.zip" -o "$TMP"
    ( cd "$dir" && unzip -oq "$TMP" )
    rm -f "$TMP"
    # The zip's top-level dir name is not fixed (e.g. kotlinc/); its bin/kotlin must keep lib alongside,
    # so rename that dir to kotlinc under $dir/kotlinc, and point PATH to its bin.
    local top
    top="$(find "$dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)"
    if [ -n "$top" ] && [ "$(basename "$top")" != kotlinc ]; then
      rm -rf "$dir/kotlinc"
      mv "$top" "$dir/kotlinc"
    fi
    log "Kotlin $ver installed${UPDATED_TAG}"
  fi
  write_tool_env "$dir" \
    "PATH=$dir/kotlinc/bin:\$PATH"
}