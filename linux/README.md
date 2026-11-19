# Linux host

GTK4 host through Rivet — the third platform leg implementing the `design/`
v0.3 contract (issue #10). Four screens, real engine session lifecycle,
route checks with expectation compare, route patches with single-step undo,
Surge-subset import with the per-line unsupported report, and the rule
editor with validate-only preview. Bilingual via the generated i18n table;
light/dark token pairs follow the desktop theme.

Build and run (GTK4 + the embeddable Racket CS from rivet's setup action):

```bash
raco rivet build          # compiles backend + host, stages .rivet/stage
raco rivet dev            # run the staged host
```

Sessions need the pinned Xray binary (`RELAYPILOT_XRAY_BIN` or `xray` on
PATH); without it the UI stays honest — session start fails with the
engine-unavailable reason while library and route checks keep working.
`RELAYPILOT_LIBRARY_ROOT` overrides the profile library location.
