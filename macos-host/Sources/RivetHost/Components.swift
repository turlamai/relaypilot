import SwiftUI

// MARK: - app shell

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: RelayPilotStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(224)
        } detail: {
            VStack(spacing: 0) {
                BannerView()
                PageView(page: store.page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                FooterView()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if store.canUndo {
                        Button {
                            Task { await store.undo() }
                        } label: {
                            Label(Lang.t("topUndo"), systemImage: "arrow.uturn.backward")
                        }
                    }
                    Button {
                        store.quickFindOpen = true
                    } label: {
                        Label(Lang.t("quickFind"), systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("k", modifiers: .command)
                }
            }
        }
        .background(Palette.bg)
        .sheet(isPresented: Binding(get: { store.quickFindOpen },
                                    set: { store.quickFindOpen = $0 })) {
            QuickFindView()
        }
        .sheet(item: Binding(get: { store.sessionConfirm },
                             set: { store.sessionConfirm = $0 })) { phase in
            SessionConfirmDialog(phase: phase)
        }
        .sheet(item: Binding(get: { store.patchFlow },
                             set: { store.patchFlow = $0 })) { flow in
            PatchDialog(flow: flow)
        }
        .sheet(item: Binding(get: { store.editorFlow },
                             set: { store.editorFlow = $0 })) { flow in
            EditorDialog(flow: flow)
        }
        .sheet(item: Binding(get: { store.importFlow },
                             set: { store.importFlow = $0 })) { flow in
            ImportDialog(flow: flow)
        }
        .sheet(item: Binding(get: { store.switchFlow },
                             set: { store.switchFlow = $0 })) { entry in
            SwitchConfirmDialog(entry: entry)
        }
        .sheet(item: Binding(get: { store.deleteFlow },
                             set: { store.deleteFlow = $0 })) { entry in
            DeleteConfirmDialog(entry: entry)
        }
        .overlay(alignment: .bottom) {
            ToastView()
                .environmentObject(store)
        }
    }
}

extension SessionPhase: Identifiable {
    var id: String { "\(self)" }
}

extension PatchFlow: Identifiable {
    var id: String { target }
}

extension EditorFlow: Identifiable {
    var id: String { profileId }
}

extension ImportFlow: Identifiable {
    var id: String { "import" }
}

extension RivetTypes.LibraryEntry: Identifiable {}

private struct PageView: View {
    let page: AppPage

    var body: some View {
        switch page {
        case .overview: OverviewView()
        case .trace: TraceView()
        case .profiles: ProfilesView()
        case .settings: SettingsView()
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var store: RelayPilotStore

    private func symbol(_ page: AppPage) -> String {
        switch page {
        case .overview: return "square.grid.2x2"
        case .trace: return "arrow.triangle.branch"
        case .profiles: return "doc.text"
        case .settings: return "slider.horizontal.3"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Palette.radiusControl)
                        .fill(Palette.ink)
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(Palette.bg)
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(width: 32, height: 32)
                Text("RelayPilot")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)

            VStack(spacing: 8) {
                ForEach(AppPage.allCases) { page in
                    navButton(page)
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.mute)
                Text(Lang.t("sidebarNote"))
                    .font(TypeScale.meta)
                    .foregroundStyle(Palette.mute)
            }
            .padding(.horizontal, 12)
            .padding(.top, 32)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.raised)
    }

    @ViewBuilder
    private func navButton(_ page: AppPage) -> some View {
        let active = store.page == page
        Button {
            store.page = page
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol(page))
                    .font(.system(size: 14))
                    .foregroundStyle(active ? Palette.accent : Palette.mute)
                Text(Lang.t(page.titleKey))
                    .font(TypeScale.secondary.weight(active ? .semibold : .regular))
                    .foregroundStyle(active ? Palette.ink : Palette.mute)
                Spacer(minLength: 0)
                if page == .profiles {
                    let pending = store.pendingItems.filter { $0.profileId != nil }.count
                    Text(pending > 0 ? "\(pending)" : "\(store.snapshot?.profiles.count ?? 0)")
                        .font(TypeScale.meta.monospaced())
                        .foregroundStyle(pending > 0 ? Palette.warn : Palette.faint)
                }
            }
            .padding(12)
            .background(active ? Palette.surface : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Palette.radiusControl)
                    .strokeBorder(active ? Palette.line : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct BannerView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
            Text(Lang.t("banner"))
                .font(TypeScale.meta)
        }
        .foregroundStyle(Palette.mute)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .background(Palette.raised)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.line) }
    }
}

private struct FooterView: View {
    @EnvironmentObject private var store: RelayPilotStore

    private var sessionName: String {
        switch store.phase {
        case .running: return Lang.t("session.running")
        case .starting: return Lang.t("session.starting")
        case .idle: return Lang.t("session.idle")
        }
    }

    var body: some View {
        HStack {
            Text("\(sessionName) · \(store.activeEntry?.name ?? "—")")
            Spacer(minLength: 16)
            if let active = store.activeEntry {
                Text(String(format: Lang.t("fact.rulesCount"), active.ruleCount))
            }
        }
        .font(TypeScale.meta)
        .foregroundStyle(Palette.mute)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider().overlay(Palette.line) }
    }
}

// MARK: - shared atoms

