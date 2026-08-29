FROM ghcr.io/lycheeorg/lychee:v7.7.5

ENV APP_DIR=/lychee \
    DB_CONNECTION=sqlite \
    DB_DATABASE=/config/lychee.sqlite \
    PHP_MEMORY_LIMIT=1G

COPY dynamic.php /app/app/Http/Middleware/DynamicBaseUrl.php
COPY provider.php /app/app/Providers/Provider.php
COPY entrypoint.sh /docker-entrypoint-custom.sh

# 原生注入（不依赖 Kernel.php / bootstrap/app.php 结构，升级更通用）：
# 1) 把两个新类加入 Composer classmap（镜像用 classmap-authoritative，需显式登记才能自动加载）
# 2) 把服务提供者追加进 config/app.php 的 providers 数组（Laravel 原生注册点）
# 3) FrankenPHP worker 脚本由 octane:install 生成（替代手动 bake）
RUN chmod +x /docker-entrypoint-custom.sh \
    && php -r '$cm="/app/vendor/composer/autoload_classmap.php";$m=require $cm;$a=["App\\Http\\Middleware\\DynamicBaseUrl"=>"/app/app/Http/Middleware/DynamicBaseUrl.php","App\\Providers\\Provider"=>"/app/app/Providers/Provider.php"];foreach($a as $k=>$v){if(!isset($m[$k]))$m[$k]=$v;}file_put_contents($cm,"<?php\n\nreturn ".var_export($m,true).";\n");' \
    && php -r '$f="/app/config/app.php";$s=file_get_contents($f);$m="\x27providers\x27 => [";if(strpos($s,$m)!==false&&strpos($s,"App\\Providers\\Provider")===false){$s=str_replace($m,$m."\n        App\\Providers\\Provider::class,",$s);file_put_contents($f,$s);}' \
    && APP_KEY="base64:$(php -r 'echo base64_encode(random_bytes(32));')" php artisan octane:install --server=frankenphp

EXPOSE 8000

ENTRYPOINT ["/docker-entrypoint-custom.sh"]
CMD ["php", "artisan", "octane:start", "--server=frankenphp", "--host=0.0.0.0", "--port=8000"]
