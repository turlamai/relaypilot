# Security Policy

RelayPilot is an architecture alpha with no released clients and no sale. What exists today is a Racket source CLI, a supervised loopback engine session against a pinned Xray binary, and an atomic local storage boundary. Reports are taken seriously and handled quickly.

## Reporting a vulnerability

Email **security@jrtx.site** (or open a GitHub security advisory on this
repository). Include reproduction steps, affected versions, and your
assessment of impact. You will get an acknowledgment within 72 hours.

Please do not open public issues for security problems.

## Scope

In scope:

- The CLI surface (`app/cli.rkt`, launchers `scripts/relaypilot-cli.sh` /
  `scripts/relaypilot-cli.cmd`): argument and profile parsing, the
  Surge-compatible import parser, exit codes, and canonical JSON output —
  an import that silently changes rule semantics, or output that leaks
  secrets, is a bug.
- The configuration plane: canonical Relay Profile validation
  (`app/core/profile/`), the deterministic rules evaluator
  (`app/core/rules/`), policy group selection (`app/core/policy/`), and
  the Xray adapter compiler (`app/core/engines/`) — generated engine
  configuration must stay faithful to the evaluated decision, carry its
  source map and SHA-256 identity, and reject unsupported semantics
  instead of delegating them silently to the engine.
- The supervised engine session (`app/core/engines/runtime.rkt`): pinned
  binary discovery via `RELAYPILOT_XRAY_BIN`, the version query,
  `run -test` config validation, session start/stop lifecycle, and the
  bounded structured event bridge — what may be launched, what loopback
  endpoints the session binds, and how far engine events may travel.
- Secret redaction and the diagnostics/AI boundary
  (`app/core/diagnostics/`, `app/core/ai/`): `DiagnosticBundle` and
  `ConfigPatch` must keep credentials, server addresses and keys out of
  traces, patches and reports.
- The storage boundary (`app/core/storage/`) and the Rivet RPC boundary
  (`app/backend.rkt`): atomic local-folder writes, no telemetry, and the
  rule that hosts render while the Racket backend decides.

Explicitly in scope as a fact, not a finding: **RelayPilot currently has
no automatic update mechanism.** Nothing checks for, downloads or applies
updates. If an update feed is introduced later, it will follow the family
UPDATE contract with Ed25519-signed manifests; until then there is no
update surface to attack.

Out of scope: defects in Xray-core itself (report upstream to
[XTLS/Xray-core](https://github.com/XTLS/Xray-core)), social engineering,
physical access attacks, and the operating system's process/network
primitives.

## Design notes reviewers should know

- RelayPilot owns no listening network port. Loopback SOCKS ingress exists
  only inside supervised test sessions and is configured through the
  generated engine configuration; test credentials are synthetic.
- No engine binary is bundled or redistributed by this repository. CI and
  local verification download one official Xray release, checksum-pinned
  (see `docs/third-party.md`), solely to validate configuration and drive
  loopback sessions. The generated notice text that a future bundle must
  ship lives in `THIRD_PARTY_NOTICES.txt`
  (`racket scripts/third-party-notices.rkt`).
- Release identity is checked, not auto-updated: `info.rkt`, `rivet.rktd`
  and `app/core/version.rkt` must agree (`scripts/check-release-version.sh`).
- Local data stays in the user-selected local folder and is never uploaded
  anywhere; provider-specific sync remains outside the profile model.

## Supported versions

RelayPilot is a source-stage architecture alpha: there are no release
artifacts or tags yet. Security fixes land on `main` first; `0.1.0` is the
package identity recorded in `CHANGELOG.md`, not a shipped build.
