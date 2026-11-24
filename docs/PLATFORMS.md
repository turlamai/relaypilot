# Platform legs

RelayPilot's desktop host is the **glaze carrier** in `host/`: one web UI in
the system WebView, with tray and menu status owned by the carrier. It
implements the `design/` contract over the same RVT1 backend on every
declared desktop platform (see `host/README.md` for the slice plan).

| Platform | Carrier | Status |
|---|---|---|
| macOS | system WebView (WKWebView) | carrier boots in CI; packaging and launch smoke land with S5 |
| Windows | WebView2 | carrier boots in CI; packaging and launch smoke land with S5 |
| Linux | WebKitGTK (libayatana tray where present) | carrier boots in CI under Xvfb; packaging and launch smoke land with S5 |

The former rivet native legs (`macos-host/`, `windows/`, `linux/`) and the
`apple/`, `android/` placeholder directories were retired with the glaze
re-line on 2026-11-24 and remain in `main` history
(`git log -- macos-host/`). Mobile is not served by the glaze carrier: the
family rule is a native app per platform (iOS/iPadOS Swift, Android Kotlin),
started only when the mobile roadmap item does.

Platform claims follow the AGENTS.md truthfulness rules — nothing is
"supported" before its host and a real data path are verified on the target
OS.