struct PageHeading<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(title: String, subtitle: String,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(TypeScale.page)
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.mute)
            }
            Spacer(minLength: 16)
            trailing
        }
    }
}

struct SectionHead<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(TypeScale.section)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 12)
            trailing
        }
    }
}

struct StatusBadge: View {
    enum Kind { case ok, warn, error, neutral }

    let text: String
    let kind: Kind

    private var fg: Color {
        switch kind {
        case .ok: return Palette.ok
        case .warn: return Palette.warn
        case .error: return Palette.danger
        case .neutral: return Palette.mute
        }
    }

    private var bg: Color {
        switch kind {
        case .ok: return Palette.okSoft
        case .warn: return Palette.warnSoft
        case .error: return Palette.dangerSoft
        case .neutral: return Palette.raised
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(TypeScale.meta.weight(.semibold))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: Palette.radiusControl))
    }

    private var icon: String {
        switch kind {
        case .ok: return "checkmark"
        case .warn, .error: return "exclamationmark.triangle"
        case .neutral: return "info.circle"
        }
    }
}

enum RelayButtonKind {
    case primary, plain, danger
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var kind: RelayButtonKind = .primary
    var large = false
    var disabled = false
    /// Standard dialog semantics: Return confirms, Esc cancels.
    var role: ButtonRole? = nil
    /// Two-stage dialogs keep ⌘↩ working while focus sits in a TextEditor,
    /// which would otherwise swallow plain Return.
    var cmdReturn = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
        }
        .buttonStyle(RelayButtonStyle(kind: kind, large: large))
        .disabled(disabled)
        .keyboardShortcut(cmdReturn
                          ? KeyboardShortcut(.return, modifiers: .command)
                          : (role == .cancel ? .cancelAction : .defaultAction))
    }
}

struct RelayButtonStyle: ButtonStyle {
    let kind: RelayButtonKind
    let large: Bool

    init(kind: RelayButtonKind, large: Bool) {
        self.kind = kind
        self.large = large
    }

    private var textColor: Color {
        switch kind {
        case .primary: return Palette.onAccent
        case .danger: return Palette.danger
        case .plain: return Palette.ink
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Palette.accent
        case .plain, .danger: return Palette.surface
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.secondary.weight(.medium))
            .foregroundStyle(textColor)
            .padding(.horizontal, large ? 24 : 16)
            .frame(minHeight: large ? 48 : 40)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: Palette.radiusControl)
                    .strokeBorder(kind == .danger ? Palette.danger : Palette.line)
            )
            .clipShape(RoundedRectangle(cornerRadius: Palette.radiusControl))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct ActionLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TypeScale.secondary)
                .underline()
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.accent)
    }
}

struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(TypeScale.secondary.weight(.semibold))
            .foregroundStyle(Palette.ink)
    }
}

/// The prototype's `.field` input: persistent label above, line-bordered box.
struct RelayTextField: View {
    let label: String
    @Binding var text: String
    var mono = false
    var onSubmit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: label)
            TextField("", text: $text)
                .font(mono ? TypeScale.secondary.monospaced() : TypeScale.secondary)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Palette.radiusControl)
                        .strokeBorder(Palette.line)
                )
                .onSubmit { onSubmit?() }
        }
    }
}

/// Sheet wrapper reproducing the prototype dialog: 16px radius, header with
/// title/description/close, body, action row with hairline separators.
struct DialogScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(TypeScale.section)
                        .foregroundStyle(Palette.ink)
                    Text(subtitle)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.mute)
                }
                Spacer(minLength: 16)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.mute)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .overlay(alignment: .bottom) { Divider().overlay(Palette.line) }

            content
                .padding(24)
        }
        .frame(width: 640)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Palette.radiusDialog))
        .padding(.vertical, 24)
    }
}

struct DialogActions<Buttons: View>: View {
    @ViewBuilder let buttons: Buttons

    var body: some View {
        HStack {
            Spacer(minLength: 12)
            buttons
        }
        .padding(.top, 16)
        .overlay(alignment: .top) { Divider().overlay(Palette.line).padding(.bottom, 16) }
    }
}

struct DiffColumns<L: View, R: View>: View {
    @ViewBuilder let left: L
    @ViewBuilder let right: R

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            left
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .overlay(
                    RoundedRectangle(cornerRadius: Palette.radiusControl)
                        .strokeBorder(Palette.line)
                )
            right
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .overlay(
                    RoundedRectangle(cornerRadius: Palette.radiusControl)
                        .strokeBorder(Palette.line)
                )
        }
    }
}

struct ToastView: View {
    @EnvironmentObject private var store: RelayPilotStore

    var body: some View {
        if let toast = store.toast {
            HStack(spacing: 16) {
                Text(toast.message)
                    .font(TypeScale.secondary)
                if toast.undoable {
                    Button(Lang.t("undo")) {
                        Task { await store.undo() }
                        store.toast = nil
                    }
                    .buttonStyle(.plain)
                    .underline()
                }
                Button(Lang.t("close")) {
                    store.toast = nil
                }
                .buttonStyle(.plain)
                .underline()
            }
            .foregroundStyle(Palette.bg)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Palette.ink)
            .clipShape(RoundedRectangle(cornerRadius: Palette.radiusCard))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
