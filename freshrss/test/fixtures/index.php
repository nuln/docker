<?php
declare(strict_types=1);
// Minimal RSS publisher for functional.sh and integration.sh.
//
//   GET  /feed.xml  -> the current feed (starts with one article)
//   POST /publish   -> append a new article, so a refresh must pick it up
//   GET  /state     -> how many articles are published so far
//
// The article list is kept in a file next to the document root, so the feed URL never changes:
// FreshRSS caches per URL, which is exactly what a real feed does.
//
// Two environment variables make it behave like a WebSub-capable publisher:
//   PUBLISHER_SELF_URL — the `atom:link rel="self"` it advertises; `p/api/pshb.php` refuses a
//                        push whose self link differs from the registered topic.
//   PUBLISHER_HUB_URL  — the `atom:link rel="hub"` it advertises; when set, FreshRSS enrols the
//                        feed in WebSub on the first actualisation.

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$stateFile = __DIR__ . '/state.json';
$selfFile = __DIR__ . '/self.url';

if ($path === '/state') {
	header('Content-Type: application/json');
	echo file_get_contents($stateFile) ?: '{"count":0}';
	exit;
}

// Change the advertised `rel="self"` at runtime. FreshRSS treats a changed self link on a feed it
// already knows as the feed having moved, which is the only path that makes it unsubscribe from the
// old WebSub topic (see feedController::actualizeFeedsAndCommit).
if ($path === '/setself' && ($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
	file_put_contents($selfFile, (string)($_POST['url'] ?? ''));
	// Moving a feed changes the document, so the cache validators have to change with it: otherwise
	// the next conditional request is answered 304 and the new self link is never seen.
	@touch($stateFile);
	header('Content-Type: text/plain');
	echo "self=" . (string)@file_get_contents($selfFile) . "\n";
	exit;
}

$state = json_decode((string)@file_get_contents($stateFile), true);
$state = is_array($state) ? $state : ['count' => 1];
$articles = $state['articles'] ?? [];

if ($path === '/publish' && ($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
	$n = (int)($state['count'] ?? 1) + 1;
	$articles[] = [
		'n' => $n,
		'title' => "Published article #{$n}",
		'link' => "http://example.invalid/article-{$n}",
		'guid' => "local-article-{$n}",
		'date' => gmdate('D, d M Y H:i:s \+\0\0\0O', 1893456000 + $n * 3600),
	];
	file_put_contents($stateFile, json_encode(['count' => $n, 'articles' => $articles]));
	header('Content-Type: text/plain');
	echo "published {$n}\n";
	exit;
}

if ($articles === []) {
	$articles[] = [
		'n' => 1,
		'title' => 'First article from the local feed',
		'link' => 'http://example.invalid/first',
		'guid' => 'local-article-1',
		'date' => gmdate('D, d M Y H:i:s \+\0\0\0O', 1893456000),
	];
	$state['count'] = 1;
	$state['articles'] = $articles;
	file_put_contents($stateFile, json_encode($state));
}

$items = '';
foreach ($articles as $a) {
	$items .= <<<XML

	<item>
		<title>{$a['title']}</title>
		<link>{$a['link']}</link>
		<guid isPermaLink="false">{$a['guid']}</guid>
		<description>Article number {$a['n']} from the functional test publisher.</description>
		<pubDate>{$a['date']}</pubDate>
	</item>
	XML;
}

$selfUrl = is_file($selfFile) ? (string)file_get_contents($selfFile)
	: (string)(getenv('PUBLISHER_SELF_URL') ?: 'http://example.invalid/feed.xml');
$hubUrl = (string)(getenv('PUBLISHER_HUB_URL') ?: '');
$hubLink = $hubUrl === '' ? '' :
	"\t" . '<atom:link href="' . htmlspecialchars($hubUrl, ENT_XML1) . '" rel="hub" />' . "\n";

header('Content-Type: application/rss+xml; charset=utf-8');
// A real publisher advertises cache validators and FreshRSS/SimplePie depends on them: without an
// ETag/Last-Modified the parser keeps serving its own cached copy and never notices new items. The
// advertised links are part of the validator, because a feed that moves is a different document.
$etag = '"' . md5($selfUrl . '|' . $hubUrl . '|' . (string)json_encode($articles)) . '"';
$inm = trim((string)($_SERVER['HTTP_IF_NONE_MATCH'] ?? ''));
if ($inm !== '' && ($inm === $etag || $inm === '*' || str_contains($inm, $etag))) {
	header('HTTP/1.1 304 Not Modified');
	exit;
}
header('ETag: ' . $etag);
header('Last-Modified: ' . gmdate('D, d M Y H:i:s \G\M\T', (int)(@filemtime($stateFile) ?: time())));
header('Cache-Control: max-age=0, must-revalidate');
echo '<?xml version="1.0" encoding="UTF-8"?>', "\n";
?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
	<title>Functional Test</title>
	<link>http://example.invalid/</link>
	<description>Feed published by the FreshRSS functional test.</description>
	<language>en-us</language>
	<lastBuildDate><?= gmdate('D, d M Y H:i:s \+\0\0\0O') ?></lastBuildDate>
	<atom:link href="<?= htmlspecialchars($selfUrl, ENT_XML1) ?>" rel="self" type="application/rss+xml" />
<?= $hubLink ?>	<?= $items ?>
</channel>
</rss>
