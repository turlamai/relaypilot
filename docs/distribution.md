# RelayPilot distribution

**Status: architecture alpha, no published release yet.** A release
pipeline is in place (see *Release line*), but until a `v*` tag is pushed
there are no GitHub Release assets, tags or installers for RelayPilot.
Nothing in this repository is a released VPN, TUN or system-wide network
client ([platform maturity](platform-maturity.md)).

## Current state (facts)

- **Source is the only acquisition path today.** Clone the repository and build
  it yourself; the steps live in [README](../README.md) → *Build and test*
  (Racket CS 9.x + Rivet, `raco make`, `raco test`, the CLI golden
  runner). The launchers `scripts/relaypilot-cli.sh` /
  `scripts/relaypilot-cli.cmd` are thin dev/CI shims that run
  `racket/cli.rkt` through the system Racket; they are not installable
  programs.
- **No release has been published.** `0.1.0` is the package identity
  recorded in [CHANGELOG](../CHANGELOG.md), `info.rkt` and
  `racket/core/version.rkt`; the repo has no version tags and no GitHub
  Releases ([SECURITY](../SECURITY.md)).
- **The rivet native host directories were retired** (2026-11-24, glaze
  re-line). `macos-host/`, `windows/`, `linux/`, `apple/` and `android/` are
  gone from the tree; the glaze carrier in `host/` is the only desktop host.
- **A package is built in CI on every change.** `packaged-smoke.yml`
  builds an unsigned distribution on the four carriers and checks that the
  packaged program starts and survives for eight seconds.
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

## Release line

**The pipeline exists; nothing has been published through it.**
`.github/workflows/release.yml` has two modes with the same build steps:

- **Rehearsal** (manual run): builds every package and leaves it as a
  workflow artifact. macOS is ad-hoc signed there, so Gatekeeper will not
  open it on another Mac without a right-click → Open. Nothing is
  published.
- **Release** (push a `v*` tag): the tag must match the release identity
  and the CHANGELOG section. macOS is Developer ID signed and notarized,
  Windows ships an MSI that is **not** Authenticode-signed, Linux ships
  `deb` + `rpm` + `AppImage` + `tar.gz`. The result is published as a
  pre-release with `SHA256SUMS` and build-provenance attestations.
- The release mode **fails before building anything** unless the five macOS
  signing secrets are set on this repository (`DEVELOPER_ID_P12_B64`,
  `DEVELOPER_ID_P12_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`,
  `ASC_KEY_P8_B64`). They are not set at the time of writing.

Gaps against the family baseline, on record: no Flatpak bundle and no app
icon (neither asset exists yet), no signed update feed (there is no update
mechanism to consume one, see below), no Windows code signing.

- **Channel: GitHub Releases only**, entered by pushing a version tag.
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
