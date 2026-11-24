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
| `web/` | The web UI. Tokens come single-source from `design/prototype/shared.css`, copied into the runtime public dir at startup — never committed here. Strings come from `shared/i18n` via `api/host/i18n`. |

## Slices (one PR each, `main` stays green)

- **S0** carrier skeleton: app shell, transport, runtime public dir, i18n route, harness gate, four-OS launch smoke (`host-ci.yml`).
- **S1** RPC bridge: the 18 RPCs of `rivet-schema.json` exposed 1:1 over `rivet/bridge` (in-process RVT1 pipe pair); `scripts/check-rpc-surface.py` gates the route surface against the schema.
- **S2–S4** product screens evolved from `design/prototype/`: connect/overview + profiles, trace + diagnostics export, settings + tray/menu carrier routes.
- **S5** acceptance + v0.1.0 line; the rivet stub legs and their CI jobs are retired in S4.

## Run

```bash
racket host/main.rkt          # production carrier (HTTP adapter on loopback, per-launch token)
raco glaze dev                # development
RELAYPILOT_TRANSPORT=native racket host/main.rkt   # GLZ1 native carrier
racket host/verify.rkt        # real-window evidence (graphical session)
```

Harness routes under `api/host/e2e*` are inert unless `RELAYPILOT_E2E=1`.
