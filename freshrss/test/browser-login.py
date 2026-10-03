#!/usr/bin/env python3
"""Log in to FreshRSS with a real browser, the way a person does.

Every other check in this suite drives the login with curl: it POSTs the form
directly and therefore skips the JavaScript that the login page actually depends
on. That proves the server accepts the credentials, and nothing more. The login
page is a crypto form — `p/scripts/extra.js` leaves the submit button
`disabled`, fetches a per-login salt and nonce, derives a bcrypt challenge and
only then calls `form.submit()` — so a failure anywhere in that chain looks
exactly like a successful page load: a 200, a login form, and no POST.

This drives the real thing and asserts on the things that can only be observed
in a browser: that the button gets enabled, that a POST is issued, that the
session cookie survives, and that the reader's own view comes up.

Usage:
    ./test/browser-login.py <base-url> <user> <password> [prefix]

`base-url` is the public address of the instance, e.g. http://127.0.0.1:18080,
`prefix` is the sub-directory it is served from, e.g. /rss (default /).

A reverse proxy that routes by hostname must therefore be configured for the
address used here: Chromium forbids overriding the Host header, and Caddy
answers an unknown host with an empty 200 rather than an error, which looks like
a page that renders but never becomes interactive.
Exits non-zero, with a diagnosis per failed check, on any mismatch.
"""

import sys
from urllib.parse import urlparse

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import sync_playwright

# Set by `--stall-scripts`, which reproduces a failure mode rather than the happy path.
STALL = "--stall-scripts" in sys.argv
if STALL:
    sys.argv.remove("--stall-scripts")

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


def check_that(label: str, condition: bool, detail: str = "") -> None:
    check(label + (f" — {detail}" if detail else ""), bool(condition), True)


# The login page ships its submit button disabled and only p/scripts/extra.js enables it. If
# main.js, extra.js or bcrypt.js never loads - blocked by a policy, or stalled by a reverse proxy
# that cannot serve parallel requests - the form is unusable forever and says nothing: the page
# renders, the button does nothing, and no request is ever sent. This mode withholds the scripts
# and asserts that the page reports the failure instead of sitting there.
# The trailing `*` matters: the URLs carry a `?mtime` cache-buster, which a glob without it
# would not match.
STALLED_SCRIPTS = (
    "**/scripts/main.js*",
    "**/scripts/extra.js*",
    "**/scripts/vendor/bcrypt.js*",
)


def run_stalled(base: str, prefix: str) -> None:
    # Chromium throttles timers in a page it considers hidden, which would postpone a 15 s
    # deadline to a minute and make the watchdog look broken.
    launch_args = [
        "--disable-background-timer-throttling",
        "--disable-backgrounding-occluded-windows",
        "--disable-renderer-backgrounding",
    ]
    with sync_playwright() as p:
        browser = p.chromium.launch(args=launch_args)
        page = browser.new_context().new_page()
        navigations = []
        page.on("framenavigated", lambda f: navigations.append(f.url))
        for pattern in STALLED_SCRIPTS:
            page.route(pattern, lambda route: route.abort())
        page.goto(f"{base}{prefix}/i/?c=auth&a=login", wait_until="domcontentloaded")
        try:
            page.wait_for_selector(".alert-error", timeout=45000)
            reported = True
        except PlaywrightError:
            reported = False
        message = ""
        if reported:
            message = page.eval_on_selector(".alert-error", "el => el.textContent")
        check_that("a stalled script is reported on the page, not swallowed", reported)
        check_that(
            "...naming the scripts the operator has to check",
            "main.js" in message and "bcrypt.js" in message,
            message[:60],
        )
        check_that(
            "the page did not enter a reload loop",
            len(navigations) <= 2,
            f"{len(navigations)} navigations",
        )
        check_that(
            "the automatic reload is remembered, so it happens only once",
            page.evaluate("() => sessionStorage.getItem('freshrss_login_reloaded')") == "1",
        )
        browser.close()


