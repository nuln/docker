<?php
declare(strict_types=1);
// Mock OpenID Connect Provider, complete enough for a real authorisation-code login:
//   - discovery document, JWKS, /authorize, /token, /userinfo
//   - RS256-signed id_token (RSA key pair generated on first boot)
//
// This is what lets the test drive mod_auth_openidc all the way to an authenticated session,
// instead of only checking the first redirect.
//
// /authorize records the parameters it was called with, so a test can assert on the redirect_uri
// FreshRSS advertised, and /last records the last completed exchange.

const ISSUER_HOST = 'idp';
const ISSUER_PORT = 9500;
const ISSUER = 'http://' . ISSUER_HOST . ':' . ISSUER_PORT;

$dir = __DIR__ . '/idp-state';
$keyFile = $dir . '/rsa.pem';
$codesFile = $dir . '/codes.json';
$lastFile = $dir . '/last.json';

if (!is_dir($dir)) {
	mkdir($dir, 0o777, true);
}
if (!is_file($keyFile)) {
	$res = openssl_pkey_new(['private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA]);
	openssl_pkey_export($res, $pem);
	file_put_contents($keyFile, $pem);
}
$privateKey = file_get_contents($keyFile);

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
parse_str((string)(parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_QUERY) ?? ''), $q);

$json = static function (mixed $data, int $code = 200): never {
	http_response_code($code);
	header('Content-Type: application/json');
	echo json_encode($data, JSON_UNESCAPED_SLASHES);
	exit;
};

// ---- discovery -------------------------------------------------------------------------------
if ($path === '/.well-known/openid-configuration') {
	$json([
		'issuer' => ISSUER,
		'authorization_endpoint' => ISSUER . '/authorize',
		'token_endpoint' => ISSUER . '/token',
		'jwks_uri' => ISSUER . '/jwks',
		'userinfo_endpoint' => ISSUER . '/userinfo',
		'end_session_endpoint' => ISSUER . '/logout',
		'response_types_supported' => ['code'],
		'subject_types_supported' => ['public'],
		'id_token_signing_alg_values_supported' => ['RS256'],
		'scopes_supported' => ['openid', 'profile', 'email'],
		'token_endpoint_auth_methods_supported' => ['client_secret_post', 'client_secret_basic'],
		'claims_supported' => ['sub', 'preferred_username', 'email', 'name'],
	]);
}

/** base64url without padding */
$b64 = static fn(string $raw): string => rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');

/** Build and RS256-sign an id_token for the given claims. */
$idToken = static function (array $claims) use ($privateKey, $b64): string {
	$signingInput = $b64(json_encode(['alg' => 'RS256', 'typ' => 'JWT', 'kid' => 'k1'], JSON_UNESCAPED_SLASHES))
		. '.' . $b64(json_encode($claims, JSON_UNESCAPED_SLASHES));
	openssl_sign($signingInput, $signature, $privateKey, OPENSSL_ALGO_SHA256);
	return $signingInput . '.' . $b64($signature);
};

// ---- JWKS ------------------------------------------------------------------------------------
if ($path === '/jwks') {
	$details = openssl_pkey_get_details(openssl_pkey_get_private($privateKey));
	$json(['keys' => [[
		'kty' => 'RSA', 'use' => 'sig', 'alg' => 'RS256', 'kid' => 'k1',
		'n' => $b64($details['rsa']['n']),
		'e' => $b64($details['rsa']['e']),
	]]]);
}

// ---- /last: what the last exchange looked like (assertion helper) ---------------------------
if ($path === '/token-log') {
	header('Content-Type: text/plain');
	echo (string)@file_get_contents($dir . '/token-requests.log');
	exit;
}

if ($path === '/last') {
	header('Content-Type: application/json');
	echo is_file($lastFile) ? (string)file_get_contents($lastFile) : '{}';
	exit;
}

// ---- /authorize ------------------------------------------------------------------------------
if ($path === '/authorize') {
	$redirect = (string)($q['redirect_uri'] ?? '');
	$state = (string)($q['state'] ?? '');
	if ($redirect === '') {
		http_response_code(400);
		echo 'missing redirect_uri';
		exit;
	}
	$code = bin2hex(random_bytes(16));
	$codes = is_file($codesFile) ? (json_decode((string)file_get_contents($codesFile), true) ?: []) : [];
	$codes[$code] = [
		'nonce' => (string)($q['nonce'] ?? ''),
		'redirect_uri' => $redirect,
		'scope' => (string)($q['scope'] ?? ''),
		'state' => $state,
		'time' => time(),
	];
	file_put_contents($codesFile, json_encode($codes));

	$sep = str_contains($redirect, '?') ? '&' : '?';
	header('Location: ' . $redirect . $sep . http_build_query(['code' => $code, 'state' => $state]));
	http_response_code(302);
	exit;
}

// ---- /token ----------------------------------------------------------------------------------
if ($path === '/token') {
	// mod_auth_openidc may authenticate the client with HTTP Basic (client_secret_basic) or with
	// form fields (client_secret_post); accept both, as a real provider does.
	$post = $_POST;
	if (!isset($post['client_id']) && isset($_SERVER['PHP_AUTH_USER'])) {
		$post['client_id'] = $_SERVER['PHP_AUTH_USER'];
	}
	if (!isset($post['client_secret']) && isset($_SERVER['PHP_AUTH_PW'])) {
		$post['client_secret'] = $_SERVER['PHP_AUTH_PW'];
	}
	// Record the exchange even when it is about to be refused, so a test can tell "never called"
	// from "called and rejected".
	file_put_contents($dir . '/token-requests.log',
		json_encode(['grant_type' => $post['grant_type'] ?? null,
			'client_id' => $post['client_id'] ?? null,
			'code' => $post['code'] ?? null,
			'redirect_uri' => $post['redirect_uri'] ?? null,
			'auth' => isset($_SERVER['PHP_AUTH_USER']) ? 'basic' : 'post',
		], JSON_UNESCAPED_SLASHES) . "\n", FILE_APPEND);
	if (($post['grant_type'] ?? '') !== 'authorization_code') {
		$json(['error' => 'unsupported_grant_type'], 400);
	}
	$codes = json_decode((string)@file_get_contents($codesFile), true) ?: [];
	$code = (string)($post['code'] ?? '');
	if (!isset($codes[$code])) {
		$json(['error' => 'invalid_grant'], 400);
	}
	$entry = $codes[$code];
	unset($codes[$code]);	// single use, like a real provider
	file_put_contents($codesFile, json_encode($codes));

	$now = time();
	$claims = [
		'iss' => ISSUER,
		'aud' => (string)($post['client_id'] ?? 'freshrss'),
		'sub' => 'mock-subject-1',
		'exp' => $now + 3600,
		'iat' => $now,
		'auth_time' => $now,
		'nonce' => $entry['nonce'],
		'preferred_username' => (string)(getenv('OIDC_MOCK_USER') ?: 'alice'),
		'email' => 'alice@example.invalid',
		'email_verified' => true,
		'name' => 'Mock OIDC User',
	];
	file_put_contents($lastFile, json_encode([
		'code' => $code,
		'client_id' => $post['client_id'] ?? null,
		'redirect_uri' => $entry['redirect_uri'] ?? null,
		'nonce' => $entry['nonce'] ?? null,
		'claims' => $claims,
	], JSON_UNESCAPED_SLASHES));

	$json([
		'access_token' => 'mock-access-token',
		'token_type' => 'Bearer',
		'expires_in' => 3600,
		'id_token' => $idToken($claims),
		'scope' => $entry['scope'] ?? 'openid',
	]);
}

// ---- /userinfo -------------------------------------------------------------------------------
if ($path === '/userinfo') {
	$json([
		'sub' => 'mock-subject-1',
		'preferred_username' => (string)(getenv('OIDC_MOCK_USER') ?: 'alice'),
		'email' => 'alice@example.invalid',
		'email_verified' => true,
		'name' => 'Mock OIDC User',
	]);
}

if ($path === '/logout') {
	http_response_code(302);
	header('Location: ' . (string)($q['post_logout_redirect_uri'] ?? '/'));
	exit;
}

http_response_code(404);
header('Content-Type: text/plain');
echo "no such endpoint: {$path}\n";
