# Platform legs

Native hosts implement the `design/` contract over the same RVT1 backend.

| Leg | Status | Stack | Notes |
|---|---|---|---|
| macOS (`macos-host/`) | **running** (M2 anchor leg, issue #10) | SwiftUI/AppKit, SwiftPM, embedded Racket | sessions need `RELAYPILOT_XRAY_BIN`; see `macos-host/README.md` |
| Windows (`windows/`) | planned | WinUI 3 / C++/WinRT | short-lived `leg/win-*` branches per family rules |
| Linux (`linux/`) | planned | GTK4 | embeds the static Racket CS via rivet's setup action |
| Android (`android/`) | future (Later roadmap) | Compose | companion API only when the desktop path is proven |
| Apple mobile (`apple/`) | future (Later roadmap) | SwiftUI / NetworkExtension | deferred with the iOS roadmap item |

Stub directories keep an honest README until their host lands; platform
claims follow AGENTS.md truthfulness rules — nothing is "supported" before
its host and a real data path are verified on the target OS.