def main() -> int:
    if STALL:
        if len(sys.argv) < 2:
            print(__doc__)
            return 2
        base = sys.argv[1].rstrip("/")
        # The credentials are irrelevant here, so the prefix is taken as the trailing argument
        # rather than by position.
        prefix = (sys.argv[-1] if sys.argv[-1].startswith("/") else "").rstrip("/")
        run_stalled(base, prefix)
        print(f"\n== stalled scripts: {passed} passed, {failed} failed")
        return 1 if failed else 0

    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    base = sys.argv[1].rstrip("/")
    user = sys.argv[2]
    password = sys.argv[3]
    prefix = (sys.argv[4] if len(sys.argv) > 4 else "").rstrip("/")

    console: list[str] = []
    requests: list[tuple[str, str, int | None]] = []
    cookies_seen: list[tuple[str, str]] = []

    with sync_playwright() as p:
        browser = p.chromium.launch()
        context = browser.new_context(ignore_https_errors=True)
        page = context.new_page()
        page.on("console", lambda m: console.append(f"{m.type}: {m.text}"))
        page.on("request", lambda r: requests.append(("→", r.method, r.url)))
        page.on(
            "response",
            lambda r: requests.append(("←", r.request.method, f"{r.status} {r.url}")),
        )

        login_url = f"{base}{prefix}/i/?c=auth&a=login"
        page.goto(login_url, wait_until="domcontentloaded")

        # 1. The crypto form must be wired up. extra.js leaves the button disabled
        #    and only init_crypto_forms() enables it, so this single fact tells us
        #    whether bcrypt.js and main.js both came up.
        # Wait for main.js to publish the context first, then for extra.js to wire the form:
        # init_crypto_forms() cannot run before window.context exists, so asking for the button
        # straight away races with main.js on a slow first load.
        try:
            page.wait_for_function(
                "() => typeof window.context === 'object' && window.context !== null",
                timeout=25000,
            )
            context_ready = True
        except PlaywrightError:
            context_ready = False
        try:
            page.wait_for_function(
                "() => { const b = document.querySelector('#loginButton');"
                " return b && b.disabled === false; }",
                timeout=25000,
            )
            enabled = True
        except PlaywrightError:
            enabled = False
        check_that("the login button is enabled by the page's own JavaScript", enabled)
        if not enabled:
            print("     console said:")
            for line in console[-8:]:
                print(f"       {line}")
            print(f"     bcrypt loaded: {page.evaluate('typeof window.bcrypt')}")
            print(f"     window.context: {page.evaluate('typeof window.context')}")

        check(
            "bcrypt.js is loaded",
            page.evaluate("typeof window.bcrypt"),
            "object",
        )
        check_that(
            "the login page defines the JSON context main.js requires",
            context_ready,
            "typeof window.context === 'object'",
        )

        page.fill("#username", user)
        page.fill(".passwordPlain", password)
        page.click("#loginButton")

        # 2. A POST must actually be issued. A login that renders fine but never
        #    submits is the failure this test exists to catch.
        try:
            page.wait_for_event(
                "request",
                predicate=lambda r: r.method == "POST" and "c=auth" in r.url,
                timeout=15000,
            )
            posted = True
        except PlaywrightError:
            posted = False
        check_that("clicking submit issues the login POST", posted)
        if not posted:
            print("     requests seen:")
            for entry in requests[-8:]:
                print(f"       {entry}")

        # 3. The reader's own view, reached by the browser following the redirect. Wait for the
        #    logged-in marker rather than for a fixed delay: a slow proxy can still be streaming
        #    the login page's assets after the POST response has arrived, and asserting on the DOM
        #    at that moment reports a failure the user never saw.
        try:
            page.wait_for_function(
                "() => !document.querySelector('form.crypto-form')"
                " && document.body.innerHTML.includes('a=logout')",
                timeout=30000,
            )
            logged_in = True
        except PlaywrightError:
            logged_in = False

        # The reader prefixes the title with the unread count, e.g. “(10) · FreshRSS”.
        title = page.title()
        check_that(
            "the browser ends up on the reader, not the login form",
            title.endswith("FreshRSS"),
            title,
        )
        check_that(
            "the URL stays inside the public sub-directory",
            prefix == "" or urlparse(page.url).path.startswith(prefix + "/"),
            page.url,
        )
        check_that(
            "no login form is rendered any more",
            page.query_selector("form.crypto-form") is None,
        )
        check_that(
            "the page offers a way to log out, i.e. the session is authenticated",
            logged_in,
        )

        for c in context.cookies():
            cookies_seen.append((c["name"], c["path"]))
        freshrss = [c for c in context.cookies() if c["name"] == "FreshRSS"]
        check_that("a FreshRSS session cookie is held by the browser", bool(freshrss))
        if freshrss:
            check(
                "…scoped to the public sub-directory",
                freshrss[0]["path"],
                (prefix if prefix else "") + "/",
            )

        if failed:
            print("\n  --- browser console ---")
            for line in console[-15:]:
                print(f"    {line}")
            print("\n  --- network ---")
            for entry in requests[-15:]:
                print(f"    {entry[0]} {entry[1]} {entry[2]}")

        browser.close()

    print(f"\n== browser login: {passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())