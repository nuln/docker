<?php
declare(strict_types=1);
// Minimal WebSub hub + reverse proxy, enough to drive FreshRSS through a real subscription.
//
// It answers three roles at once, which is what makes the sub-directory test possible:
//
//   * hub        — `GET|POST /hub` runs the subscription intent and the `hub.mode=verify` round
//                  trip that FreshRSS's `p/api/pshb.php` expects, and `/notify` performs content
//                  distribution by POSTing the feed to the subscriber's callback.
//   * proxy      — every other request is forwarded to the FreshRSS container **with the path
//                  untouched**. That is deliberate: mod_auth_openidc compares `OIDCRedirectURI`
//                  against the path Apache itself serves, so a proxy that strips the prefix makes
//                  OIDC unsolvable. The WebSub callback URL is built from the same public base
//                  URL, so it only resolves if the prefix survives the proxy too.
//   * test probe — `/subs` and `/hub-log` expose the state the assertions read.
//
// `PHP_CLI_SERVER_WORKERS` must be set: the hub calls back into its own proxy while handling
// `/hub`, which a single-process server could not serve.

const LEASE_SECONDS = 86400;

$dir = __DIR__ . '/hub-state';
if (!is_dir($dir)) {
	mkdir($dir, 0o777, true);
}
$subsFile = $dir . '/subs.json';
$logFile = $dir . '/hub.log';
$upstream = rtrim(getenv('FRSS_UPSTREAM') ?: 'http://frss', '/');

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

/** Append one line to the hub log. */
$log = static function (string $line) use ($logFile): void {
	file_put_contents($logFile, gmdate('c') . ' ' . $line . "\n", FILE_APPEND | LOCK_EX);
};

$subs = static function () use ($subsFile): array {
	$raw = json_decode((string)@file_get_contents($subsFile), true);
	return is_array($raw) ? $raw : [];
};
$saveSubs = static function (array $s) use ($subsFile): void {
	file_put_contents($subsFile, json_encode($s, JSON_UNESCAPED_SLASHES), LOCK_EX);
};

/** Minimal HTTP client; the built-in server has no cURL guarantee in every image. */
$fetch = static function (string $url, ?string $body = null, array $headers = []): array {
	$ch = curl_init($url);
	curl_setopt_array($ch, [
		CURLOPT_RETURNTRANSFER => true,
		CURLOPT_FOLLOWLOCATION => true,
		CURLOPT_TIMEOUT => 20,
		CURLOPT_HTTPHEADER => $headers,
	]);
	if ($body !== null) {
		curl_setopt($ch, CURLOPT_POST, true);
		curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
	}
	$out = curl_exec($ch);
	$status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
	$err = curl_error($ch);
	curl_close($ch);
	return ['status' => $status, 'body' => is_string($out) ? $out : '', 'error' => $err];
};

