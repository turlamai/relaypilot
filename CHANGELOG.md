# Changelog

All notable changes to RelayPilot are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
RelayPilot is an architecture alpha: versions below identify the source
tree, and no release artifacts, installers or tags exist for them yet.

## [Unreleased]

## [0.1.0] - 2026-10-08

Architecture alpha. The version was established at the initial commit and
is kept aligned across `rivet.rktd`, `info.rkt` and
`app/core/version.rkt` by `scripts/check-release-version.sh`.

### Added

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
  `THIRD_PARTY_NOTICES.txt`) and CI checks for release identity and the
  notice pin

[Unreleased]: https://github.com/turlamai/relaypilot/compare/aa58bad57af3c9c2d52499a89302bba62a15fb19...HEAD
[0.1.0]: https://github.com/turlamai/relaypilot/commit/aa58bad57af3c9c2d52499a89302bba62a15fb19
