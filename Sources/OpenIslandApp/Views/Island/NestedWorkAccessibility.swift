import Foundation
import SwiftUI

/// Localized VoiceOver value for nested subagent and task work.
///
/// The row's existing four-field label stays stable; this value adds the
/// collapsed-only nested-work summary without making expanded detail repeat
/// information that VoiceOver can reach directly.
enum NestedWorkAccessibility {
    static func value(
        activeSubagentCount: Int,
        completedTaskCount: Int,
        totalTaskCount: Int,
        isExpanded: Bool,
        lang: LanguageManager
    ) -> String? {
        guard !isExpanded else { return nil }

        let subagentCount = max(0, activeSubagentCount)
        let taskTotal = max(0, totalTaskCount)
        let taskCompleted = min(max(0, completedTaskCount), taskTotal)
        var components: [String] = []

        if subagentCount > 0 {
            let key = subagentCount == 1
                ? "a11y.nestedWork.subagents.one"
                : "a11y.nestedWork.subagents.other"
            components.append(lang.t(key, subagentCount))
        }

        if taskTotal > 0 {
            let key = taskTotal == 1
                ? "a11y.nestedWork.tasks.one"
                : "a11y.nestedWork.tasks.other"
            components.append(lang.t(key, taskCompleted, taskTotal))
        }

        switch components.count {
        case 0:
            return nil
        case 1:
            return components[0]
        default:
            return lang.t("a11y.nestedWork.combined", components[0], components[1])
        }
    }
}

/// Applies an accessibility value only when collapsed nested work has one.
struct NestedWorkAccessibilityValue: ViewModifier {
    let value: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(Text(verbatim: value))
        } else {
            content
        }
    }
}
