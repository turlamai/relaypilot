import SwiftUI

// MARK: - profiles (配置库)

struct ProfilesView: View {
    @EnvironmentObject private var store: RelayPilotStore
    @FocusState private var searchFocused: Bool

    private var filtered: [RivetTypes.LibraryEntry] {
        let query = store.profilesQuery.trimmingCharacters(in: .whitespaces).lowercased()
        return (store.snapshot?.profiles ?? []).filter { entry in
            let statusMatch = store.profilesFilter == "all" || entry.status == store.profilesFilter
            let textMatch = query.isEmpty
                || entry.name.lowercased().contains(query)
                || entry.description.lowercased().contains(query)
            return statusMatch && textMatch
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: Lang.t("nav.profiles"),
                            subtitle: Lang.t("profiles.subtitle"),
                            trailing: {
                                PrimaryButton(title: Lang.t("profiles.import"),
                                              icon: "plus", kind: .primary) {
                                    store.importFlow = ImportFlow()
                                }
                            })
                toolbar
                Text(String(format: Lang.t("profiles.results"),
                            filtered.count, store.snapshot?.profiles.count ?? 0))
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.mute)
                masterDetail
            }
            .padding(24)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.bg)
        .onReceive(NotificationCenter.default.publisher(
            for: .relaypilotFocusProfileSearch)) { _ in
            searchFocused = true
        }
    }

    private var toolbar: some View {
        HStack(alignment: .bottom, spacing: 16) {
            RelayTextField(label: Lang.t("profiles.search"),
                           text: $store.profilesQuery)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: Lang.t("profiles.filter"))
                Picker("", selection: $store.profilesFilter) {
                    Text(Lang.t("profiles.filter.all")).tag("all")
                    Text(Lang.t("profiles.filter.valid")).tag("valid")
                    Text(Lang.t("profiles.filter.invalid")).tag("invalid")
                }
                .labelsHidden()
                .frame(width: 200)
            }
        }
    }

    @ViewBuilder
    private var masterDetail: some View {
        if filtered.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(store.snapshot?.profiles.isEmpty == true
                     ? Lang.t("profiles.empty") : Lang.t("profiles.nomatch"))
                    .font(TypeScale.section)
                    .foregroundStyle(Palette.ink)
                Text(store.snapshot?.profiles.isEmpty == true
                     ? Lang.t("profiles.pick.body") : Lang.t("profiles.nomatch.body"))
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.mute)
                if store.snapshot?.profiles.isEmpty == false {
                    PrimaryButton(title: Lang.t("profiles.clearFilters"), kind: .plain) {
                        store.profilesQuery = ""
                        store.profilesFilter = "all"
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: Palette.radiusCard)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(Palette.line))
        } else {
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 0) {
                    ForEach(filtered) { entry in
                        ProfileListRow(entry: entry,
                                       selected: entry.id == store.selectedProfileId) {
                            store.selectProfile(entry.id)
                        }
                        Divider().overlay(Palette.line)
                    }
                }
                .frame(width: 300)
                if let selected = filtered.first(where: { $0.id == store.selectedProfileId }) {
                    ProfileDetail(entry: selected)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Lang.t("profiles.pick"))
                            .font(TypeScale.section)
                            .foregroundStyle(Palette.ink)
                        Text(Lang.t("profiles.pick.body"))
                            .font(TypeScale.secondary)
                            .foregroundStyle(Palette.mute)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .overlay(RoundedRectangle(cornerRadius: Palette.radiusCard)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(Palette.line))
                }
            }
        }
    }
}

