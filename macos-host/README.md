# macOS host

SwiftUI/AppKit host through Rivet — the M2 anchor leg (issue #10). Implements
the `design/` v0.3 contract: Overview (engine session lifecycle + attention
items), Route Check (real DecisionTrace, expectation compare, route patch),
Profiles (Surge-subset import with per-line unsupported report, rule editor,
switch/delete), and Settings. Bilingual via `shared/i18n`; light/dark token
pairs mirror `design/prototype/shared.css`.

Build and run:

```bash
raco rivet build          # compiles backend + host, stages .rivet/stage
raco rivet package        # dist/relaypilot.app + launch smoke
raco rivet acceptance     # contract/bridge/native-build/native-ui suites
```

Sessions need the pinned Xray binary: set `RELAYPILOT_XRAY_BIN` (see the
runtime discovery in `racket/core/engines/runtime.rkt`). Without it the UI
stays honest — session start fails with the engine-unavailable reason while
library and route checks keep working.

`RELAYPILOT_LIBRARY_ROOT` overrides the profile library location (scriptable
runs and acceptance isolation); default is
`~/Library/Application Support/ai.turinglambda.relaypilot/library`.
