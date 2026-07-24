import SwiftUI
import OpenIslandCore

/// Persistent hint at the top of the expanded island while no agent hooks are
/// installed. Decoupled from session presence — process discovery routinely
/// surfaces sessions even on a freshly cleaned install, so the empty-state
/// branch alone never reaches users who already run an agent.
///
/// AB-298: extracted from `IslandPanelView.installHooksHint` into a standalone
/// slot component so a theme can swap it. Takes its label text by value and
/// emits its tap through a closure — no `AppModel` reference.
struct IslandInstallHooksHint: View {
    let lang: LanguageManager
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(lang.t("island.hint.installHooks"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
