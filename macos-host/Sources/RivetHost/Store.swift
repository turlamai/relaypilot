import SwiftUI
import RivetEmbedding
import RivetRuntime

enum AppPage: String, CaseIterable, Identifiable {
    case overview, trace, profiles, settings

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .overview: return "nav.overview"
        case .trace: return "nav.trace"
        case .profiles: return "nav.profiles"
        case .settings: return "nav.settings"
        }
    }
}

enum SessionPhase: Equatable {
    case idle
    case starting
    case running
}

struct ActivityEvent: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    let text: String
}

/// One captured undo step. `profiles` maps profile id to its canonical JSON;
/// a nil value records that the profile did not exist before the change, so
/// undo can both restore and remove.
struct UndoSnapshot {
    let activeId: String
    let profiles: [String: String?]
}

struct ImportFlow {
    var name = ""
    var text = ""
    var stage: Stage = .input
    var preview: RivetTypes.ImportPreview?
    var acknowledged = false
    var error: String?

    enum Stage { case input, preview }
}

struct EditorFlow {
    let profileId: String
    let profileName: String
    let isActive: Bool
    let originalText: String
    var text = ""
    var stage: Stage = .edit
    var issues: [RivetTypes.ProfileIssue] = []

    enum Stage { case edit, confirm }
}

struct PatchFlow {
    let target: String
    var policy = "DIRECT"
    var stage: Stage = .edit
    var preview: RivetTypes.PatchPreview?
    var error: String?

    enum Stage { case edit, confirm }
}

struct PendingItem: Identifiable {
    enum Kind {
        case profile(String)
        case mismatch(String)
    }

    let id: String
    let kind: Kind

    var profileId: String? {
        if case .profile(let id) = kind { return id }
        return nil
    }

    var target: String? {
        if case .mismatch(let target) = kind { return target }
        return nil
    }
}

extension Notification.Name {
    static let relaypilotFocusTraceField = Notification.Name("relaypilotFocusTraceField")
    static let relaypilotFocusProfileSearch = Notification.Name("relaypilotFocusProfileSearch")
    static let relaypilotOpenQuickFind = Notification.Name("relaypilotOpenQuickFind")
}

@MainActor
final class RelayPilotStore: ObservableObject {
    @Published var page: AppPage = .overview
    @Published var snapshot: RivetTypes.LibrarySnapshot?
    @Published var phase: SessionPhase = .idle
    @Published var sessionId: String?
    @Published var engineVersion: String?

    @Published var traceInput = ""
    @Published var traceTarget: String?
    @Published var traceDecision: RivetTypes.RouteDecision?
    @Published var traceArtifact: RivetTypes.CompiledEngineConfig?
    @Published var traceBusy = false
    @Published var traceError: String?

    @Published var savedTargets: [String] = []
    @Published var expectations: [String: String] = [:]
    @Published var routeCache: [String: RivetTypes.RouteDecision] = [:]

    @Published var events: [ActivityEvent] = []
    @Published var toast: Toast?
    @Published var canUndo = false

    @Published var theme = "system"
    @Published var redact = true

    @Published var sessionConfirm: SessionPhase?
    @Published var importFlow: ImportFlow?
    @Published var editorFlow: EditorFlow?
    @Published var patchFlow: PatchFlow?
    @Published var switchFlow: RivetTypes.LibraryEntry?
    @Published var deleteFlow: RivetTypes.LibraryEntry?

    @Published var quickFindOpen = false
    @Published var quickFindQuery = ""

    @Published var profilesQuery = ""
    @Published var profilesFilter = "all"
    @Published var selectedProfileId: String?

