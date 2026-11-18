import SwiftUI
import RivetEmbedding
import RivetRuntime

@main
struct RelayPilotApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.store)
                .frame(minWidth: 1000, minHeight: 640)
                .task { model.start() }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandMenu(Lang.t("menu.go")) {
                ForEach(AppPage.allCases) { page in
                    Button(Lang.t(page.titleKey)) {
                        model.store.page = page
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(page.id.first!))),
                                      modifiers: .command)
                }
            }
            CommandGroup(after: .toolbar) {
                Button(Lang.t("menu.quickFind")) {
                    model.store.quickFindOpen = true
                }
                .keyboardShortcut("k", modifiers: .command)
                Divider()
                Picker(Lang.t("settings.theme"), selection: Binding(
                    get: { model.store.theme },
                    set: { model.store.setTheme($0) })) {
                    Text(Lang.t("theme.system")).tag("system")
                    Text(Lang.t("theme.light")).tag("light")
                    Text(Lang.t("theme.dark")).tag("dark")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
    }
}

/// Boots the embedded Racket backend and hands the generated API to the
/// store. The boot sequence mirrors the podlens host (same rivet runtime).
@MainActor
final class AppModel: ObservableObject {
    let store = RelayPilotStore()
    @Published var bootStatus = ""
    @Published var ready = false

    private var backend: EmbeddedRacketBackend?

    func start() {
        guard backend == nil else { return }
        store.applyTheme()
        installKeyMonitor()
        do {
            let config = try Self.runtimeConfiguration()
            let backend = EmbeddedRacketBackend(configuration: config)
            self.backend = backend
            try backend.start(onEvent: { [weak self] _, _ in
                // RelayPilot has no runtime events on the RVT1 channel yet;
                // session evidence stays engine-side and surfaces through
                // explicit RPCs.
                _ = self
            })
            let api = RivetAPI(client: backend.client)
            Task { [weak self] in
                await self?.finishBoot(api: api)
            }
        } catch {
            ready = false
            bootStatus = "Backend error: \(error)"
        }
    }

    private func finishBoot(api: RivetAPI) async {
        store.bind(api: api)
        ready = true
        bootStatus = ""
    }

    /// "/" focuses the current page's search field without hijacking text
    /// input (DESIGN.md 快速查找与键盘). ⌘K is handled by the menu shortcut.
    private func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 44, // physical slash key
               event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
               let firstResponder = NSApp.keyWindow?.firstResponder,
               !(firstResponder is NSText || firstResponder is NSTextView),
               !(firstResponder is NSTextField) {
                switch self.store.page {
                case .trace:
                    NotificationCenter.default.post(name: .relaypilotFocusTraceField,
                                                    object: nil)
                default:
                    NotificationCenter.default.post(name: .relaypilotFocusProfileSearch,
                                                    object: nil)
                    if self.store.page != .profiles {
                        self.store.page = .profiles
                    }
                }
                return nil
            }
            return event
        }
    }

    private static func runtimeConfiguration() throws -> EmbeddedRacketConfiguration {
        let executable = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL

        // Packaged apps keep Racket data in Contents/Resources. `raco rivet
        // dev` runs the staged executable directly, where runtime/res live
        // next to the executable.
        let roots = [
            Bundle.main.resourceURL,
            executable.deletingLastPathComponent()
        ].compactMap { $0 }

        for root in roots {
            let runtime = root.appendingPathComponent("runtime", isDirectory: true)
            let core = root.appendingPathComponent("res/core.zo")
            let required = [
                runtime.appendingPathComponent("petite.boot"),
                runtime.appendingPathComponent("scheme.boot"),
                runtime.appendingPathComponent("racket.boot"),
                core
            ]
            if required.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
                return EmbeddedRacketConfiguration(
                    executable: executable,
                    petiteBoot: required[0],
                    schemeBoot: required[1],
                    racketBoot: required[2],
                    core: core,
                    moduleName: RivetGeneratedConfig.moduleName,
                    entryName: RivetGeneratedConfig.entryName
                )
            }
        }
        throw RuntimeError.missingRuntime
    }

    enum RuntimeError: Error {
        case missingRuntime
    }
}
