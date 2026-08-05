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
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/kotlinc/bin/kotlin" ]; then
    log "Kotlin already installed (skip download)"
  else
    [ "$FORCE" -eq 1 ] && rm -rf "$dir"
    mkdir -p "$dir"
    log "Downloading and installing Kotlin (extract to $dir)..."
    curl -fsSL https://api.github.com/repos/JetBrains/kotlin/releases/latest -o /tmp/kotlin-rel.json
    KOTLIN_VER="$(awk -F'"' '/"tag_name":/{gsub(/^v/,"",$4); print $4; exit}' /tmp/kotlin-rel.json)"
    rm -f /tmp/kotlin-rel.json
    TMP="/tmp/kotlin-${KOTLIN_VER}.zip"
    curl -fsSL "https://github.com/JetBrains/kotlin/releases/download/v${KOTLIN_VER}/kotlin-compiler-${KOTLIN_VER}.zip" -o "$TMP"
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
    log "Kotlin $KOTLIN_VER installed${UPDATED_TAG}"
  fi
  write_tool_env "$dir" \
    "PATH=$dir/kotlinc/bin:\$PATH"
}