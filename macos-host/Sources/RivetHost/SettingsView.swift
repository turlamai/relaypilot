import SwiftUI

// MARK: - settings (设置)

struct SettingsView: View {
    @EnvironmentObject private var store: RelayPilotStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: Lang.t("nav.settings"),
                            subtitle: Lang.t("settings.subtitle"))
                settingsGroup(Lang.t("settings.appearance")) {
                    settingsRow(title: Lang.t("settings.theme"),
                                subtitle: Lang.t("settings.redact.desc")) {
                        Picker("", selection: Binding(
                            get: { store.theme },
                            set: { store.setTheme($0) })) {
                            Text(Lang.t("theme.system")).tag("system")
                            Text(Lang.t("theme.light")).tag("light")
                            Text(Lang.t("theme.dark")).tag("dark")
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                }
                settingsGroup(Lang.t("settings.privacy")) {
                    settingsRow(
                        title: Lang.t("settings.redact"),
                        subtitle: Lang.t("settings.redact.desc")) {
                        Toggle(isOn: Binding(get: { store.redact },
                                             set: { store.setRedact($0) })) {
                            Text(store.redact ? Lang.t("switch.on") : Lang.t("switch.off"))
                                .font(TypeScale.secondary)
                        }
                        .toggleStyle(.button)
                    }
                    settingsRow(title: Lang.t("settings.export"),
                                subtitle: Lang.t("settings.export.desc")) {
                        PrimaryButton(title: Lang.t("settings.export.button"), kind: .plain) {
                            Task { await store.exportDiagnostics() }
                        }
                    }
                }
                settingsGroup(Lang.t("settings.efficiency")) {
                    settingsRow(title: Lang.t("settings.quickfind"),
                                subtitle: Lang.t("settings.quickfind.desc")) {
                        PrimaryButton(title: "\(Lang.t("quickFind")) ⌘K",
                                      icon: "magnifyingglass", kind: .plain) {
                            store.quickFindOpen = true
                        }
                    }
                    settingsRow(title: Lang.t("settings.keyboard"),
                                subtitle: Lang.t("settings.keyboard.desc")) {}
                }
                settingsGroup(Lang.t("settings.protection")) {
                    settingsRow(title: Lang.t("settings.previewGuard"),
                                subtitle: Lang.t("settings.previewGuard.desc")) {
                        StatusBadge(text: Lang.t("settings.previewGuard.value"), kind: .ok)
                    }
                    settingsRow(title: Lang.t("settings.ai"),
                                subtitle: Lang.t("settings.ai.desc")) {
                        StatusBadge(text: Lang.t("settings.ai.value"), kind: .neutral)
                    }
                }
                Text(Lang.t("settings.note"))
                    .font(TypeScale.meta)
                    .foregroundStyle(Palette.faint)
                    .padding(.bottom, 16)
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.bg)
    }

    private func settingsGroup<Content: View>(_ title: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(TypeScale.section)
                .foregroundStyle(Palette.ink)
            VStack(spacing: 0) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func settingsRow<Trailing: View>(title: String,
                                             subtitle: String,
                                             @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TypeScale.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.mute)
                }
            }
            Spacer(minLength: 24)
            trailing()
        }
        .padding(.vertical, 20)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.line) }
    }
}

// MARK: - quick find (⌘K)

struct QuickFindItem: Identifiable {
    enum Kind { case page(AppPage), profile(String), target(String) }

    let id: String
    let title: String
    let subtitle: String
    let kind: Kind
}

struct QuickFindView: View {
    @EnvironmentObject private var store: RelayPilotStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool

    private var items: [QuickFindItem] {
        var all: [QuickFindItem] = []
        for page in AppPage.allCases {
            all.append(QuickFindItem(id: "page-\(page.id)",
                                     title: Lang.t(page.titleKey),
                                     subtitle: Lang.t("qf.kind.page"),
                                     kind: .page(page)))
        }
        for entry in store.snapshot?.profiles ?? [] {
            all.append(QuickFindItem(id: "profile-\(entry.id)",
                                     title: entry.name,
                                     subtitle: entry.description.isEmpty
                                     ? Lang.t("qf.kind.profile") : entry.description,
                                     kind: .profile(entry.id)))
        }
        for target in store.savedTargets {
            all.append(QuickFindItem(id: "target-\(target)",
                                     title: target,
                                     subtitle: Lang.t("qf.kind.target"),
                                     kind: .target(target)))
        }
        let query = store.quickFindQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty { return all }
        return all.filter {
            $0.title.lowercased().contains(query) || $0.subtitle.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: Lang.t("qf.search"))
                TextField(Lang.t("qf.placeholder"), text: $store.quickFindQuery)
                    .font(TypeScale.secondary)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: Palette.radiusControl)
                        .strokeBorder(Palette.line))
                    .focused($searchFocused)
                    .onAppear { searchFocused = true }
            }
            ScrollView {
                VStack(spacing: 2) {
                    if items.isEmpty {
                        Text(Lang.t("qf.empty"))
                            .font(TypeScale.secondary)
                            .foregroundStyle(Palette.mute)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(items) { item in
                            QuickFindRow(item: item) {
                                open(item)
                                dismiss()
                                store.quickFindOpen = false
                            }
                        }
                    }
                }
            }
            .frame(height: 260)
            Text(Lang.t("qf.hint"))
                .font(TypeScale.meta)
                .foregroundStyle(Palette.faint)
        }
        .padding(24)
        .frame(width: 560)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Palette.radiusDialog))
        .padding(.vertical, 40)
        .onExitCommand { dismiss() }
    }

    private func open(_ item: QuickFindItem) {
        switch item.kind {
        case .page(let page):
            store.page = page
        case .profile(let id):
            store.openProfile(id)
        case .target(let target):
            Task {
                store.page = .trace
                await store.inspect(target: target)
            }
        }
    }
}

struct QuickFindRow: View {
    let item: QuickFindItem
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(TypeScale.secondary.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Text(item.subtitle)
                        .font(TypeScale.meta)
                        .foregroundStyle(Palette.mute)
                }
                Spacer(minLength: 12)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.mute)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Palette.radiusControl))
    }
}
