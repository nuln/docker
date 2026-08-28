<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Config;
use Illuminate\Support\Facades\URL;
use Symfony\Component\HttpFoundation\Response;

class DynamicBaseUrl
{
    public function handle(Request $request, Closure $next): Response
    {
        $proxiesEnv = (string) env('LYCHEE_TRUSTED_PROXIES', '*');
        $proxies = $proxiesEnv === '*'
            ? [$request->server->get('REMOTE_ADDR')]
            : array_filter(array_map('trim', explode(',', $proxiesEnv)));

        if (count($proxies) > 0) {
            $request->setTrustedProxies(
                $proxies,
                Request::HEADER_X_FORWARDED_FOR
                | Request::HEADER_X_FORWARDED_HOST
                | Request::HEADER_X_FORWARDED_PROTO
                | Request::HEADER_X_FORWARDED_PORT
            );
        }

        $host = rtrim($request->root(), '/');
        $dir = '/' . trim((string) env('APP_DIR', '/lychee'), '/');
        if ($dir === '/') {
            $dir = '';
        }

        $base = $host . $dir;

        URL::forceScheme($request->getScheme());
        URL::forceRootUrl($base);
        Config::set('app.url', $host);
        Config::set('app.dir_url', $dir);
        Config::set('filesystems.disks.images.url', $base . '/uploads');
        Config::set('filesystems.disks.dist.url', $dir . '/dist/');
        Config::set('log-viewer.back_to_system_url', $base . '/gallery');

        return $next($request);
    }
}
