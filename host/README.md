# host/ — glaze carrier

RelayPilot's desktop UI runs on **glaze** (system WebView + HTML/CSS/JS UI) per the owner
decision of 2026-11-23 (relaypilot#13: re-line from rivet to glaze). This directory is the
carrier: the Racket process that opens the native window, serves the web UI and exposes the
typed RPC surface to the page.

| Path | Role |
|---|---|
| `main.rkt` | Carrier entry. `api` is the route list `glaze.rktd` points at; `raco glaze schema write` regenerates `glaze-schema.json` from it. |
| `verify.rkt` | Real-window launch smoke + journey evidence (PNG + typed report in `.glaze/verify/`). Run on every declared platform. |
| `linux-verify.sh` | Headless Linux CI wrapper (session bus on `/run/user`, Xvfb). |
| `web/index.html` + `app.js` + `app.css` | The product UI (overview/connect + profile library). Tokens come single-source from `design/prototype/shared.css`, copied into the runtime public dir at startup — never committed here. Strings come from `shared/i18n` via `api/host/i18n`. |
| `web/probe.html` + `probe.js` | The RPC surface journey page (S0/S1 evidence); not a product screen. |
| `web/e2e.js` | In-page product journey, imported by `app.js` only when `?e2e=1` and the host gate is on. |

## Slices (one PR each, `main` stays green)

- **S0** carrier skeleton: app shell, transport, runtime public dir, i18n route, harness gate, four-OS launch smoke (`host-ci.yml`).
- **S1** RPC bridge: the 18 RPCs of `rivet-schema.json` exposed 1:1 over `rivet/bridge` (in-process RVT1 pipe pair); `scripts/check-rpc-surface.py` gates the route surface against the schema.
- **S2** overview/connect + profiles: session start/stop through `engine-dry-run` → `engine-session-*`, saved targets explained by `explain-route`, the single-target route patch (`library-patch-preview/apply`), the rule editor (`library-validate-rules` → `library-update-rules`), import preview/commit, switch and delete. Every mutation offers one-step undo through `library-restore-profile` (switch undo = `library-set-active` back). The page never decides or validates anything itself.
- **S3** trace + diagnostics: the route check view is `explain-route` laid out (expectation comparison is local and only lists mismatches on the overview), the decision steps are the engine's own `steps` text; diagnostic export = `diagnose-route` → native save panel (`api/dialog/save`) → `api/host/write`, scoped by the `relaypilot` capability (`dialog:save`, `host:write`). Redaction defaults to on.
- **S4** settings + tray/menu status: the settings view (theme via `html[data-theme]`, redaction shared with route check, diagnostic export, quick find `Ctrl/⌘ K`) and the carrier-owned tray. After every render the page posts the menu it wants to `api/host/tray_state` (localized labels, the active profile checked, a tooltip); the host rebuilds the native menu (`glaze/tray`), and a pick comes back over `glaze/events` as `relaypilot-menu` so it runs the same action path as a page button (`show` refocuses the window, `quit` stops the session through the page then `api/host/quit`). A platform without a tray backend degrades to the inert stub. The page opens the event stream once its first screen is up; under the harness only the journey's tray step opens it, because on Linux a window capture taken while the stream is open kills the carrier (glaze#165). The rivet native host dirs (`macos-host/`, `windows/`, `linux/`, `apple/`, `android/`) and their CI jobs are retired here.
- **S5** acceptance + packaging launch smoke + the v0.1.0 line.

## Run

```bash
racket host/main.rkt          # production carrier (HTTP adapter on loopback, per-launch token)
raco glaze dev                # development
RELAYPILOT_TRANSPORT=native racket host/main.rkt   # GLZ1 native carrier
racket host/verify.rkt        # real-window evidence: probe journey, then product journey
```

## Library root

`api/host/context` hands the page the profile library root; every library RPC receives it
back. Resolution order: `RELAYPILOT_LIBRARY_ROOT` (scriptable runs, acceptance isolation),
else the per-user app data dir for the identifier in `rivet.rktd`
(`%LOCALAPPDATA%\ai.turinglambda.relaypilot\library`,
`~/Library/Application Support/ai.turinglambda.relaypilot/library`,
`$XDG_DATA_HOME/ai.turinglambda.relaypilot/library`).

## Harness

Routes under `api/host/e2e*` are inert unless `RELAYPILOT_E2E=1`. With the gate on the
product context resolves to one disposable library per process; `api/host/e2e_reset`
rotates it and clears the report. The probe journey always gets its own fresh root.
