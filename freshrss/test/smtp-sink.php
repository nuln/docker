<?php
declare(strict_types=1);
// Minimal SMTP sink: accepts messages, appends each one to a file, and keeps listening.
//
// It exists so the email-validation flow can be tested for real — FreshRSS signs a token, mails a
// link, and the link has to be followed — without depending on an external mail service. Only the
// subset of SMTP that PHPMailer actually uses for a single message is implemented, and every reply
// is a success: the point of the test is FreshRSS, not the server.
//
// Usage: php smtp-sink.php <directory> [port]
// The last message is written to <directory>/last-mail.txt (headers and body, as received).

$dir = $argv[1] ?? '/tmp';
$port = (int)($argv[2] ?? 1025);
if (!is_dir($dir)) {
	mkdir($dir, 0o777, true);
}

$server = @stream_socket_server('tcp://0.0.0.0:' . $port, $errno, $errstr);
if ($server === false) {
	fwrite(STDERR, "smtp-sink: cannot listen on {$port}: {$errstr} ({$errno})\n");
	exit(1);
}
fwrite(STDOUT, "smtp-sink: listening on {$port}, writing to {$dir}\n");

/** Read one CRLF-terminated line from the client, transparently handling the greeting. */
$readLine = static function ($conn): string {
	$line = '';
	while (($chunk = fgets($conn, 8192)) !== false) {
		$line .= $chunk;
		if (substr($line, -2) === "\r\n" || substr($line, -1) === "\n") {
			break;
		}
	}
	return $line;
};
$reply = static function ($conn, string $text): void {
	fwrite($conn, $text . "\r\n");
};

while (true) {
	$conn = @stream_socket_accept($server, -1);
	if ($conn === false) {
		continue;
	}
	stream_set_timeout($conn, 20);
	$reply($conn, '220 freshrss-test-sink ESMTP ready');

	while (($line = $readLine($conn)) !== '') {
		$line = rtrim($line, "\r\n");
		$command = strtoupper(strtok($line, ' ') ?: '');

		switch ($command) {
			case 'EHLO':
				$reply($conn, '250-freshrss-test-sink');
				$reply($conn, '250 SIZE 10485760');
				break;
			case 'HELO':
				$reply($conn, '250 freshrss-test-sink');
				break;
			case 'MAIL':
			case 'RCPT':
			case 'RSET':
			case 'NOOP':
				$reply($conn, '250 OK');
				break;
			case 'STARTTLS':
				// Refused on purpose: the test must not depend on certificates.
				$reply($conn, '454 TLS not available');
				break;
			case 'DATA':
				$reply($conn, '354 End data with <CR><LF>.<CR><LF>');
				$body = '';
				while (($chunk = fgets($conn, 8192)) !== false) {
					$body .= $chunk;
					if (rtrim($body, "\r\n") === '.') {
						$body = substr($body, 0, -3);
						break;
					}
				}
				file_put_contents($dir . '/last-mail.txt', $body, LOCK_EX);
				file_put_contents($dir . '/count.txt', (string)(1 + (int)@file_get_contents($dir . '/count.txt')), LOCK_EX);
				$reply($conn, '250 OK: queued');
				break;
			case 'QUIT':
				$reply($conn, '221 Bye');
				break 2;
			default:
				$reply($conn, '250 OK');
				break;
		}
	}
	fclose($conn);
}
