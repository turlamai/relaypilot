#!/usr/bin/env python3
"""Every carrier route carries a permission class (#13 S5).

host/verify.rkt runs without a capability (open-route mode), but the
production carrier and the package run with `host-capability`. Under a
capability glaze's HTTP carrier is default-deny: a route without
`#:permission` answers 403 "capability denied API route", and the event
stream needs the `glaze:events` grant. The verifier stays green through
such a gap; the packaged self-check only meets it if the journey happens to
call the route. This gate makes the omission a static failure.

Run after any route or capability change (host-ci.yml runs it on every PR):

    python scripts/check-route-permissions.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "host" / "main.rkt"

ROUTE = re.compile(r'^\s*\[\((?:GET|POST)\s+"([^"]+)"(.*)$')
CAPABILITY = re.compile(r"\(make-capability\s+\"relaypilot\"\s*'\(([^)]*)\)\)")


def main() -> int:
    text = SOURCE.read_text(encoding="utf-8")
    errors: list[str] = []
    routes = 0
    for number, line in enumerate(text.splitlines(), 1):
        match = ROUTE.match(line)
        if not match:
            continue
        routes += 1
        if "#:permission" not in match.group(2):
            errors.append(f"host/main.rkt:{number}: route {match.group(1)} has no #:permission")
    if not routes:
        errors.append("host/main.rkt: no routes matched; the route syntax changed")

    capability = CAPABILITY.search(text)
    if not capability:
        errors.append("host/main.rkt: host-capability grant list not found")
    else:
        grants = capability.group(1).split()
        if "glaze:events" not in grants:
            errors.append("host-capability lacks glaze:events: tray picks cannot reach the page")

    if errors:
        for error in errors:
            print(f"route permission gate FAIL: {error}", file=sys.stderr)
        return 1
    print(f"Route permission gate PASS: {routes} routes classified, "
          f"{len(grants) if capability else 0} grants")
    return 0


if __name__ == "__main__":
    sys.exit(main())
