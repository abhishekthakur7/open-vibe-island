import SwiftUI
import OpenIslandCore

/// Flight Deck's empty state (AB-339 · SPEC-flight-deck §4J / Slot 6).
///
/// The shipped empty state read a dim "NO SIGNAL" — an apology for a blank hole.
/// The 2.0 board flips the tone: no sessions is a **valid, confident** state — a
/// dark panel with the power on, monitoring. The surface now leads with a lamp
/// grid (one lit lamp breathing on the slow `FlightDeckMotion.Monitor` 2.6s
/// heartbeat + three dark), a bright **ALL SYSTEMS NOMINAL** heading, a line of
/// monitoring copy, and a `BRIDGE LINK · MONITORING · 0 SESSIONS` sysline whose
/// truth is wired to `\.islandBridgeIsLive` — a dead socket reads honestly (a red
/// lamp + `NO LINK`), never a static lie. Framed in the same squared hairline
/// panel the bootstrap / install-hint states use, so the pre-list states share
/// one avionics identity. Casing + tracking neutralize for CJK.
struct FlightDeckEmptyState: View {
    let lang: LanguageManager
    let hasRecentSessions: Bool

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandBridgeIsLive) private var bridgeIsLive
    @Environment(\.islandTokens) private var tokens

    /// The sysline lamp + middle token track the bridge truth: nominal green +
    /// `MONITORING` when the socket is live, alert red + `NO LINK` when it is down.
    private var syslineColor: Color {
        bridgeIsLive ? tokens.colors.statusRunning : tokens.colors.statusFailed
    }

    /// `BRIDGE LINK · MONITORING · 0 SESSIONS` (live) / `BRIDGE LINK · NO LINK ·
    /// 0 SESSIONS` (down) — an EICAS sysline: uppercased, letterspaced, and
    /// neutralized for CJK as one composed string. The empty state is by
    /// definition a zero-session surface, so the session token is a literal `0`.
    private var syslineText: String {
        let link = lang.t("island.flightDeck.footer.bridgeLink")
        let state = lang.t(bridgeIsLive
            ? "island.flightDeck.empty.monitoring"
            : "island.flightDeck.footer.noLink")
        let sessions = lang.t("island.flightDeck.footer.sessions", 0)
        return "\(link) · \(state) · \(sessions)"
    }

    var body: some View {
        VStack(spacing: 13) {
            Spacer()

            // Lamp grid: 1 lit (breathing 2.6s) + 3 dark — the confident tone flip
            // (§4J mockup `.empty .lampgrid`).
            HStack(spacing: 7) {
                FlightDeckMonitorLamp(color: tokens.colors.statusRunning, lit: true)
                FlightDeckMonitorLamp(color: tokens.colors.statusRunning, lit: false)
                FlightDeckMonitorLamp(color: tokens.colors.statusRunning, lit: false)
                FlightDeckMonitorLamp(color: tokens.colors.statusRunning, lit: false)
            }
            .accessibilityHidden(true)

            // Confident heading — bright paper (not the shipped dim tertiary).
            Text(FlightDeckText.caps(lang.t("island.flightDeck.empty.nominal"), lang: lang))
                .font(FlightDeckTypography.microLabel)
                .tracking(FlightDeckText.tracking(1.8, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.96, increaseContrast: increasesContrast)))

            // Monitoring copy — sans prose (SPEC §2 · mockup `.empty p` 12.5px
            // sans regular), dim ink, bounded width. Prose the reader reads, so it
            // draws sans, never the mono `body` value role.
            Text(lang.t("island.flightDeck.empty.copy"))
                .font(.system(size: 12.5, weight: .regular, design: FlightDeckTypography.Family.sans.design))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))

            // Sysline — a lit dot + the wired bridge-truth caption.
            HStack(spacing: 8) {
                FlightDeckMonitorLamp(color: syslineColor, lit: true, side: 6, chamfer: 1)
                Text(FlightDeckText.caps(syslineText, lang: lang))
                    .font(.system(size: FlightDeckTypography.microLabelSize, weight: .regular, design: .monospaced))
                    .tracking(FlightDeckText.tracking(1.0, lang: lang))
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            }
            .accessibilityElement(children: .combine)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.colors.paper.opacity(increasesContrast ? 0.03 : 0.012))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)), lineWidth: 1)
                )
        )
    }
}

/// A single lamp in the empty-state grid / sysline. A lit lamp is a self-lit
/// green phosphor square breathing on the slow `FlightDeckMotion.Monitor` 2.6s
/// heartbeat (the AB-336 primitive, distinctly calmer than the 2.0s engine
/// breathe); a dark lamp is an unlit well square in a tier-2 hairline housing.
/// Driven by a single clock-free `@State` toggle (the `FlightDeckEngineLamp`
/// precedent); under Reduce Motion no animation is started and a lit lamp holds
/// its lit peak — never dark, never even acquiring a clock. Always
/// accessibility-hidden: the lamp's meaning is carried by the heading + sysline.
private struct FlightDeckMonitorLamp: View {
    let color: Color
    let lit: Bool
    var side: CGFloat = 11
    var chamfer: CGFloat = 2

    @State private var breathing = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var peak: Bool { reduceMotion || breathing }

    var body: some View {
        Group {
            if lit {
                FlightDeckChamferedRectangle(chamfer: chamfer)
                    .fill(color)
                    .opacity(peak ? FlightDeckMotion.Breathe.opacityMax : FlightDeckMotion.Breathe.opacityMin)
                    .frame(width: side, height: side)
                    .phosphorGlow(
                        shape: FlightDeckChamferedRectangle(chamfer: chamfer),
                        tint: color,
                        radius: peak ? FlightDeckMotion.Breathe.glowRadiusMax : FlightDeckMotion.Breathe.glowRadiusMin,
                        intensity: peak ? 0.7 : 0.5
                    )
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(
                            .easeInOut(duration: FlightDeckMotion.Monitor.period / 2).repeatForever(autoreverses: true)
                        ) {
                            breathing = true
                        }
                    }
            } else {
                FlightDeckChamferedRectangle(chamfer: chamfer)
                    .fill(FlightDeckSurfaces.well)
                    .frame(width: side, height: side)
                    .overlay(
                        FlightDeckChamferedRectangle(chamfer: chamfer)
                            .strokeBorder(FlightDeckSurfaces.hairline(tier: 2, increaseContrast: increasesContrast), lineWidth: 1)
                    )
            }
        }
        .accessibilityHidden(true)
    }
}
