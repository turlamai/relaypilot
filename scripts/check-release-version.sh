#!/bin/sh
# RelayPilot release identity must agree across the root VERSION file,
# rivet.rktd, info.rkt and racket/core/version.rkt. Usage:
# scripts/check-release-version.sh [expected-tag]
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

fail() {
    echo "release identity mismatch: $1" >&2
    exit 1
}

# Root VERSION: bare semver on a single line, newline-terminated (family
# convention; the tag pipeline and release notes both key off it).
grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' VERSION || fail "VERSION must be bare semver (x.y.z)"
[ "$(tail -c 1 VERSION | wc -l)" -eq 1 ] || fail "VERSION must end with a newline"
file_version=$(cat VERSION)

rivet_version=$(sed -n 's/.*(version \. "\([^"]*\)").*/\1/p' rivet.rktd | head -1)
rivet_build=$(sed -n 's/.*(build \. \([0-9]*\)).*/\1/p' rivet.rktd | head -1)
info_version=$(sed -n 's/^(define version "\(.*\)")$/\1/p' info.rkt | head -1)
core_version=$(sed -n 's/^(define app-version "\(.*\)")$/\1/p' racket/core/version.rkt | head -1)
core_build=$(sed -n 's/^(define app-build \([0-9]*\))$/\1/p' racket/core/version.rkt | head -1)

[ -n "$rivet_version" ] || fail "no version in rivet.rktd"
[ -n "$rivet_build" ] || fail "no build in rivet.rktd"
[ "$file_version" = "$rivet_version" ] || fail "VERSION ($file_version) != rivet.rktd ($rivet_version)"
[ "$rivet_version" = "$info_version" ] || fail "rivet.rktd ($rivet_version) != info.rkt ($info_version)"
[ "$rivet_version" = "$core_version" ] || fail "rivet.rktd ($rivet_version) != racket/core/version.rkt ($core_version)"
[ "$rivet_build" = "$core_build" ] || fail "rivet.rktd build ($rivet_build) != racket/core/version.rkt build ($core_build)"

if [ "$#" -ge 1 ]; then
    expected=${1#v}
    [ "$rivet_version" = "$expected" ] || fail "rivet.rktd ($rivet_version) != tag ($expected)"
fi

echo "release identity aligned: version $rivet_version, build $rivet_build"
