<?php
/**
 * A reverse proxy that REMOVES the public sub-directory before forwarding — the behaviour of
 * Caddy's `handle_path` and nginx's `proxy_pass …/`. Used to check what the image does when the
 * prefix is stripped, and to reproduce the login loop reported against a stripping deployment.
 *
 * Path /rss/i/… becomes /i/… before forwarding. Configuration comes from the environment,
 * because PHP's built-in server does not populate $argv for a router script:
 *   PROXY_TARGET      host:port of the FreshRSS container
 *   PROXY_PREFIX      the public sub-directory to strip (default /rss)
 *   PROXY_SEND_PREFIX=1  also send X-Forwarded-Prefix, as a well-behaved proxy would
 */

declare(strict_types=1);

$target = (string)(getenv('PROXY_TARGET') ?: '');
$publicPrefix = rtrim((string)(getenv('PROXY_PREFIX') ?: '/rss'), '/');
$setForwardedPrefix = (getenv('PROXY_SEND_PREFIX') ?: '') === '1';
if ($target === '') {
	http_response_code(500);
	echo 'PROXY_TARGET is not set';
	return;
}

$path = (string)parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
$query = (string)parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_QUERY);

$stripped = $path;
if ($publicPrefix !== '' && str_starts_with($path, $publicPrefix . '/')) {
	$stripped = substr($path, strlen($publicPrefix));
} elseif ($path === $publicPrefix) {
	$stripped = '/';
}
if ($stripped === '') {
	$stripped = '/';
}
$uri = $stripped . ($query !== '' ? '?' . $query : '');

$headers = [];
foreach ($_SERVER as $key => $value) {
	if (str_starts_with($key, 'HTTP_')) {
		$name = str_replace(' ', '-', ucwords(strtolower(str_replace('_', ' ', substr($key, 5)))));
		if ($name !== 'Host') {
			$headers[] = $name . ': ' . $value;
		}
	}
}
$headers[] = 'X-Forwarded-Proto: ' . ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? 'https');
$headers[] = 'X-Forwarded-Host: ' . ($_SERVER['HTTP_HOST'] ?? 'example.com');
if ($setForwardedPrefix) {
	$headers[] = 'X-Forwarded-Prefix: ' . $publicPrefix;
}

$context = stream_context_create(['http' => [
	'method' => $_SERVER['REQUEST_METHOD'] ?? 'GET',
	'header' => implode("\r\n", $headers),
	'content' => file_get_contents('php://input') ?: null,
	'ignore_errors' => true,
	'follow_location' => 0,
	'timeout' => 30,
]]);

$body = @file_get_contents('http://' . $target . $uri, false, $context);
$status = 0;
$responseHeaders = [];
foreach ($http_response_header ?? [] as $line) {
	if (preg_match('#^HTTP/\S+\s+(\d+)#', $line, $m) === 1) {
		$status = (int)$m[1];
		continue;
	}
	$responseHeaders[] = $line;
}

http_response_code($status === 0 ? 502 : $status);
foreach ($responseHeaders as $line) {
	header($line);
}
echo $body === false ? '' : $body;