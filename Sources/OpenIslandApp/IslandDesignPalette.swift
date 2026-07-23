import SwiftUI
import OpenIslandCore

enum IslandDesignPalette {
    enum Status {
        static let waitingAggregate = Color(red: 231.0 / 255.0, green: 167.0 / 255.0, blue: 98.0 / 255.0)
        static let waitingForApproval = Color(red: 244.0 / 255.0, green: 164.0 / 255.0, blue: 164.0 / 255.0)
        static let waitingForAnswer = Color(red: 255.0 / 255.0, green: 213.0 / 255.0, blue: 138.0 / 255.0)
        static let running = Color(red: 110.0 / 255.0, green: 167.0 / 255.0, blue: 255.0 / 255.0)
        static let completed = Color(red: 111.0 / 255.0, green: 185.0 / 255.0, blue: 130.0 / 255.0)
        /// Same amber used by `IslandActionButtonStyle`'s `.warning` kind —
        /// shared "caution" tone for both a bypass-permissions chip and an
        /// interrupted completion.
        static let warning = Color(red: 0.85, green: 0.55, blue: 0.15)
        static let interrupted = warning
        static let failed = Color(red: 0.86, green: 0.32, blue: 0.32)
        static let inactive = V6Palette.paper.opacity(0.38)
        static let idle = V6Palette.paper.opacity(0.35)

        static func tint(for phase: SessionPhase, outcome: SessionOutcome = .success) -> Color {
            switch phase {
            case .waitingForApproval:
                waitingForApproval
            case .waitingForAnswer:
                waitingForAnswer
            case .running:
                running
            case .completed:
                switch outcome {
                case .success:
                    completed
                case .interrupted:
                    interrupted
                case .failed:
                    failed
                }
            }
        }

        static func tint(
            for phase: SessionPhase,
            presence: IslandSessionPresence,
            outcome: SessionOutcome = .success
        ) -> Color {
            if phase == .waitingForApproval || phase == .waitingForAnswer {
                return tint(for: phase)
            }

            switch presence {
            case .running:
                return running
            case .active:
                // Presence only resolves to `.active` here when the phase is
                // `.completed` (running/attention phases are handled above),
                // so it's safe to fold in the outcome tint.
                return tint(for: .completed, outcome: outcome)
            case .inactive:
                return inactive
            }
        }
    }

    /// AB-244: contrast tokens for dim body text and hairline dividers.
    /// Pre-existing values ranged 0.25–0.42 for de-emphasized-but-still-
    /// informative text (contrast ratio as low as ~2:1 against the near-
    /// black ground) and 0.045–0.08 for row/section dividers. `secondary`/
    /// `tertiary` raise the text tiers to clear WCAG's 4.5:1 normal-text
    /// threshold with headroom for the app's translucent (not pure-black)
    /// vibrancy background; `hairline` stays subtle by default but jumps to
    /// a clearly visible boundary when the user has Increase Contrast on.
    enum Contrast {
        static let secondaryText: Double = 0.55
        static let tertiaryText: Double = 0.48

        static func text(_ base: Double, increaseContrast: Bool) -> Double {
            increaseContrast ? min(1, base + 0.24) : base
        }

        static func hairline(increaseContrast: Bool) -> Double {
            increaseContrast ? 0.22 : 0.055
        }
    }
}
