<?php
declare(strict_types=1);

/**
 * Drive the PHP OIDC login end to end, from inside the instance's own container.
 *
 * Run there rather than from the host so that `127.0.0.1` is the instance and the provider's
 * container name resolves — the same two lookups a browser on the public domain performs. Prints
 * one JSON object on stdout, so the shell test can assert on it without parsing HTML.
 *
 * Usage: php oidc-php-flow.php <base-url> <prefix> [replay]
 *   replay: after a successful login, request the same callback URL again and report its status.
 */

$base = $argv[1] ?? 'http://127.0.0.1';
$prefix = $argv[2] ?? '/rss';
$checkReplay = ($argv[3] ?? '') === 'replay';

$jar = tempnam(sys_get_temp_dir(), 'oidcjar');
@unlink($jar);

/**
 * @param array<string,string> $post
 * @return array{status:int,location:string,body:string}
 */
function request(string $url, string $jar, array $post = []): array {
	$ch = curl_init($url);
	if ($ch === false) {
		return ['status' => 0, 'location' => '', 'body' => ''];
	}
	$options = [
		CURLOPT_RETURNTRANSFER => true,
		CURLOPT_HEADER => true,
		CURLOPT_FOLLOWLOCATION => false,
		CURLOPT_COOKIEJAR => $jar,
		CURLOPT_COOKIEFILE => $jar,
		CURLOPT_TIMEOUT => 25,
		CURLOPT_CONNECTTIMEOUT => 5,
	];
	if ($post !== []) {
		$options[CURLOPT_POST] = true;
		$options[CURLOPT_POSTFIELDS] = http_build_query($post);
	}
	curl_setopt_array($ch, $options);
	$raw = curl_exec($ch);
	$info = curl_getinfo($ch);
	curl_close($ch);
	if (!is_string($raw)) {
		return ['status' => 0, 'location' => '', 'body' => ''];
	}
	preg_match('/^Location:\s*(.+)$/mi', $raw, $match);
	return [
		'status' => (int)$info['http_code'],
		'location' => trim($match[1] ?? ''),
		'body' => (string)substr($raw, (int)$info['header_size']),
	];
}

$result = [
	'signin_page' => false,
	'authorize_status' => 0,
	'authorize_location' => '',
	'callback_status' => 0,
	'logged_in' => false,
	'replay_status' => 0,
	'logout_status' => 0,
	'logout_location' => '',
	'session_after_logout' => true,
];

// 1. The login page offers the provider, and offers no password form (that would be a second way in).
$page = request($base . $prefix . '/i/?c=auth&a=login', $jar);
$result['signin_page'] = str_contains($page['body'], 'Sign in with your identity provider')
	&& !str_contains($page['body'], 'id="passwordPlain"');

// 2. Starting the flow answers with a redirect to the provider, carrying PKCE and state.
$start = request($base . $prefix . '/i/?c=auth&a=oidc&start=1', $jar);
$result['authorize_status'] = $start['status'];
$result['authorize_location'] = $start['location'];

// 3. Provider -> our callback -> session.
$provider = request($start['location'], $jar);
$callback = request($provider['location'], $jar);
$result['callback_status'] = $callback['status'];
$reader = request($base . $prefix . '/i/', $jar);
$result['logged_in'] = str_contains($reader['body'], 'logged_in')
	&& !str_contains($reader['body'], 'Sign in with your identity provider');

// 4. The callback is single-use: `state` is consumed before the token is even exchanged.
if ($checkReplay) {
	$result['replay_status'] = request($provider['location'], $jar)['status'];
}

// 5. Logout ends the local session and, when the provider advertises one, its session too.
preg_match('/name="_csrf" value="([^"]+)"/', $reader['body'], $csrf);
$logout = request($base . $prefix . '/i/?c=auth&a=logout', $jar, ['_csrf' => $csrf[1] ?? '']);
$result['logout_status'] = $logout['status'];
$result['logout_location'] = $logout['location'];
$result['session_after_logout'] = str_contains(request($base . $prefix . '/i/', $jar)['body'], 'logged_in');

echo json_encode($result, JSON_UNESCAPED_SLASHES), "\n";
@unlink($jar);
