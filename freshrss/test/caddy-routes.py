#!/usr/bin/env python3
"""Print a Caddy JSON config's HTTP routes in evaluation order, and match paths.

When a reverse proxy seems to be bypassed — a redirect answers a path you
expected to be proxied — the reason is always visible in the compiled route
order. Caddy reorders what you wrote: directives are sorted by a fixed order in
which `redir` and `respond` come before `handle` and `reverse_proxy`, while
`handle` blocks are mutually exclusive and sorted by how specific their matcher
is. Reading the Caddyfile does not tell you which of those happened; the adapted
JSON does.

Usage:
    caddy adapt --config /etc/caddy/Caddyfile | python3 test/caddy-routes.py
    python3 test/caddy-routes.py config.json [path ...]

With paths given, each is reported against the first route that matches it. A
route with no `path` matcher matches every path, so an unqualified `redir`
compiled ahead of a `handle /rss/*` will show up as the route answering `/rss/` —
which is exactly the failure this is for finding.

`docker exec <container> caddy adapt --config /etc/caddy/Caddyfile` works too, so
you can inspect a running container without shell access to the host files.
"""

from __future__ import annotations

import json
import sys
from urllib.parse import urlsplit

Route = dict


def matcher_text(match: list | None) -> str:
    """Render a Caddy matcher roughly the way it reads in a Caddyfile."""
    if not match:
        return ""
    parts = []
    for clause in match:
        for key, value in clause.items():
            if key == "not":
                # Each entry of a `not` clause is a matcher in its own right, so wrap it before
                # recursing — passing the dict where a list of clauses is expected reads its keys
                # as if they were clauses.
                inner = "; ".join(matcher_text([v]) for v in value)
                parts.append(f"NOT {inner}")
            elif isinstance(value, list):
                parts.append(f"{key} " + " ".join(str(v) for v in value))
            else:
                parts.append(f"{key} {value}")
    return " AND ".join(parts)


def path_matches(patterns: list, path: str) -> bool:
    """Caddy path semantics: exact, or a trailing `*` matching any remainder."""
    for pattern in patterns:
        if pattern == path:
            return True
        if pattern.endswith("/*") and path.startswith(pattern[:-1]):
            return True
    return False


def route_matches(route: Route, path: str) -> bool:
    """Whether this route's matcher accepts the path.

    A route whose matcher says nothing about paths accepts every path — that is
    how an unqualified `redir` or `respond` ends up answering requests it was
    never meant to.
    """
    match = route.get("match") or []
    if not match:
        return True
    for clause in match:
        if "path" in clause:
            if not path_matches(clause["path"], path):
                return False
        elif "not" in clause:
            negated = any(
                "path" in inner and path_matches(inner["path"], path)
                for inner in clause["not"]
            )
            if negated:
                return False
    return True


# Handlers that wrap or adjust the request/response rather than answering it. Caddy places them in
# the same route's handle array ahead of the handler that produces the response, so reporting them
# as the route that answered a request would name the wrong thing — `encode` is the usual culprit.
MIDDLEWARE = frozenset({
    "encode", "headers", "vars", "request_body", "rewrite", "copy_response",
    "tracing", "map", "intercept", "invoke", "templates", "push",
})


def describe(handler: dict) -> str:
    """One-line summary of a terminal handler."""
    name = handler.get("handler", "?")
    if name == "redirect":
        target = handler.get("headers", {}).get("Location", [""])[0]
        return f"REDIRECT {handler.get('status_code', 302)} -> {target}"
    if name == "reverse_proxy":
        upstreams = ", ".join(u["dial"] for u in handler.get("upstreams", []))
        return f"REVERSE_PROXY -> {upstreams}"
    if name == "static_response":
        target = handler.get("headers", {}).get("Location")
        if target:
            return f"REDIRECT {handler.get('status_code')} -> {target[0]}"
        return f"RESPOND {handler.get('status_code', 200)}"
    if name == "file_server":
        return "FILE_SERVER"
    if name == "subroute":
        return "SUBROUTE"
    if name == "route":
        return "ROUTE"
    return name.upper()


def constrains_path(match: list | None) -> bool:
    """Whether any clause in the matcher restricts which paths reach this route.

    A route with no `path` clause accepts every path, which is exactly why an
    unqualified `redir` compiled ahead of `handle /rss/*` swallows the sub-directory.
    """
    for clause in match or []:
        if "path" in clause:
            return True
        if any("path" in inner for inner in clause.get("not", [])):
            return True
    return False


def collect(routes: list, out: list, inherited: list | None = None) -> None:
    """Flatten the route tree into leaf routes, preserving evaluation order.

    Caddy wraps mutually exclusive groups in an entry carrying a `group` label
    whose `handle` array holds the real handlers, and `subroute` nests another
    level of routes. Descend through both so the leaves come out in the order
    Caddy will try them.

    A matcher can sit on any level, so clauses are inherited downwards: the
    `path /rss/*` that guards a `handle` block is attached to the `subroute`
    entry wrapping it, not to the `reverse_proxy` leaf inside. Dropping it would
    make the leaf look like a catch-all.
    """
    for route in routes:
        match = (inherited or []) + (route.get("match") or [])
        for handler in route.get("handle", []):
            name = handler.get("handler")
            if name in ("subroute", "route"):
                collect(handler.get("routes", []), out, match)
            elif name not in MIDDLEWARE:
                out.append({"match": match, "label": describe(handler)})


def routes_of(config: dict) -> list:
    servers = config.get("apps", {}).get("http", {}).get("servers", {})
    leaves: list = []
    for server in servers.values():
        local: list = []
        for route in server.get("routes", []):
            match = route.get("match")
            for handler in route.get("handle", []):
                name = handler.get("handler")
                if name in ("subroute", "route"):
                    inner: list = []
                    collect(handler.get("routes", []), inner, match)
                    local.extend(inner)
                elif name not in MIDDLEWARE:
                    local.append({"match": match, "label": describe(handler)})
        leaves.extend(local)
    return leaves


def main(argv: list) -> int:
    if len(argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        if argv[1] == "-":
            config = json.load(sys.stdin)
        else:
            with open(argv[1], encoding="utf-8") as handle:
                config = json.load(handle)
    except OSError as error:
        print(f"cannot read {argv[1]}: {error}", file=sys.stderr)
        return 2
    except json.JSONDecodeError as error:
        print(f"{argv[1]} is not Caddy JSON: {error}", file=sys.stderr)
        return 1

    routes = routes_of(config)
    if not routes:
        print("no HTTP routes found", file=sys.stderr)
        return 1

    print("effective route order (first match wins):")
    for index, route in enumerate(routes, 1):
        text = matcher_text(route["match"])
        if not constrains_path(route["match"]):
            text = f"{text}, any path" if text else "any path"
        suffix = f" [{text}]" if text else ""
        print(f"  {index:>2}. {route['label']}{suffix}")

    for target in argv[2:]:
        path = urlsplit(target).path or "/"
        print(f"\n  {target}")
        for index, route in enumerate(routes, 1):
            if route_matches(route, path):
                print(f"      answered by route {index}: {route['label']}")
                break
        else:
            print("      no route matched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))