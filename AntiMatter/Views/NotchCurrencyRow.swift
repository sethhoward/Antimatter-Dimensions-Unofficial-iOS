//
//  NotchCurrencyRow.swift
//  AntiMatter
//
//  EP and IP labels positioned in the status bar zone flanking the Dynamic Island.
//  Lives outside the TabView in PhoneShell's ZStack so it can ignore safe areas.
//

import SwiftUI

struct NotchCurrencyRow: View {
    let engine: GameEngine

    /// Cached top safe area inset — read once on appear, constant for a given device.
    @State private var topInset: CGFloat = 50

    private let colorEternity = GameColor.eternity
    private let colorInfinity = GameColor.infinity

    var body: some View {
        HStack {
            if engine.eternityUnlocked {
                NotchCurrencyLabel(value: engine.currentEP,
                                   suffix: Self.suffix(for: engine.currentEP, short: "EP", long: "Eternity Points"),
                                   color: colorEternity)
            }

            Spacer()

            if engine.infinityUnlocked {
                NotchCurrencyLabel(value: engine.currentIP,
                                   suffix: Self.suffix(for: engine.currentIP, short: "IP", long: "Infinity Points"),
                                   color: colorInfinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, topInset)
        .allowsHitTesting(false)
        .background(backgroundInsetReader)
    }

    /// Spell out "Infinity Points" / "Eternity Points" when the raw value is
    /// below 100 — i.e. the formatted string has no abbreviation suffix
    /// ("42 K", "1.2e5") and parses under 100 as a plain decimal.
    private static func suffix(for formatted: String, short: String, long: String) -> String {
        let trimmed = formatted.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(" ") || trimmed.contains("e") { return short }
        guard let n = Double(trimmed), n < 100 else { return short }
        return long
    }

    @ViewBuilder
    private var backgroundInsetReader: some View {
        // Read safe area inset once — no per-frame GeometryReader
        GeometryReader { geo in
            Color.clear.onAppear {
                topInset = geo.safeAreaInsets.top
            }
        }
        .frame(height: 0)
    }
}

/// Isolated currency label — prevents parent HStack/Spacer re-layout on every tick.
/// CATextLayer-backed to bypass SwiftUI `ResolvedTextFilter`.
private struct NotchCurrencyLabel: View {
    let value: String
    let suffix: String
    let color: Color

    var body: some View {
        NotchCurrencyLabelRenderer(value: value, suffix: suffix, color: color)
            .fixedSize()
            .frame(height: 17)
    }
}