struct ProfileListRow: View {
    @EnvironmentObject private var store: RelayPilotStore
    let entry: RivetTypes.LibraryEntry
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.mute)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.name)
                        .font(TypeScale.secondary.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    if !entry.description.isEmpty {
                        Text(entry.description)
                            .font(TypeScale.secondary)
                            .foregroundStyle(Palette.mute)
                    }
                    if entry.id == store.snapshot?.activeProfileId {
                        StatusBadge(text: Lang.t("profiles.badge.active"), kind: .ok)
                    } else {
                        StatusBadge(
                            text: entry.status == "valid"
                                ? Lang.t("profiles.filter.valid")
                                : Lang.t("profiles.filter.invalid"),
                            kind: entry.status == "valid" ? .neutral : .error)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(16)
            .contentShape(Rectangle())
            .background(selected ? Palette.surface : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Palette.radiusControl)
                    .strokeBorder(selected ? Palette.line : Palette.line.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }
}

struct ProfileDetail: View {
    @EnvironmentObject private var store: RelayPilotStore
    let entry: RivetTypes.LibraryEntry
    @State private var rules: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.name)
                    .font(TypeScale.section)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 16)
                if entry.id == store.snapshot?.activeProfileId {
                    StatusBadge(text: Lang.t("profiles.badge.active"), kind: .ok)
                } else {
                    StatusBadge(
                        text: entry.status == "valid"
                            ? Lang.t("profiles.filter.valid")
                            : Lang.t("profiles.filter.invalid"),
                        kind: entry.status == "valid" ? .ok : .error)
                }
            }
            if !entry.description.isEmpty {
                Text(entry.description)
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.mute)
            }
            if entry.status != "valid" {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(Lang.t("profiles.issues.title"))
                            .font(TypeScale.secondary.weight(.semibold))
                    }
                    .foregroundStyle(Palette.danger)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(entry.issues, id: \.detail) { issue in
                            Text("· \(issue.detail)")
                                .font(TypeScale.secondary)
                                .foregroundStyle(Palette.danger)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.dangerSoft)
                .clipShape(RoundedRectangle(cornerRadius: Palette.radiusControl))
            }

            SectionHead(title: Lang.t("profiles.rules.title")) {
                AnyView(Text(String(format: Lang.t("profiles.rulesCount"), entry.ruleCount))
                    .font(TypeScale.meta)
                    .foregroundStyle(Palette.faint))
            }
            if rules.isEmpty {
                Text(entry.status == "valid" ? Lang.t("editor.none") : Lang.t("trace.step.nomatch.body"))
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.mute)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                        RuleRow(index: index + 1, rule: rule)
                        Divider().overlay(Palette.line)
                    }
                }
            }

            HStack(spacing: 12) {
                if entry.id == store.snapshot?.activeProfileId {
                    PrimaryButton(title: Lang.t("profiles.checkRoutes"), kind: .plain) {
                        store.page = .trace
                    }
                } else if entry.status == "valid" {
                    PrimaryButton(title: Lang.t("profiles.use"), kind: .primary) {
                        store.switchFlow = entry
                    }
                }
                PrimaryButton(title: Lang.t("profiles.edit"), kind: .plain) {
                    Task { await store.openEditor(entry) }
                }
                if entry.id != store.snapshot?.activeProfileId {
                    PrimaryButton(title: Lang.t("profiles.delete"), kind: .danger) {
                        store.deleteFlow = entry
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.surface)
        .overlay(RoundedRectangle(cornerRadius: Palette.radiusCard)
            .strokeBorder(Palette.line))
        .clipShape(RoundedRectangle(cornerRadius: Palette.radiusCard))
        .task(id: entry.id) {
            rules = await store.rulesList(for: entry)
        }
        .onChange(of: entry.ruleCount) { _, _ in
            Task { rules = await store.rulesList(for: entry) }
        }
    }
}

struct RuleRow: View {
    let index: Int
    let rule: String

    private var kind: String {
        rule.split(separator: ",").first.map(String.init)?.uppercased() ?? ""
    }

    private var value: String {
        let parts = rule.split(separator: ",").map(String.init)
        if kind == "FINAL" || kind == "MATCH" {
            return Lang.t("profiles.rule.fallback")
        }
        return parts.count > 1 ? parts[1] : ""
    }

    private var policy: String {
        let parts = rule.split(separator: ",").map(String.init)
        return parts.last ?? ""
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(format: "%02d", index))
                .font(TypeScale.meta.monospaced())
                .foregroundStyle(Palette.mute)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(TypeScale.secondary.monospaced())
                    .foregroundStyle(Palette.ink)
                Text(kind)
                    .font(TypeScale.meta)
                    .foregroundStyle(Palette.mute)
            }
            Spacer(minLength: 12)
            Text(policy)
                .font(TypeScale.secondary)
                .foregroundStyle(Palette.ink)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - rule editor dialog

struct EditorDialog: View {
    @EnvironmentObject private var store: RelayPilotStore
    @State private var flow: EditorFlow
    @State private var busy = false

    init(flow: EditorFlow) {
        _flow = State(initialValue: flow)
    }

    var body: some View {
        if flow.stage == .edit {
            editStage
        } else {
            confirmStage
        }
    }

