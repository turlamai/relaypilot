#!/usr/bin/env bash
# Native-UI acceptance for the macOS host: launch the packaged app with an
# isolated HOME, drive the v0.3 contract journeys over accessibility, and
# leave the declared evidence under .rivet/acceptance/macos.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
output="$repo/.rivet/acceptance/macos"
app="$repo/dist/relaypilot.app/Contents/MacOS/relaypilot"
driver="$output/macos-ax"
home="$output/home-$$"
mkdir -p "$output" "$home"
# Library isolation comes from RELAYPILOT_LIBRARY_ROOT; a HOME
# override would change the app's LaunchServices context and break AX.
export RELAYPILOT_LIBRARY_ROOT="$home/library"
[[ -x "$app" ]]

swiftc "$repo/scripts/e2e/macos-ax.swift" -o "$driver" \
  -framework AppKit -framework ApplicationServices

"$app" >"$output/application.log" 2>&1 &
app_pid=$!

stop_bounded() {
  local pid="$1"
  kill -TERM "$pid" 2>/dev/null || true
  for _ in $(seq 1 200); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.05
  done
  kill -KILL "$pid" 2>/dev/null || true
  return 1
}

cleanup() {
  local status=$?
  trap - EXIT
  if kill -0 "$app_pid" 2>/dev/null; then
    stop_bounded "$app_pid" || true
    wait "$app_pid" 2>/dev/null || true
  fi
  exit "$status"
}
trap cleanup EXIT

"$driver" --pid "$app_pid" --output "$output"
echo "acceptance journeys complete; evidence in $output"
