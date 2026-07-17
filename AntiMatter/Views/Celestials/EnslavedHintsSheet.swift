//
//  EnslavedHintsSheet.swift
//  AntiMatter
//
//  Half-height sheet mirroring the web EnslavedHintsModal — spend stored
//  game time to unlock Reality + Glyph hints about how to progress through
//  The Nameless Ones' Reality. State is loaded lazily (not per-tick) via
//  `engine.loadEnslavedHints()` and refreshed every second while visible
//  so the "time to next hint" estimate stays live.
//

import SwiftUI
import Combine

struct EnslavedHintsSheet: View {
    let engine: GameEngine

    @Environment(\.dismiss) private var dismiss

    /// 1Hz refresh while the sheet is up — the time-to-afford estimate
    /// depends on real-time accumulation, so a per-second reload keeps
    /// it honest without the full per-tick polling cost.
    private let refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var hints: EnslavedHintsState? { engine.enslavedHints }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let h = hints {
                        introText
                        shownHintsSection(h)
                        if h.realityHintsUnlocked + h.glyphHintsGiven < h.realityHintsTotal + h.glyphHintsTotal {
                            costSection(h)
                            spendButtons(h)
                        } else {
                            Text("There are no more hints left.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding(16)
            }
            .background(GameColor.baseBackground)
            .adaptiveSheetTitle("Cracks in The Nameless Ones' Reality")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(GameColor.enslaved)
                }
            }
            .task { engine.loadEnslavedHints() }
            .onReceive(refreshTimer) { _ in engine.loadEnslavedHints() }
        }
        .presentationDetents([.large])
    }

    private var introText: some View {
        Text("This Reality seems to be resisting your efforts to complete it. So far you have done the following:")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Shown hints (Reality + Glyph mixed)

    @ViewBuilder
    private func shownHintsSection(_ h: EnslavedHintsState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(h.realityEntries.filter { $0.hasHint }) { entry in
                realityHintRow(entry)
            }
            ForEach(Array(h.glyphHints.enumerated()), id: \.offset) { _, text in
                glyphHintRow(text)
            }
        }
    }

    private func realityHintRow(_ entry: EnslavedProgressEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.hasProgress ? "house.fill" : "questionmark.circle")
                    .foregroundStyle(entry.hasProgress ? GameColor.enslaved : .white.opacity(0.7))
                    .font(.subheadline)
                    .frame(width: 22, alignment: .center)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.hasProgress
                         ? "You have exposed a crack in the Reality:"
                         : "You have not figured out what this hint means yet.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entry.hasProgress ? GameColor.enslaved.readableOnDark() : .white)
                    Text("— \(entry.hint)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("— \(entry.hasProgress ? entry.condition : "?????")")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(entry.hasProgress ? 0.85 : 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .modifier(RoundedBorderModifier(color: GameColor.enslaved.opacity(0.25), cornerRadius: 8, lineWidth: 1))
    }

    private func glyphHintRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "diamond.fill")
                .foregroundStyle(GameColor.enslaved)
                .font(.subheadline)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 3) {
                Text("Glyph hint:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GameColor.enslaved.readableOnDark())
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .modifier(RoundedBorderModifier(color: GameColor.enslaved.opacity(0.25), cornerRadius: 8, lineWidth: 1))
    }

    // MARK: - Cost + spend buttons

    private func costSection(_ h: EnslavedHintsState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Each hint triples the next hint's cost; this cost bump decays toward 1× over 24 hours. Finding the meaning of a hint immediately halves the cost. The floor is 1e40 years.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Next hint:")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                Text(h.nextHintCostText)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(h.canAffordHint ? GameColor.enslaved : .white.opacity(0.8))
                if !h.canAffordHint, !h.timeToNextHintText.isEmpty {
                    Spacer(minLength: 8)
                    Text("ETA: \(h.timeToNextHintText)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(.top, 4)
    }

    private func spendButtons(_ h: EnslavedHintsState) -> some View {
        let realityLeft = max(0, h.realityHintsTotal - h.realityHintsUnlocked)
        let glyphLeft = max(0, h.glyphHintsTotal - h.glyphHintsGiven)
        return VStack(spacing: 8) {
            GameButton(theme: .enslaved, isEnabled: h.canAffordHint && realityLeft > 0) {
                engine.spendTimeForRealityHint()
            } label: {
                Text("Reality hint (\(realityLeft) left)")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            GameButton(theme: .enslaved, isEnabled: h.canAffordHint && glyphLeft > 0) {
                engine.spendTimeForGlyphHint()
            } label: {
                Text("Glyph hint (\(glyphLeft) left)")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .padding(.top, 4)
    }
}