// ---------------------------------------------------------------------------------------------
// Test probes
// ---------------------------------------------------------------------------------------------
if ($path === '/subs') {
	header('Content-Type: application/json');
	echo json_encode($subs(), JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
	exit;
}
if ($path === '/hub-log') {
	header('Content-Type: text/plain; charset=UTF-8');
	echo (string)@file_get_contents($logFile);
	exit;
}

// ---------------------------------------------------------------------------------------------
// Content distribution: POST the topic's current content to every subscriber callback
// ---------------------------------------------------------------------------------------------
if ($path === '/notify') {
	$all = $subs();
	$only = $_REQUEST['topic'] ?? null;
	$results = [];
	foreach ($all as $topic => $sub) {
		if (is_string($only) && $only !== $topic) {
			continue;
		}
		$src = $fetch((string)$topic, null, ['Accept: application/rss+xml']);
		$r = $fetch((string)$sub['callback'], $src['body'], [
			'Content-Type: application/atom+xml',
			'Link: <' . $topic . '>; rel="self", <' . $sub['hub'] . '>; rel="hub"',
		]);
		$results[$topic] = ['status' => $r['status'], 'body' => substr($r['body'], 0, 200), 'error' => $r['error']];
		$log('notify ' . $topic . ' -> ' . $r['status'] . ' ' . trim(substr($r['body'], 0, 80)));
	}
	header('Content-Type: application/json');
	echo json_encode($results, JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
	exit;
}

// ---------------------------------------------------------------------------------------------
// The hub itself
// ---------------------------------------------------------------------------------------------
if ($path === '/hub') {
	// FreshRSS sends the intent as a GET with a form-encoded body; accept both shapes.
	$req = array_merge($_GET, $_POST);
	$mode = (string)($req['hub.mode'] ?? $req['hub_mode'] ?? '');
	$topic = (string)($req['hub.topic'] ?? $req['hub_topic'] ?? '');
	$callback = (string)($req['hub.callback'] ?? $req['hub_callback'] ?? '');
	$verify = (string)($req['hub.verify'] ?? $req['hub_verify'] ?? '');
	$log('hub mode=' . $mode . ' topic=' . $topic . ' callback=' . $callback . ' verify=' . $verify);

	if ($mode === '' || $topic === '' || $callback === '') {
		http_response_code(400);
		header('Content-Type: text/plain');
		echo "missing hub.mode / hub.topic / hub.callback\n";
		exit;
	}

	$challenge = bin2hex(random_bytes(16));
	$all = $subs();
	if ($mode === 'subscribe') {
		$all[$topic] = ['callback' => $callback, 'hub' => self_url($path), 'lease_end' => time() + LEASE_SECONDS,
			'challenge' => $challenge, 'added' => time()];
		$saveSubs($all);
	} elseif ($mode === 'unsubscribe') {
		unset($all[$topic]);
		$saveSubs($all);
	} else {
		http_response_code(400);
		echo "unsupported hub.mode: {$mode}\n";
		exit;
	}

	// Intent accepted, then the mandatory verification round trip. It is issued before answering
	// because a PHP built-in server cannot both answer and serve the nested request itself.
	$sep = str_contains($callback, '?') ? '&' : '?';
	$verifyUrl = $callback . $sep . http_build_query([
		'hub.mode' => 'verify',
		'hub.topic' => $topic,
		'hub.challenge' => $challenge,
		'hub.lease_seconds' => (string)LEASE_SECONDS,
	]);
	$v = $fetch($verifyUrl, null, ['Accept: text/plain']);
	$echoed = trim($v['body']) === $challenge;
	// `p/api/pshb.php` answers 422 to an unsubscribe it did not ask for. A hub tearing a subscription
	// down has no way to tell that from a race, so it completes the unsubscription either way; the
	// normal case is a 2xx that echoes the challenge back.
	$alreadyGone = $mode === 'unsubscribe' && $v['status'] === 422;
	$log('verify ' . $verifyUrl . ' -> ' . $v['status'] . ' echoed=' . ($echoed ? 'yes' : 'no')
		. ($alreadyGone ? ' already-unsubscribed' : '') . ' body=' . substr(trim($v['body']), 0, 80)
		. ' err=' . $v['error']);

	if (!$echoed && !$alreadyGone) {
		http_response_code(404);
		header('Content-Type: text/plain');
		echo "verification failed (status {$v['status']}, error '{$v['error']}')\n";
		exit;
	}

	header('Content-Type: text/plain');
	http_response_code(202);
	echo "{$mode} accepted\n";
	exit;
}

// ---------------------------------------------------------------------------------------------
// Everything else: reverse proxy, path preserved verbatim
// ---------------------------------------------------------------------------------------------
// Feed paths go to the publisher, anything else to FreshRSS. Keeping the topic, the hub and the
// reader application on one hostname is what lets FreshRSS's `isSameHost()` check accept the
// pairing: it is the fallback used when `serverIsPublic()` calls the address private, which is the
// case for any name that only resolves inside a container network.
$publisher = rtrim((string)(getenv('PUBLISHER_UPSTREAM') ?: ''), '/');
$segment = explode('/', $path, 3)[1] ?? '';
$toPublisher = $publisher !== ''
	&& (str_starts_with($segment, 'feed') || in_array($segment, ['publish', 'setself', 'state'], true));
$target = ($toPublisher ? $publisher : $upstream) . ($_SERVER['REQUEST_URI'] ?? '/');
$headers = [];
foreach ($_SERVER as $k => $v) {
	if (str_starts_with($k, 'HTTP_') && !in_array($k, ['HTTP_HOST', 'HTTP_CONNECTION'], true)) {
		$headers[] = str_replace(' ', '-', ucwords(strtolower(str_replace('_', ' ', substr($k, 5))))) . ': ' . $v;
	}
}
$headers[] = 'X-Forwarded-Host: ' . ($_SERVER['HTTP_X_FORWARDED_HOST'] ?? $_SERVER['HTTP_HOST'] ?? 'unknown');
$headers[] = 'X-Forwarded-Proto: http';
$headers[] = 'X-Forwarded-Port: ' . ($_SERVER['SERVER_PORT'] ?? '80');

$body = $method === 'GET' || $method === 'HEAD' ? null : (string)file_get_contents('php://input');
$r = $fetch($target, $body, $headers);
http_response_code($r['status'] ?: 502);
echo $r['body'];

/** Absolute URL of this hub, as advertised to subscribers. */
function self_url(string $path): string {
	$host = $_SERVER['HTTP_X_FORWARDED_HOST'] ?? $_SERVER['HTTP_HOST'] ?? 'localhost';
	$scheme = 'http';
	$port = $_SERVER['SERVER_PORT'] ?? '80';
	$default = $scheme . '://' . $host . (($port === '80' || $port === '443') ? '' : ':' . $port);
	return $default;
}
