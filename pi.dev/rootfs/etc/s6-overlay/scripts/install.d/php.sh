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
  local ver="${PHP_VERSION:-8.5.9}"
  if [ "$FORCE" -eq 0 ] && [ -x "$dir/bin/php" ]; then
    log "PHP already installed (skip download)"
  else
    [ "$FORCE" -eq 1 ] && rm -rf "$dir"
    mkdir -p "$dir"
    log "Downloading and compiling PHP ${ver} (official source, minimal CLI, install to $dir)..."
    curl -fsSL "https://www.php.net/distributions/php-${ver}.tar.gz" -o /tmp/php.tar.gz
    tar -C /tmp -xzf /tmp/php.tar.gz
    # Build with a small fixed job count (-j2): avoids relying on nproc, which
    # reports the HOST core count (e.g. 14) inside the container, not the
    # compose cpu limit. On a weak NAS this would otherwise oversubscribe the
    # CPUs during compilation.
    ( cd "/tmp/php-${ver}" \
      && ./configure --prefix="$dir" --disable-all --enable-cli \
      && make -j2 \
      && make install )
    rm -rf "/tmp/php-${ver}" /tmp/php.tar.gz
    log "PHP $ver installed (minimal CLI; for extensions reinstall and add --enable-xxx)${UPDATED_TAG}"
  fi
  write_tool_env "$dir" \
    "PATH=$dir/bin:\$PATH"
}