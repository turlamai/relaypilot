# RelayPilot

RelayPilot is an architecture alpha for canonical network profiles and explainable routing. It provides a Racket source CLI, a supervised loopback engine slice and a Glaze desktop host; no public desktop or mobile release is available yet.

[![CI](https://github.com/turlamai/relaypilot/actions/workflows/ci.yml/badge.svg)](https://github.com/turlamai/relaypilot/actions/workflows/ci.yml) ![built with](https://img.shields.io/badge/built%20with-Glaze%20%2B%20Rivet-9333ea) ![license](https://img.shields.io/badge/license-Proprietary-red) ![stage](https://img.shields.io/badge/stage-architecture%20alpha-C15F3C)

**English** · [中文](README.zh-CN.md) · 🌐 [relaypilot.jrtx.site](https://relaypilot.jrtx.site/)

RelayPilot is not an "Xray GUI." RelayPilot owns profiles, rules, policy selection, DNS intent, connection history, deterministic decision traces, diagnostics, sync boundaries, and typed AI patches. Xray/libXray is the first protocol engine behind an adapter and may later coexist with a native engine or other implementations.

## Start here

Free architecture experiment with no sale, subscription or commercial activation. Existing source licence restrictions remain in force. Architecture alpha with a source CLI and a loopback engine slice. Desktop/mobile source foundations do not constitute released VPN, TUN or system-wide network clients.

[Installation, first use, privacy, backup and recovery](docs/USER-GUIDE.md) · [简体中文](docs/USER-GUIDE.zh-CN.md)

## What works today

- Canonical Relay Profile JSON with validation and round-trip serialization
- Surge-compatible import for `DOMAIN`, `DOMAIN-SUFFIX`, `IP-CIDR`, `IP-CIDR6`, `GEOIP`, `FINAL`, and `MATCH` syntax
- Deterministic local evaluation for exact domain, suffix, IPv4 CIDR, and final rules
- Select/fallback policy groups with cycle detection and stable selection
- `DecisionTrace`: rule source, policy resolution, selected outbound, steps, warnings, and stable trace ID
- Xray adapter slice for VLESS + RAW/TLS/REALITY, SOCKS ingress, `freedom`/`blackhole`, ordered routes, rule tags, source maps, canonical JSON, and SHA-256 identity
- Agent-first CLI (`validate` / `decide` / `compile` / `dry-run` / `import-surge` / `diagnose` / `version`): canonical JSON, exit codes that never lie, byte-level golden contract ([CLI-SPEC](docs/CLI-SPEC.md))
- Supervised Xray process runtime: pinned binary discovery, version query, `run -test` config validation, session start/stop lifecycle, bounded structured event bridge, and a real loopback SOCKS request through a local test endpoint
- Rivet RPC boundary for route explanation, engine compilation, dry runs, and engine session lifecycle
- Desktop UI: one web UI on the glaze carrier (the system WebView) for connect/overview, profiles, trace and settings, with a carrier-owned tray. Packaged for macOS, Windows and Linux; CI runs the product journey against the package on each
- Atomic local-folder storage boundary; provider-specific sync remains outside the profile model
- Typed `DiagnosticBundle`, secret redaction, and a validated `ConfigPatch` type (no AI caller is wired to it yet)
- 58 passing Racket tests with the pinned engine (42 without it; engine tests skip with a printed reason), plus a 20-case golden CLI suite
- CI: checksum-pinned Xray v26.3.27, release-identity and notice-pin checks, golden suite, and real engine session tests

The repository does **not** yet contain a runnable VPN app, TUN integration, a bundled Xray/libXray binary, background services, subscriptions, production DNS, or commercial infrastructure. What ships next is tracked in [ROADMAP.md](ROADMAP.md); the control-plane design in [ARCHITECTURE.md](ARCHITECTURE.md).

## First vertical slice

```text
Relay Profile
    ↓ validate
Surge-compatible rules
    ↓ first-match evaluation
Policy group selection
    ↓ deterministic DecisionTrace
EnginePlan + source map
    ↓ Xray adapter
Canonical Xray JSON + SHA-256
    ↓ supervised engine runtime (pinned Xray process)
Validate (`run -test`) · loopback SOCKS session · structured events
```

The same RelayPilot evaluator that explains a route is the source of the adapter plan. Unsupported local semantics are rejected at compilation instead of silently delegating truth to an engine. Every engine artifact identifies its adapter version, engine pin, deterministic digest, and source map; the runtime adds bounded execution evidence without ever rewriting the artifact.

## Platform status

| Platform | UI target | RelayPilot status |
|---|---|---|
| macOS | glaze carrier (system WebView) + native tray | Packaged (`dmg`, `zip`); product journey and tray self-checked in CI. Tag releases require Developer ID signing and notarization; not published |
| Windows | glaze carrier (WebView2) + native tray | Packaged (`msi`, `zip`), not code-signed; product journey and tray self-checked in CI. Not published |
| Linux | glaze carrier (WebKitGTK) + native tray | Packaged (`deb`, `rpm`, `AppImage`, `tar.gz`); self-checked in CI. The tray needs libayatana-appindicator3 (or libappindicator3), else it is absent |
| iOS / iPadOS | SwiftUI + NetworkExtension | Architecture only; not served by the glaze carrier, no native host |
| tvOS | SwiftUI + NetworkExtension | Architecture only; libXray cgo feasibility, not a product build |
| Android | Jetpack Compose + VpnService | Architecture only; no native host |

See [platform maturity](docs/platform-maturity.md) for the exact boundary.

## Install

No release is published yet. Once releases exist, install the packaged
artifact for your platform from
[GitHub Releases](https://github.com/turlamai/relaypilot/releases/latest)
(`dmg`/`zip` on macOS, `msi`/`zip` on Windows, `deb`/`rpm`/`AppImage`/`tar.gz`
on Linux) and verify it against the published `SHA256SUMS` before running it:

```bash
sha256sum --check --ignore-missing SHA256SUMS   # with the artifact in the same directory
```

The app verifies the Ed25519-signed `update-manifest.json` release asset
itself; a failed verification degrades to "no update", never to a
less-verified one.

## Build and test

Requires Racket CS 9.x and [Rivet](https://github.com/turlamai/rivet):

```bash
raco pkg install --auto --no-docs rivet
raco make racket/backend.rkt
raco test tests/
python3 shared/cli-golden/runner.py --binary scripts/relaypilot-cli.sh
```

With the pinned engine configured (`RELAYPILOT_XRAY_BIN=/path/to/xray`), the test suite additionally runs config validation and a real loopback SOCKS session through a supervised Xray process; without it, those tests skip with a printed reason.

The CLI is the executable slice (full contract in [docs/CLI-SPEC.md](docs/CLI-SPEC.md)):

```bash
scripts/relaypilot-cli.sh version
scripts/relaypilot-cli.sh validate examples/relay-profile.json
scripts/relaypilot-cli.sh decide examples/relay-profile.json --domain api.openai.com --port 443
scripts/relaypilot-cli.sh dry-run examples/relay-profile.json
scripts/relaypilot-cli.sh compile examples/relay-profile.json --out /tmp/xray.json
```

## Repository layout

```text
relaypilot/
├── rivet.rktd                 # Rivet application contract
├── racket/backend.rkt         # typed RPC backend (served inside the carrier via rivet/bridge)
├── racket/cli.rkt             # agent-facing CLI (docs/CLI-SPEC.md)
├── racket/core/
│   ├── profile/               # canonical Relay Profile
│   ├── rules/                 # Surge syntax + deterministic evaluator
│   ├── policy/                # group selection
│   ├── engines/               # adapter contract, Xray compiler, supervised runtime
│   ├── diagnostics/           # DecisionTrace bundles
│   ├── storage/               # local-first provider boundary
│   └── ai/                    # redaction + typed ConfigPatch
├── shared/cli-golden/         # byte-level CLI golden contract
├── tests/                     # domain, adapter, runtime and RPC contract tests
├── examples/                  # synthetic, non-secret profile and rules
├── scripts/                   # CLI launchers, release/notice checks
├── host/                      # glaze carrier + web UI (the desktop host)
├── docs/                      # product and engineering contracts
└── site/                      # static product site
```

## Product constraints

- Local-first. No required account, license server, RelayPilot cloud, or mandatory service.
- User-owned sync: iCloud Drive first on Apple; local folders and WebDAV across platforms.
- Desktop UI uses Glaze with system WebViews and native platform capabilities; Rivet carries typed application logic. Mobile hosts remain architecture targets.
- AI can explain or propose a typed, validated patch. It cannot directly mutate a live profile.
- Protocol engines are replaceable infrastructure. RelayPilot-specific semantics stay here.

The current goal is a safe, verifiable architecture alpha and an understandable local workflow. No commercial service, paid update window or purchasing feature is planned.

## License

Copyright © 2026 TurLamAI. No open-source license has been granted yet; the terms are stated in [LICENSE](LICENSE). Third-party engine distributions will carry their own notices and source-offer obligations.
