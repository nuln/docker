#!/usr/bin/env bash
# =============================================================================
# install.d/php.sh — PHP installer (official source build, minimal CLI, loaded by install.sh)
#   desc: PHP official source build, minimal CLI (--disable-all --enable-cli)
#   tool: php
#   fn:   install_php
#   usage: install.sh php [--update]
# =============================================================================
# Default --disable-all --enable-cli (zero system-lib dependency, compiles on amd64/arm64).
# For extensions, reinstall and add --enable-xxx to ./configure (the matching -dev lib needs root apt install).
# Depends on install.sh-provided: CACHE, FORCE, UPDATED_TAG, log, write_tool_env

install_php() {
  local dir="$CACHE/php"
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/bin/php" ]; then
    log "PHP already installed (skip download)"
  else
    [ "$FORCE" -eq 1 ] && rm -rf "$dir"
    mkdir -p "$dir"
    log "Downloading and compiling PHP (official source, minimal CLI, install to $dir)..."
    # Get the latest stable version (official releases API; read from file to avoid SIGPIPE).
    # Parse with posix awk match/substr (works on both mawk and gawk) to extract the
    # major.minor.patch triplet, so the php-<ver>.tar.gz URL below is always well-formed.
    curl -fsSL 'https://www.php.net/releases/index.php?json' -o /tmp/php-rel.json 2>/dev/null \
      || curl -fsSL 'https://www.php.net/releases/active.php' -o /tmp/php-rel.json 2>/dev/null
    PHP_VER="$(awk -F'"' '/"version":/{v=$4; if (match(v, /^[0-9]+\.[0-9]+\.[0-9]+/)) {print substr(v, RSTART, RLENGTH); exit}}' /tmp/php-rel.json 2>/dev/null)"
    rm -f /tmp/php-rel.json
    # Fallback if the API is unreachable / payload changed shape
    if [ -z "$PHP_VER" ]; then
      PHP_VER="8.4.10"
      log "Could not resolve latest PHP from the API; falling back to $PHP_VER"
    fi
    curl -fsSL "https://www.php.net/distributions/php-${PHP_VER}.tar.gz" -o /tmp/php.tar.gz
    tar -C /tmp -xzf /tmp/php.tar.gz
    # Build with a small fixed job count (-j2): it matches the conservative default MAKEFLAGS
    # in docker-compose.yml and avoids relying on nproc, which reports the HOST core count
    # (e.g. 14) inside the container, not the compose cpus: limit. On a weak NAS this would
    # otherwise oversubscribe the CPUs during compilation.
    ( cd "/tmp/php-${PHP_VER}" \
      && ./configure --prefix="$dir" --disable-all --enable-cli \
      && make -j2 \
      && make install )
    rm -rf "/tmp/php-${PHP_VER}" /tmp/php.tar.gz
    log "PHP $PHP_VER installed (minimal CLI; for extensions reinstall and add --enable-xxx)${UPDATED_TAG}"
  fi
  write_tool_env "$dir" \
    "PATH=$dir/bin:\$PATH"
}