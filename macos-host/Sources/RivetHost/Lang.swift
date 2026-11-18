import AppKit

/// Host strings come from the project's shared/i18n single source, embedded
/// as GeneratedI18n. There is no language setting on purpose (DESIGN.md:
/// no dropdowns without behavior): the UI follows the system language, zh
/// when the system prefers Chinese, en otherwise.
enum Lang {
    static let current = (Locale.preferredLanguages.first?.hasPrefix("zh") ?? false) ? "zh" : "en"

    static func t(_ key: String) -> String {
        GeneratedI18n.tr(current, key)
    }

    /// Format helpers: the tables carry printf-style placeholders.
    static func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale(identifier: "en_US_POSIX"), arguments: args)
    }

    /// The localized label for a policy target: DIRECT/REJECT get proper
    /// names, profile groups and nodes keep their identifiers (DESIGN.md:
    /// API identifiers stay literal).
    static func policyName(_ policy: String) -> String {
        switch policy {
        case "DIRECT": return t("policy.direct")
        case "REJECT": return t("policy.reject")
        default: return policy
        }
    }
}
