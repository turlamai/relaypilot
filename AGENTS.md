# RelayPilot agent contract

## 家族设计（必读入口）

- 设计/UI 任务先加载 `tlai-product`，必读 `references/policy.md` 与 `references/design-standard.md`（理念、决策规则、UI 验收）。技能缺失时读取 ZCode 真源：macOS/Linux `~/Sync/ZCode/skills/tlai-product/`；Windows `D:/ZCode/skills/tlai-product/`。无法读取须报告规范未核验，不凭记忆跳过。
- 家族规范管共性；本仓现有设计、行为与 token 真源管具体值和产品差异。例外记回原契约，不复制家族规则或新增数值表；已有界面按下一次相关切片渐进对齐。
- 改界面先改原型、落账后实现；按家族 UI 清单与本仓当前技术线的既有门禁验收，原型对照和真实交互证据都要保留；对外宣传使用验收后的实物截图。

## 实现路由（agent 按任务读真源）

- 实现界面以 `design/prototype/` 为准：对照 HTML/CSS/JS 与实物截图验收，不依赖散文复述。
- Token/几何值真源 = `design/prototype/shared.css`（亮暗成对；原型 v0.3 契约 2026-11-18 落账）；`design/DESIGN.md` 记语义名、亮暗成对关系与决策，值以 shared.css 为准。
- 行为边界与跨平台一致性以 `design/DESIGN.md` 的不变式与平台差异节为准。
- 改界面先改原型再改实现（tlai-product）；动共享层（design/、shared/）先 issue 声明，同 commit 落契约。

## Current owner decision — 2026-11-23 UI line: rivet → glaze (#13)

RelayPilot's desktop UI is re-lined from rivet native hosts to **glaze** (system WebView + one web UI). Read `host/README.md` for the carrier and the slice plan. Rules while the re-line is in flight (S0–S5):

- The Racket control plane (`racket/`), `rivet-schema.json`, the CLI and `shared/i18n` are **Keep**: no engine, schema or RPC changes ride the re-line.
- The web UI is evolved from `design/prototype/` (the UI baseline); tokens single-source in `design/prototype/shared.css`, strings single-source in `shared/i18n`. Never commit copies into `host/web/`.
- `host/main.rkt` `api` is the route surface; `glaze-schema.json` is its committed baseline (`raco glaze schema write` + `check`). Harness routes stay inert unless `RELAYPILOT_E2E=1`.
- The former rivet native legs (`macos-host/`, `windows/`, `linux/`) and the `apple/`, `android/` placeholder dirs were retired in S4 (2026-11-24, supersedes the fold task in #11): the glaze carrier is the only desktop host, and mobile stays native per the family rule when its roadmap item starts. History on `main` keeps them (`git log -- macos-host/`). The "Rivet boundary" section below still governs the engine side and stays in force for RVT1/embedding/runtime.

## Current owner decision — 2026-11-18 quality-first

This product is in **non-commercial development**. The prior 2026-10/11 product pricing, trial, paid-feature, Free/Pro and family Permit/Commerce rollout decisions are canceled. Do not introduce checkout, subscriptions, activation, commercial entitlement, paid update windows or a paywall. Do not change source-license terms or release signing and identity verification. Prioritize product correctness, reliable native experience, recovery, bilingual README and truthful website claims. The [current family portfolio](https://github.com/turlamai/turlamai.github.io/blob/master/PORTFOLIO.md) governs every slice.

## Product boundary

- RelayPilot is an independent local-first network toolbox. Proxying is foundational, not the product boundary.
- Keep canonical profiles, rules, policy selection, DNS intent, connections, DecisionTrace, diagnostics, storage/sync, and AI patches inside RelayPilot.
- Treat Xray/libXray as an `EngineAdapter`, never as RelayPilot's data model.
- Do not invent new proxy protocols or begin a ground-up proxy core rewrite.

## Rivet boundary

- Preserve Racket application logic and first-party native UIs: SwiftUI/AppKit, WinUI 3, GTK4, and Compose.
- Do not introduce a cross-platform UI DSL or alter RVT1/embedding/runtime for product-specific needs.
- Keep VPN/TUN/service/engine semantics here. Open a Rivet issue or PR only after demonstrating a generally useful application primitive.

## Truthfulness

- Do not mark a platform supported until its native host and a real data path are verified.
- Every engine artifact must identify adapter version, engine version or pending boundary, deterministic digest, and source map.
- Unsupported imported syntax must produce a precise diagnostic. Never silently change semantics.
- AI never writes a live profile directly. Redact, validate a typed patch, simulate, preview, then require user apply.

## Verification

Run before submitting changes:

```bash
raco make racket/backend.rkt
raco test tests/
python3 shared/cli-golden/runner.py --binary scripts/relaypilot-cli.sh
scripts/check-release-version.sh
racket scripts/third-party-notices.rkt --check
```

With `RELAYPILOT_XRAY_BIN` pointing at the pinned Xray binary, `raco test tests/` additionally runs config validation and a real loopback SOCKS session through a supervised engine process; without it those tests skip with a printed reason — a skip is not a pass.

Runtime/host changes need an end-to-end test on their target OS. Apple native validation belongs on macOS CI; do not claim it from Windows.

## CLI contract

- The CLI is implemented once in `racket/cli.rkt`; launchers are thin shims (`scripts/relaypilot-cli.sh` / `.cmd`). Do not add a second implementation path.
- Behavior changes land in `docs/CLI-SPEC.md` first, then re-record `shared/cli-golden/` with `--record` and review the diff; never edit golden bytes by hand and never delete a case to get green.
- Engine-dependent golden behavior is intentionally out of the golden contract; the runner strips `RELAYPILOT_XRAY_BIN`.


## 产品交付与下一步（2026-11-18）

请以当前代码与验收证据推进用户主流程、恢复、跨平台原生体验、签名更新、文档和产品主页，不按任何历史商业规划开发。

## 组合定位（Portfolio placement）

2026-11-18 起，以产品交付质量为目标，不推进收费版、试用、商业授权或结账。既有 LICENSE 和发行签名验证保持不变。当前权威是[产品组合策略](https://github.com/turlamai/turlamai.github.io/blob/master/PORTFOLIO.zh-CN.md)。

## Documentation languages

Public default documentation is English; maintain complete Chinese user paths in `*.zh-CN.md`, with reciprocal links. Update both languages when prices, quotas, installation, recovery, privacy or supported platforms change. API/protocol identifiers and commands remain unchanged; do not maintain a second normative protocol or implementation. Follow the [family language policy](https://github.com/turlamai/turlamai.github.io/blob/master/docs/DOCUMENTATION-LANGUAGES.md). Existing internal notes are not a claim that every document is bilingual.

## Public product documentation

The paired `docs/USER-GUIDE.md` / `docs/USER-GUIDE.zh-CN.md` own the public installation, first-use, data/recovery, privacy and availability path. Keep the homepage and both README entry points aligned with them when behavior changes. Detailed technical contracts and the current implementation queue retain their existing owners. Do not publish target prices, a purchase link or a ready/secure/platform claim before its release evidence exists.