    private var editStage: some View {
        DialogScaffold(title: Lang.t("editor.title"),
                       subtitle: Lang.t("editor.body"),
                       onClose: { store.editorFlow = nil }) {
            VStack(alignment: .leading, spacing: 16) {
                Text(flow.profileName)
                    .font(TypeScale.secondary.monospaced())
                    .foregroundStyle(Palette.ink)
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: Lang.t("editor.rules"))
                    TextEditor(text: $flow.text)
                        .font(TypeScale.secondary.monospaced())
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(Palette.surface)
                        .overlay(RoundedRectangle(cornerRadius: Palette.radiusControl)
                            .strokeBorder(Palette.line))
                }
                Text(Lang.t("editor.grammar"))
                    .font(TypeScale.meta)
                    .foregroundStyle(Palette.faint)
                ActionLink(title: Lang.t("editor.appendFinal")) {
                    let trimmed = flow.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    flow.text = trimmed.isEmpty
                        ? "FINAL, DIRECT"
                        : trimmed + "\nFINAL, DIRECT"
                }
                if !flow.issues.isEmpty {
                    issueList(flow.issues)
                }
                DialogActions {
                    PrimaryButton(title: Lang.t("cancel"), kind: .plain,
                                  role: .cancel) {
                        store.editorFlow = nil
                    }
                    PrimaryButton(title: Lang.t("editor.validatePreview"),
                                  kind: .primary, disabled: busy, cmdReturn: true) {
                        Task {
                            store.editorFlow = flow
                            busy = true
                            await store.editorValidate()
                            busy = false
                            if let updated = store.editorFlow { flow = updated }
                        }
                    }
                }
            }
        }
    }

    private var confirmStage: some View {
        DialogScaffold(title: Lang.t("editor.confirm.title"),
                       subtitle: flow.isActive
                       ? Lang.t("editor.confirm.body.active")
                       : Lang.t("editor.confirm.body.other"),
                       onClose: { store.editorFlow = nil }) {
            VStack(alignment: .leading, spacing: 16) {
                Text(flow.profileName)
                    .font(TypeScale.secondary.monospaced())
                    .foregroundStyle(Palette.ink)
                DiffColumns {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Lang.t("editor.confirm.before"))
                            .font(TypeScale.secondary.weight(.semibold))
                            .foregroundStyle(Palette.mute)
                        rulesBlock(flow.originalText)
                    }
                } right: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Lang.t("editor.confirm.after"))
                            .font(TypeScale.secondary.weight(.semibold))
                            .foregroundStyle(Palette.mute)
                        rulesBlock(flow.text)
                    }
                }
                DialogActions {
                    PrimaryButton(title: Lang.t("patch.back"), kind: .plain,
                                  role: .cancel) {
                        flow.stage = .edit
                    }
                    PrimaryButton(title: Lang.t("editor.confirm.save"), kind: .primary, cmdReturn: true) {
                        store.editorFlow = flow
                        Task { await store.editorSave() }
                    }
                }
            }
        }
    }

    private func rulesBlock(_ text: String) -> some View {
        Text(text.isEmpty ? Lang.t("editor.none") : text)
            .font(TypeScale.secondary.monospaced())
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raised)
            .clipShape(RoundedRectangle(cornerRadius: Palette.radiusControl))
    }

    private func issueList(_ issues: [RivetTypes.ProfileIssue]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Lang.t("editor.fixFirst"))
                .font(TypeScale.secondary.weight(.semibold))
                .foregroundStyle(Palette.danger)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(issues, id: \.detail) { issue in
                    Text("· \(issue.detail)")
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.danger)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.dangerSoft)
        .clipShape(RoundedRectangle(cornerRadius: Palette.radiusControl))
    }
}

// MARK: - switch / delete confirms

struct SwitchConfirmDialog: View {
    @EnvironmentObject private var store: RelayPilotStore
    let entry: RivetTypes.LibraryEntry

    var body: some View {
        DialogScaffold(title: Lang.t("switch.title"),
                       subtitle: store.phase == .running
                       ? Lang.t("switch.body.running")
                       : Lang.t("switch.body.idle"),
                       onClose: { store.switchFlow = nil }) {
            VStack(alignment: .leading, spacing: 16) {
                DiffColumns {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Lang.t("switch.from"))
                            .font(TypeScale.secondary.weight(.semibold))
                            .foregroundStyle(Palette.mute)
                        Text(store.activeEntry?.name ?? "—")
                            .font(TypeScale.secondary)
                            .foregroundStyle(Palette.ink)
                    }
                } right: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Lang.t("switch.to"))
                            .font(TypeScale.secondary.weight(.semibold))
                            .foregroundStyle(Palette.mute)
                        Text(entry.name)
                            .font(TypeScale.secondary)
                            .foregroundStyle(Palette.ink)
                    }
                }
                DialogActions {
                    PrimaryButton(title: Lang.t("cancel"), kind: .plain,
                                  role: .cancel) {
                        store.switchFlow = nil
                    }
                    PrimaryButton(title: Lang.t("switch.confirm"), kind: .primary) {
                        Task { await store.useProfile(entry) }
                    }
                }
            }
        }
    }
}

struct DeleteConfirmDialog: View {
    @EnvironmentObject private var store: RelayPilotStore
    let entry: RivetTypes.LibraryEntry

    var body: some View {
        DialogScaffold(title: Lang.t("delete.title"),
                       subtitle: Lang.t("delete.body"),
                       onClose: { store.deleteFlow = nil }) {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.name)
                    .font(TypeScale.secondary.monospaced())
                    .foregroundStyle(Palette.ink)
                DialogActions {
                    PrimaryButton(title: Lang.t("cancel"), kind: .plain,
                                  role: .cancel) {
                        store.deleteFlow = nil
                    }
                    PrimaryButton(title: Lang.t("delete.confirm"), kind: .danger) {
                        Task { await store.deleteProfile(entry) }
                    }
                }
            }
        }
    }
}

