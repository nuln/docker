#!/usr/bin/env python3
"""Check the Content-Security-Policy the instance actually serves, from a browser.

FreshRSS sends `Content-Security-Policy: default-src 'self'`, hard-coded in
lib/Minz/ActionController.php with no configuration key for it. Two consequences this script
pins down:

  * no *executable* inline script may appear on the login page — the policy forbids inline
    script outright, so one is silently dead and the browser only reports a violation whose hash
    identifies the content and not the source;
  * allowing a third-party origin (Cloudflare Browser Insights is injected at the edge and is
    loaded from `static.cloudflareinsights.com`) must work, while everything not listed stays
    blocked.

Usage:
    ./test/browser-csp.py <base-url> <prefix> <port> [--allowed]

`--allowed` asserts the positive half: a script served from `http://localhost:<port>`, a
genuinely different origin from `127.0.0.1` that also resolves locally, is fetched and executed,
while `127.0.0.1` — same host, not listed — stays blocked. Without the flag the unmodified
policy is asserted to produce no violation at all.
"""

import sys

try:
    from playwright.sync_api import Error as PlaywrightError
    from playwright.sync_api import sync_playwright
except ModuleNotFoundError:
    # Called from test/integration.sh, which a developer may well run without Playwright installed.
    # Skipping is the right answer here; CI installs it up front, so this never applies there.
    print("== csp: skipped (python playwright is not installed)")
    sys.exit(0)

OK = "\033[32mok\033[0m"
BAD = "\033[31mFAIL\033[0m"
passed = 0
failed = 0


def check(label: str, got, want) -> None:
    global passed, failed
    if got == want:
        passed += 1
        print(f"  {OK}   {label}")
    else:
        failed += 1
        print(f"  {BAD} {label}\n     got:  {got!r}\n     want: {want!r}")


def main() -> int:
    allowed = "--allowed" in sys.argv
    argv = [a for a in sys.argv if not a.startswith("--")]
    if len(argv) < 3:
        print(__doc__)
        return 2
    base = argv[1].rstrip("/")
    prefix = argv[2].rstrip("/")
    port = argv[3]

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_context().new_page()
        violations: list[str] = []
        logs: list[str] = []
        page.on(
            "console",
            lambda m: (
                logs.append(f"{m.type}: {m.text}"),
                violations.append(m.text)
                if "Content Security" in m.text or "inline script" in m.text
                else None,
            ),
        )
        # Boxed in a list so the listener can write to it.
        csp = [""]
        page.on(
            "response",
            lambda r: csp.__setitem__(0, r.headers.get("content-security-policy", ""))
            if "c=auth" in r.url
            else None,
        )
        page.goto(f"{base}{prefix}/i/?c=auth&a=login", wait_until="load")
        page.wait_for_timeout(3000)

        # An inline script with a non-JSON type would be executed, and therefore blocked.
        inline = page.evaluate(
            """() => Array.from(document.querySelectorAll('script'))
                .filter(s => !s.src && s.type !== 'application/json')
                .map(s => s.outerHTML.slice(0, 120))"""
        )
        check("the login page has no executable inline script", inline, [])

        check(
            "FreshRSS's own scripts loaded despite the policy",
            page.evaluate("() => typeof window.bcrypt === 'object'"),
            True,
        )
        check(
            "the standard mobile-web-app-capable meta accompanies the Apple one",
            page.evaluate(
                """() => {
                    const metas = Array.from(document.querySelectorAll('meta[name]'));
                    const has = n => metas.some(m => m.getAttribute('name') === n);
                    return has('mobile-web-app-capable') && has('apple-mobile-web-app-capable');
                }"""
            ),
            True,
        )
        check(
            "the login form became usable",
            page.evaluate(
                "() => { const b = document.querySelector('#loginButton');"
                " return !!b && b.disabled === false; }"
            ),
            True,
        )

        if allowed:
            executed = False
            try:
                page.add_script_tag(url=f"http://localhost:{port}/probe.js")
                executed = page.evaluate("() => window.__allowed === true")
            except PlaywrightError as e:
                print(f"     the allowed origin was still blocked: {str(e)[:120]}")
            check("a script from the allowed origin executes", executed, True)
            check(
                "the policy names that origin with an explicit port",
                f"http://localhost:{port}" in csp[0],
                True,
            )
            check(
                "the policy is a single header, not several intersected ones",
                csp[0].count("default-src"),
                1,
            )
            # 127.0.0.1 is the page's own origin and is NOT listed as a separate source, so it is
            # covered by 'self' either way; what matters is that a host absent from the policy is
            # still refused. `localhost` minus the port is such a host.
            blocked = False
            try:
                page.add_script_tag(url="http://localhost/probe.js")
            except PlaywrightError:
                blocked = True
            check("an origin that is not listed stays blocked", blocked, True)
        else:
            check("the stock policy produces no violation at all", violations, [])
            # Upstream logs "waiting for bcrypt.js…" and "waiting for JS…" from init_crypto_forms
            # and init_extra_afterDOM. Both are true for a few milliseconds on every page load,
            # because bcrypt.js and main.js are deferred and asynchronous, so they used to appear
            # on every single view while saying nothing actionable. They are now only reported once
            # the wait is long enough to be real — and that must not regress.
            noisy = [m for m in logs if "waiting for" in m]
            check("no transient 'waiting for …' message is logged", noisy, [])
            errors = [m for m in logs if m.startswith(("error", "warning"))]
            check("nothing is logged as an error or a warning", errors, [])

        for v in violations:
            print(f"     violation: {v[:160]}")
        browser.close()

    print(f"\n== csp ({'allowed origin' if allowed else 'stock policy'}): {passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())