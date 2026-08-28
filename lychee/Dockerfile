FROM ghcr.io/lycheeorg/lychee:latest

ENV APP_DIR=/lychee \
    DB_CONNECTION=sqlite \
    DB_DATABASE=/config/lychee.sqlite \
    PHP_MEMORY_LIMIT=1G

COPY dynamic_base_url_middleware.php /app/app/Http/Middleware/DynamicBaseUrl.php
COPY frankenphp-worker.php /app/public/frankenphp-worker.php
COPY patch.sh /tmp/patch.sh
COPY docker-entrypoint-custom.sh /docker-entrypoint-custom.sh

RUN chmod +x /tmp/patch.sh /docker-entrypoint-custom.sh \
    && /tmp/patch.sh

EXPOSE 8000

ENTRYPOINT ["/docker-entrypoint-custom.sh"]
CMD ["php", "artisan", "octane:start", "--server=frankenphp", "--host=0.0.0.0", "--port=8000"]
