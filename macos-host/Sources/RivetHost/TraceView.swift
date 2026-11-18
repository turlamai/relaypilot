import SwiftUI

// MARK: - trace (路由检查)

struct TraceView: View {
    @EnvironmentObject private var store: RelayPilotStore
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: Lang.t("nav.trace"),
                            subtitle: Lang.t("trace.subtitle"))
                searchForm
                examples
                if let error = store.traceError {
                    Text(error)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.danger)
                }
                if store.traceBusy {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(Lang.t("trace.inspecting"))
                            .font(TypeScale.secondary)
                            .foregroundStyle(Palette.mute)
                    }
                    .padding(16)
                    .background(Palette.raised)
                    .clipShape(RoundedRectangle(cornerRadius: Palette.radiusControl))
                } else if store.traceDecision != nil {
                    result
                }
            }
            .padding(24)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.bg)
        .onReceive(NotificationCenter.default.publisher(
            for: .relaypilotFocusTraceField)) { _ in
            fieldFocused = true
        }
    }

    private var searchForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: Lang.t("trace.field"))
                    TextField("", text: $store.traceInput)
                        .font(TypeScale.secondary.monospaced())
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Palette.surface)
                        .overlay(RoundedRectangle(cornerRadius: Palette.radiusControl)
                            .strokeBorder(Palette.line))
                        .focused($fieldFocused)
                        .onSubmit {
                            Task { await store.inspect() }
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PrimaryButton(title: store.traceBusy
                              ? Lang.t("trace.inspecting")
                              : Lang.t("trace.inspect"),
                              icon: "magnifyingglass",
                              kind: .primary,
                              disabled: store.traceBusy) {
                    Task { await store.inspect() }
                }
            }
        }
    }

    @ViewBuilder
    private var examples: some View {
        if !store.savedTargets.isEmpty {
            HStack(spacing: 12) {
                Text(Lang.t("targets.title"))
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.mute)
                ForEach(store.savedTargets, id: \.self) { target in
                    Button(target) {
                        Task { await store.inspect(target: target) }
                    }
                    .buttonStyle(.plain)
                    .font(TypeScale.secondary.monospaced())
                    .foregroundStyle(Palette.accent)
                    .underline()
                }
            }
        }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 24) {
            resultHeading
            comparison
            explanation
            steps
            technical
        }
    }

    private var expectationBadge: StatusBadge.Kind {
        guard let target = store.traceTarget,
              let expected = store.expectations[target] else { return .neutral }
        let mismatch = store.traceDecision?.policy != expected
        return mismatch ? .warn : .ok
    }

    private var expectationBadgeText: String {
        guard let target = store.traceTarget,
              let expected = store.expectations[target] else {
            return Lang.t("trace.noExpectationBadge")
        }
        let mismatch = store.traceDecision?.policy != expected
        return mismatch ? Lang.t("trace.mismatch") : Lang.t("trace.match")
    }

    private var resultHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(store.traceTarget ?? "")
                .font(TypeScale.section.monospaced())
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 16)
            StatusBadge(text: expectationBadgeText, kind: expectationBadge)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var policyPicker: some View {
        Picker(Lang.t("trace.expectation.label"), selection: Binding(
            get: { store.expectations[store.traceTarget ?? ""] ?? "" },
            set: { store.setExpectation(store.traceTarget ?? "", $0.isEmpty ? nil : $0) })) {
            Text(Lang.t("trace.expectation.none")).tag("")
            ForEach(store.activeEntry?.targets ?? [], id: \.self) { target in
                Text(Lang.policyName(target)).tag(target)
            }
        }
        .labelsHidden()
        .frame(width: 240)
    }

    private var comparison: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Lang.t("trace.expectation.label"))
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.mute)
                policyPicker
                Text(Lang.t("trace.expectation.note"))
                    .font(TypeScale.meta)
                    .foregroundStyle(Palette.faint)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) { Divider().overlay(Palette.line) }

            VStack(alignment: .leading, spacing: 8) {
                Text(Lang.t("trace.actual"))
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.mute)
                Text(Lang.policyName(store.traceDecision?.policy ?? ""))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text(store.traceDecision?.outbound ?? "")
                    .font(TypeScale.secondary.monospaced())
                    .foregroundStyle(Palette.mute)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.surface)
        .overlay(RoundedRectangle(cornerRadius: Palette.radiusCard)
            .strokeBorder(Palette.line))
        .clipShape(RoundedRectangle(cornerRadius: Palette.radiusCard))
    }

    private var mismatch: Bool {
        guard let target = store.traceTarget,
              let expected = store.expectations[target] else { return false }
        return store.traceDecision?.policy != expected
    }

    private var explanation: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(mismatch
                     ? Lang.t("trace.rule.diffSource")
                     : (store.traceDecision?.ruleIndex != nil
                        ? Lang.t("trace.rule.decides")
                        : Lang.t("trace.rule.supplement")))
                    .font(TypeScale.secondary.weight(.semibold))
                    .foregroundStyle(mismatch ? Palette.warn : Palette.ink)
                Text(causeText)
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.mute)
                Text(ruleSource)
                    .font(TypeScale.secondary.monospaced())
                    .foregroundStyle(Palette.accent)
            }
            Spacer(minLength: 16)
            if let entry = store.activeEntry {
                PrimaryButton(title: mismatch
                              ? Lang.t("patch.title")
                              : Lang.t("profiles.edit"),
                              icon: "pencil",
                              kind: mismatch ? .primary : .plain) {
                    if mismatch {
                        store.patchFlow = PatchFlow(target: store.traceTarget ?? "")
                    } else {
                        Task { await store.openEditor(entry) }
                    }
                }
            }
        }
        .padding(.vertical, 24)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.line) }
    }

    private var causeText: String {
        guard let decision = store.traceDecision else { return Lang.t("trace.cause.none") }
        if decision.ruleIndex == 0 {
            return Lang.t("trace.cause.final")
        }
        let index = Int(decision.ruleIndex)
        // The generated ruleIndex is 1-based; rule 0 is the FINAL fallback.
        if decision.outbound == "relaypilot.block" {
            return Lang.t("trace.cause.final")
        }
        switch decision.policy {
        case "DIRECT", "REJECT":
            return String(format: Lang.t("trace.cause.suffix"), index)
        default:
            return String(format: Lang.t("trace.cause.exact"), index)
        }
    }

    private var ruleSource: String {
        guard let decision = store.traceDecision else { return Lang.t("trace.cause.none") }
        if decision.ruleIndex == 0 {
            return decision.policy
        }
        return "rule[\(decision.ruleIndex)] → \(decision.policy) · \(decision.outbound)"
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHead(title: Lang.t("trace.steps.title")) {
                AnyView(Text(Lang.t("trace.steps.note"))
                    .font(TypeScale.meta)
                    .foregroundStyle(Palette.faint))
            }
            VStack(spacing: 0) {
                stepRow(number: "01",
                        title: Lang.t("trace.step.load"),
                        body: String(format: Lang.t("trace.step.load.body"),
                                     store.activeEntry?.name ?? "—",
                                     store.activeEntry?.ruleCount ?? 0))
                if let decision = store.traceDecision {
                    stepRow(number: "02",
                            title: decision.ruleIndex == 0
                                ? Lang.t("trace.step.matched.final")
                                : Lang.t("trace.step.matched.target"),
                            body: bodyForMatch,
                            source: ruleSource,
                            sourceLabel: Lang.t("trace.source.view"))
                    stepRow(number: "03",
                            title: exitTitle,
                            body: exitBody)
                } else {
                    stepRow(number: "02",
                            title: Lang.t("trace.step.nomatch"),
                            body: Lang.t("trace.step.nomatch.body"))
                }
            }
        }
    }

    private var bodyForMatch: String {
        guard let decision = store.traceDecision else { return "" }
        return decision.ruleIndex == 0
            ? Lang.t("trace.cause.final")
            : String(format: Lang.t("trace.cause.exact"), Int(decision.ruleIndex))
    }

    private var exitTitle: String {
        switch store.traceDecision?.policy {
        case "DIRECT": return Lang.t("policy.direct")
        case "REJECT": return Lang.t("policy.reject")
        default: return Lang.t("trace.step.matched.target")
        }
    }

    private var exitBody: String {
        guard let decision = store.traceDecision else { return "" }
        switch decision.policy {
        case "DIRECT": return Lang.t("trace.step.out.direct")
        case "REJECT": return Lang.t("trace.step.out.reject")
        default:
            return String(format: Lang.t("trace.step.out.group"),
                          decision.policy, decision.outbound)
        }
    }

    @ViewBuilder
    private func stepRow(number: String, title: String, body: String,
                         source: String? = nil, sourceLabel: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number)
                .font(TypeScale.meta.monospaced())
                .foregroundStyle(Palette.mute)
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Palette.line))
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(TypeScale.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(body)
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.mute)
                if let source, let sourceLabel {
                    SourceDisclosure(label: sourceLabel, content: source)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) { Divider().overlay(Palette.line) }
    }

    private var technical: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    technicalRow(label: Lang.t("trace.technical.traceId"),
                                 value: store.traceDecision?.traceId ?? "—")
                    technicalRow(label: Lang.t("trace.technical.profile"),
                                 value: store.activeEntry?.id ?? "—")
                    technicalRow(label: Lang.t("trace.technical.execution"),
                                 value: Lang.t("trace.technical.execution.value"))
                    if let artifact = store.traceArtifact {
                        technicalRow(label: Lang.t("trace.technical.artifact"),
                                     value: "\(artifact.adapter) \(artifact.adapterVersion) · \(artifact.sha256)")
                    } else {
                        technicalRow(label: Lang.t("trace.technical.artifact"),
                                     value: Lang.t("trace.technical.noArtifact"))
                    }
                    ForEach(store.traceDecision?.warnings ?? [], id: \.self) { warning in
                        technicalRow(label: "warning", value: warning)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(Lang.t("trace.technical.title"))
                    .font(TypeScale.secondary.weight(.medium))
                    .foregroundStyle(Palette.mute)
            }
            .padding(.top, 16)
            .overlay(alignment: .top) { Divider().overlay(Palette.line) }

            HStack {
                PrimaryButton(title: Lang.t("trace.copy"), icon: "doc.on.doc", kind: .plain) {
                    copyRecord()
                }
                Spacer(minLength: 12)
                targetButton
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var targetButton: some View {
        if let target = store.traceTarget {
            if store.savedTargets.contains(target) {
                PrimaryButton(title: Lang.t("trace.removeTarget"), icon: "trash", kind: .danger) {
                    store.removeTarget(target)
                }
            } else {
                PrimaryButton(title: Lang.t("trace.saveTarget"), icon: "plus", kind: .plain) {
                    store.saveTarget()
                }
            }
        }
    }

    private func technicalRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(TypeScale.secondary)
                .foregroundStyle(Palette.mute)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(TypeScale.secondary.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func copyRecord() {
        guard let decision = store.traceDecision else { return }
        var lines = [
            "trace_id: \(decision.traceId)",
            "\(Lang.t("trace.technical.profile")): \(store.activeEntry?.id ?? "—")",
            "policy: \(decision.policy)",
            "outbound: \(decision.outbound)"
        ]
        lines.append(contentsOf: decision.steps.map { "step: \($0)" })
        if let artifact = store.traceArtifact {
            lines.append("artifact: \(artifact.adapter) \(artifact.adapterVersion) sha256=\(artifact.sha256)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        store.showToast(Lang.t("trace.copied"))
    }
}

struct SourceDisclosure: View {
    let label: String
    let content: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                open.toggle()
            } label: {
                Text(label)
                    .font(TypeScale.secondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.mute)
            if open {
                Text(content)
                    .font(TypeScale.secondary.monospaced())
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.raised)
                    .clipShape(RoundedRectangle(cornerRadius: Palette.radiusControl))
            }
        }
    }
}

