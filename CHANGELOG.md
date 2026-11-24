# Changelog

All notable changes to RelayPilot are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
RelayPilot is an architecture alpha. Versions identify the source tree;
`0.1.0` is the first version with packaged builds (see Releases).

## [Unreleased]

## [0.1.0] - 2026-11-24

Architecture alpha, and the first packaged build. The version is kept
aligned across `rivet.rktd`, `info.rkt` and `racket/core/version.rkt` by
`scripts/check-release-version.sh`. It was set at the initial commit
(2026-10-08) and had no release artifacts before this date.

### Added

- Glaze desktop carrier (`host/`): one web UI for connect/overview, the
  profile library, route check and trace, diagnostics export and settings;
  quick find (`Ctrl/⌘ K`); a carrier-owned tray whose picks run the same
  action path as page buttons. Built on Windows, macOS and Linux; a real
  window journey runs on all three in CI.
- Typed RPC bridge over the glaze carrier for route explanation, engine
  compilation and session, the profile library, diagnostics and i18n.
- Release pipeline (`.github/workflows/release.yml`): a `v*` tag builds the
  installers and publishes a GitHub Release with `SHA256SUMS`; a manual run
  builds the same packages as rehearsal artifacts only. A packaged-launch
  smoke runs on every change.

### Fixed

- The production carrier (`racket host/main.rkt` and the package) refused
  its own page: under a capability the HTTP carrier is default-deny, and
  only the save dialog and the export write carried a permission, so every
  other route answered 403 and the page showed "load failed". The event
  stream (tray picks to the page) was refused as well. Every route now
  carries a permission class, `glaze:events` is granted, a static gate
  (`scripts/check-route-permissions.py`) keeps it so, and the packaged
  launch smoke runs the product journey on the production path
  (`RELAYPILOT_SELFTEST=1`), which is what found it. The verifier
  (`host/verify.rkt`) runs without a capability and never met the fault.

### Removed

- The rivet native host directories (`macos-host/`, `windows/`, `linux/`,
  `apple/`, `android/`) and their CI jobs; the glaze carrier is the only
  desktop host. The code stays in history before `216251c`.

### Added (engine and CLI, 2026-10-08)
- Canonical Relay Profile JSON with validation and round-trip serialization
- Surge-compatible rule-line import for `DOMAIN`, `DOMAIN-SUFFIX`,
  `IP-CIDR`, `IP-CIDR6`, `GEOIP`, `FINAL`, and `MATCH` syntax
- Deterministic local evaluation for exact domain, suffix, IPv4 CIDR, and
  final rules; select/fallback policy groups with cycle detection
- `DecisionTrace`: rule source, policy resolution, selected outbound,
  steps, warnings, and a stable trace ID
- `EngineAdapter` contract with an Xray compiler for VLESS +
  RAW/TLS/REALITY: canonical engine JSON, SHA-256 identity, and rule
  source maps
- Supervised Xray process runtime (pin `v26.3.27`): binary discovery,
  version query, `run -test` config validation, session start/stop with a
  bounded structured event bridge, and a real loopback SOCKS session
  against a local test endpoint
- Agent-first CLI (`validate` / `decide` / `compile` / `dry-run` /
  `import-surge` / `diagnose` / `version`) with a byte-level golden
  contract ([docs/CLI-SPEC.md](docs/CLI-SPEC.md))
- Rivet RPC boundary for route explanation, engine compilation, dry runs,
  and engine session lifecycle
- Atomic local-folder storage boundary; `DiagnosticBundle` with secret
  redaction; preconditioned typed `ConfigPatch`
- Third-party notices/source-offer workflow
  (`scripts/third-party-notices.rkt`, `docs/third-party.md`,
  `THIRD_PARTY_NOTICES.md`) and CI checks for release identity and the
  notice pin

[Unreleased]: https://github.com/turlamai/relaypilot/compare/aa58bad57af3c9c2d52499a89302bba62a15fb19...HEAD
[0.1.0]: https://github.com/turlamai/relaypilot/commit/aa58bad57af3c9c2d52499a89302bba62a15fb19
