#!/bin/bash
set -e

APP_ROOT="/app"
BOOTSTRAP="$APP_ROOT/bootstrap/app.php"
KERNEL="$APP_ROOT/app/Http/Kernel.php"
MIDDLEWARE="$APP_ROOT/app/Http/Middleware/DynamicBaseUrl.php"

if [ ! -f "$MIDDLEWARE" ]; then
    echo "DynamicBaseUrl middleware not found at $MIDDLEWARE"
    exit 1
fi

require_in_bootstrap() {
    if [ -f "$BOOTSTRAP" ] && ! grep -q "DynamicBaseUrl.php" "$BOOTSTRAP"; then
        sed -i "1a require_once __DIR__.'/../app/Http/Middleware/DynamicBaseUrl.php';" "$BOOTSTRAP"
        echo "Required DynamicBaseUrl in bootstrap/app.php"
    fi
}

register_global_middleware() {
    if [ -f "$KERNEL" ] && grep -q "protected \$middleware = \[" "$KERNEL"; then
        if ! grep -q "DynamicBaseUrl::class" "$KERNEL"; then
            printf '\t\t\\App\\Http\\Middleware\\DynamicBaseUrl::class,\n' > /tmp/mwline.txt
            sed -i "/protected \$middleware = \[/r /tmp/mwline.txt" "$KERNEL"
            rm -f /tmp/mwline.txt
        fi
        echo "Registered DynamicBaseUrl at the top of the global middleware stack"
        return 0
    fi
    return 1
}

require_in_bootstrap
register_global_middleware || echo "WARNING: could not register global middleware; add App\\Http\\Middleware\\DynamicBaseUrl manually."

if command -v composer >/dev/null 2>&1; then
    composer dump-autoload -o >/dev/null 2>&1 || composer dump-autoload >/dev/null 2>&1 || true
fi

echo "patch.sh done"