// MARK: - patch dialogs (修改路由)

struct PatchDialog: View {
    @EnvironmentObject private var store: RelayPilotStore
    @State private var flow: PatchFlow
    @State private var busy = false

    init(flow: PatchFlow) {
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
        DialogScaffold(title: Lang.t("patch.title"),
                       subtitle: Lang.t("patch.body"),
                       onClose: { store.patchFlow = nil }) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: Lang.t("patch.target"))
                    Text(flow.target)
                        .font(TypeScale.secondary.monospaced())
                        .textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: Lang.t("patch.policy"))
                    Picker("", selection: $flow.policy) {
                        ForEach(store.activeEntry?.targets ?? [], id: \.self) { target in
                            Text(Lang.policyName(target)).tag(target)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 320)
                }
                Text(Lang.t("patch.note"))
                    .font(TypeScale.meta)
                    .foregroundStyle(Palette.faint)
                if let error = flow.error {
                    Text(error)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.danger)
                }
                DialogActions {
                    PrimaryButton(title: Lang.t("cancel"), kind: .plain,
                                  role: .cancel) {
                        store.patchFlow = nil
                    }
                    PrimaryButton(title: Lang.t("patch.preview"),
                                  kind: .primary, disabled: busy, cmdReturn: true) {
                        Task {
                            store.patchFlow = flow
                            busy = true
                            await store.patchPreview(policy: flow.policy)
                            busy = false
                            if let updated = store.patchFlow { flow = updated }
                        }
                    }
                }
            }
        }
    }

    private var confirmStage: some View {
        DialogScaffold(title: Lang.t("patch.confirm.title"),
                       subtitle: Lang.t("patch.confirm.body"),
                       onClose: { store.patchFlow = nil }) {
            VStack(alignment: .leading, spacing: 16) {
                if let preview = flow.preview {
                    DiffColumns {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Lang.t("patch.confirm.before"))
                                .font(TypeScale.secondary.weight(.semibold))
                                .foregroundStyle(Palette.mute)
                            Text(Lang.policyName(preview.currentPolicy))
                                .font(TypeScale.secondary.weight(.medium))
                                .foregroundStyle(Palette.ink)
                            Text(preview.currentOutbound)
                                .font(TypeScale.secondary.monospaced())
                                .foregroundStyle(Palette.mute)
                        }
                    } right: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Lang.t("patch.confirm.after"))
                                .font(TypeScale.secondary.weight(.semibold))
                                .foregroundStyle(Palette.mute)
                            Text(Lang.policyName(preview.nextPolicy))
                                .font(TypeScale.secondary.weight(.medium))
                                .foregroundStyle(Palette.ink)
                            Text(preview.nextOutbound)
                                .font(TypeScale.secondary.monospaced())
                                .foregroundStyle(Palette.mute)
                        }
                    }
                    Text("+ \(preview.ruleText)")
                        .font(TypeScale.secondary.monospaced())
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.raised)
                        .clipShape(RoundedRectangle(cornerRadius: Palette.radiusControl))
                }
                DialogActions {
                    PrimaryButton(title: Lang.t("patch.back"), kind: .plain,
                                  role: .cancel) {
                        flow.stage = .edit
                    }
                    PrimaryButton(title: Lang.t("patch.confirm.apply"), kind: .primary, cmdReturn: true) {
                        Task {
                            store.patchFlow = flow
                            await store.patchApply()
                        }
                    }
                }
            }
        }
    }
}
