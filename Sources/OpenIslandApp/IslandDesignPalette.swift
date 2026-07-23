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
}
