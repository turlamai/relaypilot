import SwiftUI

// MARK: - overview (运行概览)

struct OverviewView: View {
    @EnvironmentObject private var store: RelayPilotStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: Lang.t("nav.overview"),
                            subtitle: Lang.t("overview.subtitle"))
                sessionCard
                pendingSection
                HStack(alignment: .top, spacing: 24) {
                    savedTargets
                    activity
                }
            }
            .padding(24)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.bg)
        .task { await store.refreshLibrary() }
    }

    private var sessionTitle: String {
        switch store.phase {
        case .running: return Lang.t("session.running")
        case .starting: return Lang.t("session.starting")
        case .idle: return Lang.t("session.idle")
        }
    }

    private var sessionSub: String {
        switch store.phase {
        case .running: return Lang.t("session.running.sub")
        case .starting: return Lang.t("session.starting.sub")
        case .idle: return Lang.t("session.idle.sub")
        }
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(store.phase == .running ? Palette.okSoft : Palette.bg)
                        .overlay(Circle().strokeBorder(
                            store.phase == .running ? Palette.ok : Palette.line))
                    Image(systemName: store.phase == .running ? "checkmark" : "power")
                        .font(.system(size: 20))
                        .foregroundStyle(store.phase == .running ? Palette.ok : Palette.mute)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 8) {
                    Text(sessionTitle)
                        .font(TypeScale.display)
                        .foregroundStyle(Palette.ink)
                    Text(sessionSub)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.mute)
                }
                Spacer(minLength: 16)
                sessionButton
            }

            if store.phase == .starting {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Palette.accent)
            }

            HStack(alignment: .top, spacing: 24) {
                factCell(title: Lang.t("fact.activeProfile")) {
                    if let active = store.activeEntry {
                        Text(active.name)
                            .font(TypeScale.secondary.weight(.medium))
                            .foregroundStyle(Palette.ink)
                    } else {
                        Text("—").font(TypeScale.secondary).foregroundStyle(Palette.mute)
                    }
                    ActionLink(title: Lang.t("fact.manageProfiles")) {
                        store.page = .profiles
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                factCell(title: Lang.t("fact.defaultRoute")) {
                    Text(store.defaultRouteName)
                        .font(TypeScale.secondary.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Text(store.defaultRouteName == Lang.t("policy.direct")
                         || store.defaultRouteName == Lang.t("policy.reject")
                         || store.defaultRouteName == Lang.t("policy.unset")
                         ? "" : store.defaultRouteName)
                        .font(TypeScale.meta.monospaced())
                        .foregroundStyle(Palette.mute)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                factCell(title: Lang.t("fact.profileStatus")) {
                    if let active = store.activeEntry {
                        Text(String(format: Lang.t("fact.rulesCount"), active.ruleCount))
                            .font(TypeScale.secondary.weight(.medium))
                            .foregroundStyle(Palette.ink)
                        StatusBadge(
                            text: active.status == "valid"
                                ? Lang.t("fact.status.valid")
                                : Lang.t("fact.status.invalid"),
                            kind: active.status == "valid" ? .ok : .error)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .background(Palette.surface)
        .overlay(RoundedRectangle(cornerRadius: Palette.radiusCard)
            .strokeBorder(Palette.line))
        .clipShape(RoundedRectangle(cornerRadius: Palette.radiusCard))
    }

    @ViewBuilder
    private var sessionButton: some View {
        switch store.phase {
        case .idle:
            PrimaryButton(title: Lang.t("session.start"), icon: "power",
                          kind: .primary, large: true) {
                store.sessionConfirm = .idle
            }
        case .starting:
            PrimaryButton(title: Lang.t("session.starting.button"), icon: "power",
                          kind: .primary, large: true, disabled: true) {}
        case .running:
            PrimaryButton(title: Lang.t("session.stop"), icon: "power",
                          kind: .danger, large: true) {
                store.sessionConfirm = .running
            }
        }
    }

    @ViewBuilder
    private func factCell<Content: View>(title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(TypeScale.meta)
                .foregroundStyle(Palette.mute)
            content()
        }
    }

    private var pendingSection: some View {
        let pending = store.pendingItems
        return VStack(alignment: .leading, spacing: 16) {
            SectionHead(title: Lang.t("pending.title")) {
                AnyView(StatusBadge(
                    text: pending.isEmpty
                        ? Lang.t("pending.clear")
                        : String(format: Lang.t("pending.count"), pending.count),
                    kind: pending.isEmpty ? .ok : .warn))
            }
            if pending.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.ok)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Lang.t("pending.clear.title"))
                            .font(TypeScale.secondary.weight(.medium))
                            .foregroundStyle(Palette.ink)
                        Text(Lang.t("pending.clear.body"))
                            .font(TypeScale.secondary)
                            .foregroundStyle(Palette.mute)
                    }
                }
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(pending) { item in
                        PendingRow(item: item)
                        Divider().overlay(Palette.line)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var savedTargets: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHead(title: Lang.t("targets.title")) {
                AnyView(ActionLink(title: Lang.t("targets.inspectOthers")) {
                    store.page = .trace
                })
            }
            if store.savedTargets.isEmpty {
                Text(Lang.t("targets.empty"))
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.mute)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.savedTargets, id: \.self) { target in
                        SavedTargetRow(target: target)
                        Divider().overlay(Palette.line)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHead(title: Lang.t("events.title")) {
                AnyView(Text(Lang.t("events.recentFirst"))
                    .font(TypeScale.meta)
                    .foregroundStyle(Palette.faint))
            }
            if store.events.isEmpty {
                Text("—")
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.faint)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.events) { event in
                        HStack(alignment: .top, spacing: 16) {
                            Text(event.time.formatted(date: .omitted, time: .shortened))
                                .font(TypeScale.meta.monospaced())
                                .foregroundStyle(Palette.mute)
                            Text(event.text)
                                .font(TypeScale.secondary)
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 10)
                        Divider().overlay(Palette.line)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PendingRow: View {
    @EnvironmentObject private var store: RelayPilotStore
    let item: PendingItem

    var body: some View {
        Button {
            if let profileId = item.profileId {
                store.openProfile(profileId)
            } else if let target = item.target {
                Task {
                    store.page = .trace
                    await store.inspect(target: target)
                }
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Palette.radiusControl)
                        .fill(Palette.warnSoft)
                    Image(systemName: item.profileId != nil
                          ? "info.circle" : "arrow.triangle.branch")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.warn)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(rowTitle)
                        .font(TypeScale.secondary.weight(.medium))
                        .foregroundStyle(Palette.ink)
                    Text(rowHint)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.mute)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Text(item.profileId != nil
                         ? Lang.t("pending.goProfile") : Lang.t("pending.viewDiff"))
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.accent)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.accent)
                }
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowTitle: String {
        if let profileId = item.profileId {
            return store.entry(id: profileId)?.name ?? profileId
        }
        return item.target ?? ""
    }

    private var rowHint: String {
        if let profileId = item.profileId {
            if let entry = store.entry(id: profileId),
               let first = entry.issues.first {
                return first.detail
            }
            return Lang.t("pending.invalidHint")
        }
        guard let target = item.target,
              let expected = store.expectations[target],
              let decision = store.routeCache[target] else {
            return Lang.t("pending.invalidHint")
        }
        return String(format: Lang.t("pending.mismatchHint"),
                      Lang.policyName(expected),
                      Lang.policyName(decision.policy))
    }
}

struct SavedTargetRow: View {
    @EnvironmentObject private var store: RelayPilotStore
    let target: String

    var body: some View {
        Button {
            Task {
                store.page = .trace
                await store.inspect(target: target)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(target)
                        .font(TypeScale.secondary.monospaced())
                        .foregroundStyle(Palette.ink)
                    Text(hint)
                        .font(TypeScale.secondary)
                        .foregroundStyle(Palette.mute)
                }
                Spacer(minLength: 12)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.mute)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hint: String {
        let exit = store.routeCache[target]?.outbound ?? "—"
        guard let expected = store.expectations[target] else {
            return "\(exit) · \(Lang.t("target.noExpectation"))"
        }
        let decision = store.routeCache[target]
        let mismatch = decision.map { $0.policy != expected } ?? true
        return "\(exit) · \(mismatch ? Lang.t("target.mismatch") : Lang.t("target.match"))"
    }
}

// MARK: - session confirm dialog

struct SessionConfirmDialog: View {
    @EnvironmentObject private var store: RelayPilotStore
    let phase: SessionPhase

    private var start: Bool { phase == .idle }

    var body: some View {
        DialogScaffold(
            title: start ? Lang.t("session.startConfirm.title") : Lang.t("session.stopConfirm.title"),
            subtitle: start ? Lang.t("session.startConfirm.body") : Lang.t("session.stopConfirm.body"),
            onClose: { store.sessionConfirm = nil }) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Lang.t("session.confirmProfileLabel"))
                        .font(TypeScale.meta)
                        .foregroundStyle(Palette.mute)
                    Text(store.activeEntry?.name ?? "—")
                        .font(TypeScale.secondary.monospaced())
                        .foregroundStyle(Palette.ink)
                }
                DialogActions {
                    PrimaryButton(title: Lang.t("cancel"), kind: .plain,
                                  role: .cancel) {
                        store.sessionConfirm = nil
                    }
                    PrimaryButton(title: start
                                  ? Lang.t("session.confirmStart")
                                  : Lang.t("session.confirmStop"),
                                  kind: start ? .primary : .danger) {
                        let start = start
                        store.sessionConfirm = nil
                        Task {
                            if start {
                                await store.startSession()
                            } else {
                                await store.stopSession()
                            }
                        }
                    }
                }
            }
        }
    }
}
