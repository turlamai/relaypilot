# Roadmap

## M0 — Control-plane vertical slice (current)

- [x] Canonical Relay Profile schema and validation
- [x] Surge rule-line import
- [x] Deterministic domain, suffix, IPv4 CIDR, and final evaluation
- [x] Policy group selection and DecisionTrace
- [x] EngineAdapter and Xray VLESS/REALITY compiler
- [x] Canonical engine artifact, SHA-256, and rule source map
- [x] Atomic local-folder storage boundary
- [x] DiagnosticBundle, redaction, and typed ConfigPatch
- [x] Rivet RPC boundary and tests

## M1 — First real engine session

- [x] Pin Xray v26.3.27 for configuration compatibility and record checksums/provenance
- [x] Validate generated configuration with that exact binary in CI
- [x] Supervised process lifecycle adapter (`racket/core/engines/runtime.rkt`): binary discovery, version query, `run -test` validation, session start/stop with bounded structured events
- [x] Real loopback SOCKS request through a supervised local engine session against a local test endpoint (CI + local, synthetic credentials only)
- [x] Credentials synthetic in CI; third-party notices/source-offer workflow (`scripts/third-party-notices.rkt`, `docs/third-party.md`)
- [ ] Pin the platform-specific libXray build used by the first runtime host (stays open until the first embedded runtime exists; the process pin above is separate)

## M2 — First usable desktop path

- [x] Implement the first desktop host — one web UI on the glaze carrier for macOS, Windows and Linux, with a native tray on each (2026-11-24, #13). The earlier macOS SwiftUI leg (#10) was retired with the other rivet native hosts
- [x] Connect/disconnect/status and a minimal connection/DecisionTrace inspector — engine-session lifecycle over RVT1 plus the real explain-route trace, expectation compare, and route patch
- [ ] Add the platform tunnel/service boundary without moving VPN semantics into Rivet
- [x] Import a real user-owned Surge profile subset and report unsupported fields — per-line import preview with placeholder-group mapping, wired through library-import RPCs
- [ ] Reserve the update-mechanism slot for the first shipped host: an Ed25519-signed update feed aligned with the family UPDATE contract (canonical copy: `turlamai/taskly` `shared/spec/UPDATE.md`); no auto-updater exists today and none ships before this contract is adopted here (release plan: [docs/distribution.md](docs/distribution.md))

## M3 — Cross-platform proof

- [x] Every declared desktop OS family served by the one carrier — the same package is built and self-checked (16-step product journey, native tray) on macOS, Windows and Linux x64/arm64 in CI (2026-11-24, #13)
- [ ] Sync the same canonical profile through a user-owned folder
- [ ] Prove the same decision fixtures on both platforms
- [ ] Add DNS policy execution and IPv6 parity before claiming network consistency

## Later

iOS/iPadOS/tvOS NetworkExtension, Android VpnService, Linux daemon/TUN, subscriptions, iCloud Drive, WebDAV, connection history, richer diagnosis, and carefully selected NativeEngine capabilities.

## 当前交付优先级（2026-10-23）

保留架构 Alpha，暂不销售。profile→DecisionTrace→adapter dry-run→诊断的可执行纵切已于 2026-10-23 交付：agent-first CLI（`docs/CLI-SPEC.md` + 20 例 golden 契约）、受监督 Xray 进程 runtime（pin v26.3.27）、回环 SOCKS 实测、事件桥、RPC dry-run/会话扩展、notices/source-offer 工作流。未完成的跨平台、硬件或真实支付验证仍是显式门禁；本节不表示这些验证已通过。目标平台仍未支持，不把架构能力写成产品能力。

执行场景与完成标准见[本仓审查 issue](https://github.com/turlamai/relaypilot/issues/1)及家族[交付标准](https://github.com/turinglambdaai/turinglambdaai.github.io/blob/master/docs/PRODUCT-STANDARD.md)。后续一次认领一个切片，证据回填本文件与 issue。尚未认领的切片：M2 的平台隧道/服务边界（M1 的 libXray 固定版本随之）、M3 的配置同步与 DNS/IPv6，以及 `racket/core/ai/patch.rkt` 的调用方（`ConfigPatch` 目前只有类型与校验，CLI、backend 和载体都不调用它）。
