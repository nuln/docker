#!/usr/bin/env bash
# Reproduce exactly what p/scripts/extra.js does in the browser for the FreshRSS form login,
# using the very same bcrypt implementation the browser runs (p/scripts/vendor/bcrypt.js):
#
#   1. GET ?c=javascript&a=nonce&user=…  ->  { "salt1": "$2y$09$…", "nonce": "…" }
#   2. s        = bcrypt(plainPassword, salt1)
#   3. challenge = bcrypt(s + nonce)                # posted with the nonce
#
# Doing this with PHP's password_hash() would NOT work: the `salt` option is ignored under the
# CLI SAPI, so `s` would not match the stored hash. bcrypt.js honours the salt, as required.
#
# Usage: bcrypt-challenge.sh <container> <user> <plainPassword> <nonce>
set -euo pipefail

CONTAINER="$1"
USER="$2"
PLAIN="$3"
NONCE="$4"

salt1=$(
	docker exec "$CONTAINER" php -d error_reporting=0 -r '
		$conf = include "/var/www/FreshRSS/data/users/" . $argv[1] . "/config.php";
		echo substr($conf["passwordHash"], 0, 29);
	' "$USER" 2>/dev/null
)

[ -n "$salt1" ] || { echo "cannot read salt1 for user $USER" >&2; exit 1; }

docker exec -i "$CONTAINER" node -e '
	// bcrypt.js is a UMD bundle; evaluate it with an explicit `module` so its CommonJS branch is
	// taken regardless of how node treats the globals of `node -e`.
	const fs = require("fs");
	const src = fs.readFileSync("/var/www/FreshRSS/p/scripts/vendor/bcrypt.js", "utf8");
	const mod = { exports: {} };
	new Function("module", "exports", "require", src)(mod, mod.exports, require);
	const bcrypt = mod.exports.default || mod.exports;
	if (typeof bcrypt.hashSync !== "function") {
		throw new Error("bcrypt.js did not expose hashSync");
	}
	let input = "";
	process.stdin.on("data", (d) => (input += d));
	process.stdin.on("end", () => {
		const [salt1, plain, nonce] = input.split("\n");
		// The browser uses genSaltSync(4) on capable clients, poormanSalt() otherwise; both are
		// valid bcrypt salts for password_verify().
		const s = bcrypt.hashSync(plain, salt1);
		process.stdout.write(bcrypt.hashSync(s + nonce, bcrypt.genSaltSync(4)));
	});
' <<-EOF
	$salt1
	$PLAIN
	$NONCE
EOF