    private(set) var api: RivetAPI?
    private var undoSnapshot: UndoSnapshot?
    private let defaults = UserDefaults.standard
    var libraryRoot: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        libraryRoot = support
            .appendingPathComponent(RivetGeneratedConfig.identifier, isDirectory: true)
            .appendingPathComponent("library", isDirectory: true)
        theme = defaults.string(forKey: "relaypilot-theme") ?? "system"
        redact = defaults.object(forKey: "relaypilot-redact") as? Bool ?? true
        savedTargets = defaults.stringArray(forKey: "relaypilot-saved-targets") ?? []
        if let stored = defaults.dictionary(forKey: "relaypilot-expectations") as? [String: String] {
            expectations = stored
        }
    }

    func bind(api: RivetAPI) {
        self.api = api
        Task { await refreshLibrary() }
    }

    // MARK: derived library facts

    var activeEntry: RivetTypes.LibraryEntry? {
        guard let snapshot else { return nil }
        return snapshot.profiles.first { $0.id == snapshot.activeProfileId }
    }

    func entry(id: String) -> RivetTypes.LibraryEntry? {
        snapshot?.profiles.first { $0.id == id }
    }

    /// Pending = invalid profiles + saved targets whose expectation differs.
    var pendingItems: [PendingItem] {
        var items: [PendingItem] = []
        for profile in snapshot?.profiles ?? [] where profile.status != "valid" {
            items.append(PendingItem(id: "profile-\(profile.id)", kind: .profile(profile.id)))
        }
        for target in savedTargets {
            guard let expected = expectations[target],
                  let decision = routeCache[target] else { continue }
            if decision.policy != expected {
                items.append(PendingItem(id: "target-\(target)", kind: .mismatch(target)))
            }
        }
        return items
    }

    var defaultRouteName: String {
        // The FINAL rule's policy is the default route; the decision for any
        // target that reaches FINAL shows the same resolution. Ask the engine
        // through a cached decision when available, else the raw policy.
        if let entry = activeEntry {
            return Lang.policyName(finalPolicy(entry) ?? "")
        }
        return Lang.t("fact.defaultRoute.none")
    }

    private func finalPolicy(_ entry: RivetTypes.LibraryEntry) -> String? {
        guard let json = activeProfileJSON, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = object["rules"] as? [String] else { return nil }
        for rule in rules.reversed() {
            let parts = rule.split(separator: ",").map(String.init)
            if parts.first?.uppercased() == "FINAL" || parts.first?.uppercased() == "MATCH" {
                return parts.count > 1 ? parts[1] : nil
            }
        }
        return nil
    }

    // MARK: strings

    private func rulesTextJSON(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rules = object["rules"] as? [String] else { return [] }
        return rules
    }

    // MARK: activity + toasts

    func addEvent(_ text: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            events.insert(ActivityEvent(time: Date(), text: text), at: 0)
            if events.count > 8 { events.removeLast(events.count - 8) }
        }
    }

    func showToast(_ message: String, undoable: Bool = false) {
        toast = Toast(message: message, undoable: undoable)
    }

    // MARK: library

    func refreshLibrary() async {
        guard let api else { return }
        do {
            try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
            let snapshot = try await api.library_list(root: libraryRoot.path)
            self.snapshot = snapshot
            if selectedProfileId == nil || entry(id: selectedProfileId ?? "") == nil {
                selectedProfileId = snapshot.profiles.first?.id
            }
            if snapshot.profiles.isEmpty {
                activeProfileJSON = nil
                routeCache.removeAll()
            } else {
                await refreshActiveProfileJSON()
                await refreshTargetRoutes()
            }
        } catch {
            showToast(String(format: Lang.t("library.loadFailed"), error.localizedDescription))
        }
    }

    @Published private(set) var activeProfileJSON: String?

    private func refreshActiveProfileJSON() async {
        guard let api, let active = activeEntry else {
            activeProfileJSON = nil
            return
        }
        activeProfileJSON = try? await api.library_read_profile(root: libraryRoot.path, profileId: active.id)
    }

    private func refreshTargetRoutes() async {
        guard let api, let json = activeProfileJSON else { return }
        for target in savedTargets {
            if let decision = try? await api.explain_route(profileJson: json,
                                                           domain: target, ip: "", port: 443,
                                                           network: "tcp") {
                routeCache[target] = decision
            } else {
                routeCache.removeValue(forKey: target)
            }
        }
    }

    private func captureUndo() async {
        guard let snapshot else { return }
        var profiles: [String: String?] = [:]
        for profile in snapshot.profiles {
            profiles[profile.id] = try? await api?.library_read_profile(
                root: libraryRoot.path, profileId: profile.id)
        }
        undoSnapshot = UndoSnapshot(activeId: snapshot.activeProfileId, profiles: profiles)
        canUndo = true
    }

    func undo() async {
        guard let api, let snapshot = undoSnapshot else { return }
        do {
            var touched = false
            for (id, json) in snapshot.profiles {
                if let json {
                    _ = try await api.library_restore_profile(root: libraryRoot.path, profileJson: json)
                    touched = true
                } else if FileManager.default.fileExists(
                    atPath: libraryRoot.appendingPathComponent("\(id).relayprofile.json").path) {
                    _ = try? await api.library_delete_profile(root: libraryRoot.path, profileId: id)
                    touched = true
                }
            }
            if snapshot.activeId != self.snapshot?.activeProfileId {
                _ = try await api.library_set_active(root: libraryRoot.path, profileId: snapshot.activeId)
                touched = true
            }
            undoSnapshot = nil
            canUndo = false
            await refreshLibrary()
            if touched { addEvent(Lang.t("undo.done")) }
            showToast(Lang.t("undo.done"))
        } catch {
            showToast(String(format: Lang.t("common.error"), error.localizedDescription))
        }
    }

    // MARK: session lifecycle

    func startSession() async {
        guard let api, phase == .idle, let json = activeProfileJSON else { return }
        phase = .starting
        do {
            let handle = try await api.engine_session_start(profileJson: json, socksPort: 0)
            sessionId = handle.sessionId
            engineVersion = handle.engineVersion
            phase = .running
            addEvent(Lang.t("session.started"))
            showToast(Lang.t("session.started"))
        } catch {
            phase = .idle
            addEvent("\(Lang.t("session.startFailed")) \(error.localizedDescription)")
            showToast("\(Lang.t("session.startFailed")) \(error.localizedDescription)")
        }
    }

    func stopSession() async {
        guard let api, let id = sessionId else { return }
        do {
            _ = try await api.engine_session_stop(sessionId: id)
        } catch {
            // The supervised process already exits on its own in failure
            // cases; report honestly either way.
            addEvent("\(Lang.t("session.stopped")) \(error.localizedDescription)")
        }
        sessionId = nil
        engineVersion = nil
        phase = .idle
        addEvent(Lang.t("session.stopped"))
        showToast(Lang.t("session.stopped"))
    }

    // MARK: trace

    static let domainPattern = "^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*$"

    static func isValidDomain(_ value: String) -> Bool {
        guard value.count <= 253 else { return false }
        return value.range(of: domainPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    func inspect(target raw: String? = nil) async {
        guard let api else { return }
        let value = (raw ?? traceInput).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let json = activeProfileJSON else {
            traceError = Lang.t("trace.cause.none")
            return
        }
        if !Self.isValidDomain(value) {
            traceError = Lang.t("trace.error.domain")
            return
        }
        traceError = nil
        traceInput = value
        traceTarget = value
        traceBusy = true
        do {
            let decision = try await api.explain_route(profileJson: json, domain: value,
                                                       ip: "", port: 443, network: "tcp")
            traceDecision = decision
            routeCache[value] = decision
            // The deterministic engine artifact makes the technical panel's
            // adapter/digest facts real (DESIGN.md 不变式 2).
            traceArtifact = try? await api.compile_engine_config(profileJson: json)
        } catch {
            traceDecision = nil
            traceArtifact = nil
            traceError = error.localizedDescription
        }
        traceBusy = false
    }

    func saveTarget() {
        guard let target = traceTarget else { return }
        if !savedTargets.contains(target) {
            savedTargets.append(target)
            persistTargets()
            showToast(Lang.t("trace.savedTarget"))
        }
    }

    func removeTarget(_ target: String) {
        savedTargets.removeAll { $0 == target }
        expectations.removeValue(forKey: target)
        persistTargets()
        persistExpectations()
        showToast(Lang.t("trace.removedTarget"))
        Task { await refreshLibrary() }
    }

    func setExpectation(_ target: String, _ policy: String?) {
        if let policy {
            expectations[target] = policy
        } else {
            expectations.removeValue(forKey: target)
        }
        persistExpectations()
        objectWillChange.send()
    }

    private func persistTargets() {
        defaults.set(savedTargets, forKey: "relaypilot-saved-targets")
    }

    private func persistExpectations() {
        defaults.set(expectations, forKey: "relaypilot-expectations")
    }

    // MARK: route patch

    func patchPreview(policy: String) async {
        guard let api, let entry = activeEntry else { return }
        guard let target = traceTarget else { return }
        var flow = patchFlow ?? PatchFlow(target: target)
        flow.policy = policy
        flow.error = nil
        do {
            let preview = try await api.library_patch_preview(root: libraryRoot.path,
                                                              profileId: entry.id,
                                                              target: target,
                                                              policy: policy)
            if preview.sameAsCurrent {
                patchFlow = nil
                showToast(Lang.t("patch.same"))
                return
            }
            flow.preview = preview
            flow.stage = .confirm
            patchFlow = flow
        } catch {
            flow.error = error.localizedDescription
            patchFlow = flow
        }
    }

    func patchApply() async {
        guard let api, let entry = activeEntry, let flow = patchFlow else { return }
        do {
            await captureUndo()
            _ = try await api.library_patch_apply(root: libraryRoot.path,
                                                  profileId: entry.id,
                                                  target: flow.target,
                                                  policy: flow.policy)
            patchFlow = nil
            addEvent(Lang.t("patch.applied"))
            showToast(Lang.t("patch.applied"), undoable: true)
            await refreshLibrary()
            await inspect(target: flow.target)
        } catch {
            showToast(String(format: Lang.t("common.error"), error.localizedDescription))
        }
    }

    // MARK: profiles

    func selectProfile(_ id: String) {
        selectedProfileId = id
    }

    func openProfile(_ id: String) {
        profilesQuery = ""
        profilesFilter = "all"
        selectedProfileId = id
        page = .profiles
    }

    func useProfile(_ entry: RivetTypes.LibraryEntry) async {
        guard let api, entry.status == "valid" else { return }
        do {
            await captureUndo()
            _ = try await api.library_set_active(root: libraryRoot.path, profileId: entry.id)
            switchFlow = nil
            addEvent(Lang.t("switch.done"))
            showToast(Lang.t("switch.done"), undoable: true)
            await refreshLibrary()
        } catch {
            showToast(String(format: Lang.t("common.error"), error.localizedDescription))
        }
    }

    func deleteProfile(_ entry: RivetTypes.LibraryEntry) async {
        guard let api else { return }
        guard entry.id != snapshot?.activeProfileId else {
            showToast(Lang.t("delete.activeRefused"))
            return
        }
        do {
            await captureUndo()
            _ = try await api.library_delete_profile(root: libraryRoot.path, profileId: entry.id)
            deleteFlow = nil
            if selectedProfileId == entry.id { selectedProfileId = nil }
            addEvent(Lang.t("delete.done"))
            showToast(Lang.t("delete.done"), undoable: true)
            await refreshLibrary()
        } catch {
            showToast(String(format: Lang.t("common.error"), error.localizedDescription))
        }
    }

    // MARK: rule editor

    func rulesList(for entry: RivetTypes.LibraryEntry) async -> [String] {
        guard let json = try? await api?.library_read_profile(
            root: libraryRoot.path, profileId: entry.id) else { return [] }
        return rulesTextJSON(json)
    }

    func openEditor(_ entry: RivetTypes.LibraryEntry) async {
        let text = (await rulesList(for: entry)).joined(separator: "\n")
        editorFlow = EditorFlow(profileId: entry.id,
                                profileName: entry.name,
                                isActive: entry.id == snapshot?.activeProfileId,
                                originalText: text,
                                text: text)
    }

    func editorValidate() async {
        guard let api, var flow = editorFlow, let entry = entry(id: flow.profileId) else { return }
        do {
            // Validate-only RPC: the engine reports issues without writing,
            // so the confirm stage always shows a saveable rule set.
            let issues = try await api.library_validate_rules(root: libraryRoot.path,
                                                              profileId: entry.id,
                                                              rulesText: flow.text)
            flow.issues = issues
            if issues.isEmpty { flow.stage = .confirm }
            editorFlow = flow
        } catch {
            flow.issues = [RivetTypes.ProfileIssue(index: 0, code: "error", detail: error.localizedDescription)]
            editorFlow = flow
        }
    }

    func editorSave() async {
        guard let api, let flow = editorFlow else { return }
        do {
            await captureUndo()
            let result = try await api.library_update_rules(root: libraryRoot.path,
                                                            profileId: flow.profileId,
                                                            rulesText: flow.text)
            editorFlow = nil
            addEvent("\(Lang.t("editor.saved")) \(flow.profileName)")
            showToast(Lang.t("editor.saved"), undoable: true)
            await refreshLibrary()
            _ = result
        } catch {
            var flow = flow
            flow.stage = .edit
            flow.issues = [RivetTypes.ProfileIssue(index: 0, code: "error", detail: error.localizedDescription)]
            editorFlow = flow
        }
    }

    // MARK: import

    func importPreview() async {
        guard let api, var flow = importFlow else { return }
        let name = flow.name.trimmingCharacters(in: .whitespacesAndNewlines)
        flow.error = nil
        guard !name.isEmpty, name.count <= 80 else {
            flow.error = Lang.t("import.error.name")
            importFlow = flow
            return
        }
        do {
            let preview = try await api.library_import_preview(root: libraryRoot.path,
                                                               name: name, text: flow.text)
            if preview.importableRules.isEmpty {
                flow.error = Lang.t("import.error.empty")
                importFlow = flow
                return
            }
            flow.preview = preview
            flow.acknowledged = preview.unsupported.isEmpty
            flow.stage = .preview
            importFlow = flow
        } catch {
            flow.error = error.localizedDescription
            importFlow = flow
        }
    }

    func importCommit() async {
        guard let api, let flow = importFlow, let preview = flow.preview else { return }
        guard flow.acknowledged || preview.unsupported.isEmpty else { return }
        do {
            await captureUndo()
            let name = flow.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await api.library_import_commit(root: libraryRoot.path,
                                                             name: name,
                                                             description: "",
                                                             text: flow.text)
            importFlow = nil
            selectedProfileId = result.profileId
            addEvent(Lang.t("import.created"))
            showToast(Lang.t("import.created"), undoable: true)
            page = .profiles
            await refreshLibrary()
        } catch {
            var retry = flow
            retry.stage = .input
            retry.error = error.localizedDescription
            importFlow = retry
        }
    }

    // MARK: diagnostics export

    func exportDiagnostics() async {
        guard let api, let json = activeProfileJSON, let target = traceTarget else { return }
        do {
            let bundle = try await api.diagnose_route(profileJson: json, domain: target,
                                                      ip: "", port: 443, network: "tcp",
                                                      redact: redact)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "relaypilot-diagnostic.json"
            panel.allowedContentTypes = [.json]
            if panel.runModal() == .OK, let url = panel.url {
                try bundle.write(to: url, atomically: true, encoding: .utf8)
                showToast(Lang.t("settings.export.done"))
            }
        } catch {
            showToast(String(format: Lang.t("common.error"), error.localizedDescription))
        }
    }

    // MARK: preferences

    func setTheme(_ value: String) {
        theme = value
        defaults.set(value, forKey: "relaypilot-theme")
        applyTheme()
    }

    func setRedact(_ value: Bool) {
        redact = value
        defaults.set(value, forKey: "relaypilot-redact")
    }

    func applyTheme() {
        switch theme {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}

struct Toast: Equatable, Identifiable {
    let id = UUID()
    let message: String
    let undoable: Bool
}
