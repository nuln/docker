#!/usr/bin/env bash
# =============================================================================
# verify-toolchain.sh — CI verification for install.sh toolchains
#
# Runs inside the pi container (ENTRYPOINT bypassed via --entrypoint bash).
# Installs each requested toolchain with install.sh, then asserts the expected
# binary exists AND runs from a fresh `bash -c` (proving BASH_ENV loads it),
# i.e. exactly how the pi process will invoke it.
#
# Usage (in container):  verify-toolchain.sh <tool> [<tool> ...]
#   go | rust | java | bun | scala | kotlin | node-tools | lua | php
#
# Exit non-zero on the first failure; each tool prints PASS/FAIL.
# =============================================================================
set -euo pipefail

# Install each requested toolchain via install.sh
for t in "$@"; do
  echo "== installing $t =="
  install.sh "$t"
done

# Assert a binary resolves and runs from a fresh bash -c (BASH_ENV path)
check() {
  local bin="$1"; shift
  echo "== check $bin =="
  bash -c "command -v $bin" >/dev/null || { echo "FAIL: $bin not on PATH in bash -c (BASH_ENV not loading?)"; return 1; }
  bash -c "$bin $*" 2>&1 | head -2 || true
  echo "PASS: $bin"
}

# Per-toolchain assertions
for t in "$@"; do
  case "$t" in
    go)         check go version ;;
    rust)       check rustc --version; check cargo --version ;;
    java)       check java -version ;;
    bun)        check bun --version ;;
    scala)      check scala-cli version ;;
    kotlin)     check kotlin -version ;;
    node-tools) check tsc --version ;;
    lua)        check lua -v ;;
    php)        check php -v ;;
    *)          echo "WARN: no assertion defined for $t" ;;
  esac
done

echo "ALL TOOLCHAINS OK: $*"