// MARK: - import dialog

struct ImportDialog: View {
    @EnvironmentObject private var store: RelayPilotStore
    @State private var flow: ImportFlow
    @State private var busy = false

    init(flow: ImportFlow) {
        _flow = State(initialValue: flow)
    }

    var body: some View {
        if flow.stage == .input {
            inputStage
        } else {
            previewStage
        }
    }

    private var inputStage: some View {
        DialogScaffold(title: Lang.t("import.title"),
                       subtitle: Lang.t("import.body"),
                       onClose: { store.importFlow = nil }) {
            VStack(alignment: .leading, spacing: 16) {
                RelayTextField(label: Lang.t("import.name"), text: $flow.name)
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: Lang.t("import.source"))
                    TextEditor(text: $flow.text)
                        .font(TypeScale.secondary.monospaced())
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(Palette.surface)
                        .overlay(RoundedRectangle(cornerRadius: Palette.radiusControl)
                            .strokeBorder(Palette.line))
                }
                if let error = flow.error {
                    Text(error)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.danger)
                }
                DialogActions {
                    PrimaryButton(title: Lang.t("cancel"), kind: .plain,
                                  role: .cancel) {
                        store.importFlow = nil
                    }
                    PrimaryButton(title: Lang.t("import.preview"),
                                  kind: .primary, disabled: busy, cmdReturn: true) {
                        Task {
                            store.importFlow = flow
                            busy = true
                            await store.importPreview()
                            busy = false
                            if let updated = store.importFlow { flow = updated }
                        }
                    }
                }
            }
        }
    }

    private var previewStage: some View {
        DialogScaffold(title: Lang.t("import.preview.title"),
                       subtitle: Lang.t("import.preview.body"),
                       onClose: { store.importFlow = nil }) {
            VStack(alignment: .leading, spacing: 16) {
                if let preview = flow.preview {
                    DiffColumns {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Lang.t("import.preview.title"))
                                .font(TypeScale.secondary.weight(.semibold))
                                .foregroundStyle(Palette.mute)
                            Text(String(format: Lang.t("import.preview.rulesCount"),
                                        preview.importableRules.count))
                                .font(TypeScale.secondary)
                                .foregroundStyle(Palette.ink)
                            Text(preview.placeholderGroups.isEmpty
                                 ? Lang.t("import.preview.groupsNone")
                                 : String(format: Lang.t("import.preview.groupsCount"),
                                          preview.placeholderGroups.count))
                                .font(TypeScale.secondary)
                                .foregroundStyle(Palette.ink)
                        }
                    } right: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(preview.unsupported.isEmpty
                                 ? Lang.t("import.preview.allSupported")
                                 : Lang.t("import.preview.unsupportedTitle"))
                                .font(TypeScale.secondary.weight(.semibold))
                                .foregroundStyle(preview.unsupported.isEmpty
                                                 ? Palette.ok : Palette.warn)
                            Text(String(format: Lang.t("import.preview.unsupportedCount"),
                                        preview.unsupported.count))
                                .font(TypeScale.secondary)
                                .foregroundStyle(Palette.mute)
                        }
                    }
                    if !preview.unsupported.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Lang.t("import.preview.unsupportedTitle"))
                                .font(TypeScale.secondary.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(preview.unsupported, id: \.detail) { row in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(String(format: Lang.t("import.preview.line"),
                                                        row.line, row.text))
                                                .font(TypeScale.secondary.monospaced())
                                                .foregroundStyle(Palette.ink)
                                            Text(row.detail)
                                                .font(TypeScale.meta)
                                                .foregroundStyle(Palette.mute)
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 140)
                        }
                        Toggle(isOn: $flow.acknowledged) {
                            Text(Lang.t("import.ack"))
                                .font(TypeScale.secondary)
                                .foregroundStyle(Palette.ink)
                        }
                        .toggleStyle(.checkbox)
                    }
                    Text(Lang.t("import.mappingNote"))
                        .font(TypeScale.meta)
                        .foregroundStyle(Palette.faint)
                }
                DialogActions {
                    PrimaryButton(title: Lang.t("import.back"), kind: .plain,
                                  role: .cancel) {
                        flow.stage = .input
                    }
                    PrimaryButton(title: Lang.t("import.create"),
                                  kind: .primary,
                                  disabled: !flow.acknowledged
                                  && !(flow.preview?.unsupported.isEmpty ?? false),
                                  cmdReturn: true) {
                        store.importFlow = flow
                        Task { await store.importCommit() }
                    }
                }
            }
        }
    }
}
