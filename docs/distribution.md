# RelayPilot distribution

**Status: source-only architecture alpha.** There are no GitHub Release
assets, installers, packages, tags or binaries for RelayPilot. Nothing in
this repository is a released VPN, TUN or system-wide network client
([platform maturity](platform-maturity.md)).

## Current state (facts)

- **Source is the only acquisition path.** Clone the repository and build
  it yourself; the steps live in [README](../README.md) → *Build and test*
  (Racket CS 9.x + Rivet, `raco make`, `raco test`, the CLI golden
  runner). The launchers `scripts/relaypilot-cli.sh` /
  `scripts/relaypilot-cli.cmd` are thin dev/CI shims that run
  `racket/cli.rkt` through the system Racket; they are not installable
  programs.
- **No release assets exist.** `0.1.0` is the package identity recorded in
  [CHANGELOG](../CHANGELOG.md), not a shipped build
  ([SECURITY](../SECURITY.md)); the repo has no version tags and no
  GitHub Releases.
- **The five host directories are planning placeholders.** `macos-host/`,
  `windows/`, `linux/`, `apple/` and `android/` each contain only a
  README describing the planned native host. They produce nothing
  installable today and are not released clients.
- **No engine binary is bundled or redistributed.** CI and local
  verification download one checksum-pinned Xray release for
  configuration validation and loopback sessions only
  ([third-party provenance](third-party.md)).
- **No update mechanism exists.** Nothing checks for, downloads or
  applies updates ([SECURITY](../SECURITY.md)).

## Gate before any binary ships

No binary of any kind is published before its release gates pass — the
same fail-closed posture as the family's distribution policy. Concretely,
for RelayPilot that means:

- A platform is not claimed as supported until its native host and a real
  data path are verified on that platform
  ([AGENTS](../AGENTS.md) truthfulness rules,
  [platform maturity](platform-maturity.md)).
- VPN/tunnel/service semantics stay in this repository, never inside
  Rivet ([AGENTS](../AGENTS.md) Rivet boundary).
- Any bundle that ships an engine binary must carry the generated NOTICE
  text and the written source offer
  ([third-party provenance](third-party.md)).
- Release identity must agree across `info.rkt`, `rivet.rktd` and
  `racket/core/version.rkt` (`scripts/check-release-version.sh`, already
  enforced in CI).
- Runtime/host changes need end-to-end evidence on their target OS
  ([AGENTS](../AGENTS.md) verification rules).

## Planned release shape (first desktop host, ROADMAP M2)

**Planned, not committed.** The items below describe the intended shape
for the day the first native desktop host
([ROADMAP M2](../ROADMAP.md)) ships; none of it exists in this
repository yet, and the plan can change until then.

- **Channel: GitHub Releases only**, entered by pushing a version tag;
  a tag-triggered release workflow builds, gates, packages and publishes.
- **Asset matrix per the family baseline**: macOS `dmg` + `zip`, Windows
  `msi` + `zip`, Linux `deb` + `rpm` + `AppImage` + Flatpak bundle +
  `tar.gz`, with a `SHA256SUMS.txt` covering every asset and build
  provenance attestation.
- **Update mechanism**: ROADMAP M2 explicitly *reserves* this slot — an
  Ed25519-signed update feed aligned with the family UPDATE contract
  (canonical copy: `turlamai/taskly` `shared/spec/UPDATE.md`). No
  auto-updater exists today and none ships before that contract is
  adopted here ([ROADMAP M2](../ROADMAP.md)).
- Until a release exists, the only supported way to run RelayPilot is the
  source build path above.

## Related documents

- [User guide](USER-GUIDE.md) — availability and known limits
- [Platform maturity](platform-maturity.md) — what is and is not claimed
- [Third-party engine provenance](third-party.md) — Xray pin, notices,
  source-offer obligations for future bundles
- [Security policy](../SECURITY.md) — no update surface today
- [Roadmap](../ROADMAP.md) — when the first host lands
