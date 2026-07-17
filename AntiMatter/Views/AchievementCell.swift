//
//  AchievementCell.swift
//  AntiMatter
//
//  Individual achievement tile: artwork background from sprite sheet,
//  ID number top-left, star + check/X icons bottom-right.
//  Name text is baked into the sprite artwork — no label overlay needed.
//
//  Row 18 achievements are "obscured" (hidden behind a ? icon with garbled
//  text) until unlocked, matching web's `o-achievement--hidden` behavior.
//

import SwiftUI

/// Achievement IDs whose effects are nullified by Pelle's Doomed Reality.
/// Mirrors `Pelle.disabledAchievements` (`pelle.js:184-186`).
private let pelleDisabledAchievements: Set<Int> = [
    37, 54, 55, 65, 74, 76, 78, 85, 87, 91, 92, 93, 95, 103, 104, 111, 113,
    116, 117, 118, 125, 126, 131, 132, 133, 134, 137, 141, 142, 143, 156, 164
]

struct AchievementCell: View {
    let achievement: AchievementState
    let engine: GameEngine
    @State private var showDetail = false
    /// Re-randomization tick for the obscured-row garble animation. Bumps
    /// every ~300ms while the scene is active (gated by TimelineView's
    /// `paused:` parameter so background scenes don't burn CPU).
    @State private var garbleTick: Int = 0
    @Environment(\.scenePhase) private var scenePhase

    private var tileImage: UIImage? {
        AchievementImageProvider.shared.image(for: achievement)
    }

    /// True when Pelle has nullified this achievement's reward — only meaningful
    /// for achievements that are unlocked (locked ones are already greyed).
    private var isPelleDisabled: Bool {
        engine.pelleDoomed && pelleDisabledAchievements.contains(achievement.id)
    }

    var body: some View {
        tileContent
            .onTapGesture { showDetail = true }
            .popover(isPresented: $showDetail, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
                achievementDetail
                    .presentationCompactAdaptation(.popover)
            }
            #if DEBUG
            .contextMenu {
                if achievement.isUnlocked {
                    Button(role: .destructive) {
                        engine.devCommand("Achievement(\(achievement.id)).lock()")
                    } label: {
                        Label("Lock Achievement", systemImage: "lock")
                    }
                } else {
                    Button {
                        engine.devCommand("Achievement(\(achievement.id)).unlock()")
                    } label: {
                        Label("Unlock Achievement", systemImage: "lock.open")
                    }
                }
            }
            #endif
    }

    // MARK: - Tile content

    // Web CSS: waiting indicator = #d1d161, waiting border = #acac39
    private static let waitingColor = Color(red: 0.820, green: 0.820, blue: 0.380)  // #d1d161
    private static let waitingBorder = Color(red: 0.675, green: 0.675, blue: 0.224) // #acac39

    // Web CSS: .o-achievement--hidden { background-color: #555555; border-color: black }
    private static let obscuredBg = Color(red: 0.333, green: 0.333, blue: 0.333)    // #555555

    @ViewBuilder
    private var tileContent: some View {
        let isWaiting = achievement.isWaiting
        let isObscured = achievement.isObscured
        // For obscured (last-row) achievements: re-roll the garble seed
        // every ~300ms so the random characters cycle, matching web's
        // `processText` re-render cadence. Paused when the scene isn't
        // active so it doesn't burn CPU on the lock screen.
        Group {
            if isObscured {
                TimelineView(.animation(minimumInterval: 0.3, paused: scenePhase != .active)) { ctx in
                    let seed = Int(ctx.date.timeIntervalSinceReferenceDate * 3.3)
                    obscuredTile(seed: seed)
                }
            } else {
                normalTile(isWaiting: isWaiting)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // Web parity: unlocked tiles have no visible per-tile border (the
        // dark green CSS border blends into the green background). Row
        // completion is signalled by the dark green backdrop on the row.
        // Locked tiles keep their red outline so they pop against the dark
        // theme. Obscured (Pelle row) keeps black; Pelle-disabled keeps red.
        .roundedBorder(
            isObscured ? Color.black
            : isPelleDisabled && achievement.isUnlocked ? GameColor.pelle
            : achievement.isUnlocked ? Color.clear
            : isWaiting ? Self.waitingBorder
            : Color.red.opacity(0.6),
            cornerRadius: 4,
            lineWidth: isObscured ? 1.5
            : achievement.isUnlocked ? 0
            : isWaiting ? 2
            : 1
        )
    }

    @ViewBuilder
    private func obscuredTile(seed: Int) -> some View {
        ZStack {
            Rectangle()
                .fill(Self.obscuredBg)

            Text("?")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))

            // Animated garbled ID — bottom-leading, re-rolled per seed.
            Text(processText("\(achievement.id)", seed: seed))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .shadow(color: .black, radius: 2, x: 0, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(4)
        }
    }

    @ViewBuilder
    private func normalTile(isWaiting: Bool) -> some View {
        ZStack {
            // Colored background: red=unlocked-but-Pelle-disabled, green=unlocked,
            // yellow=waiting, gray=locked.
            Rectangle()
                .fill(isPelleDisabled && achievement.isUnlocked ? GameColor.pelle.opacity(0.35)
                      : achievement.isUnlocked ? Color.green.opacity(0.35)
                      : isWaiting ? Self.waitingColor.opacity(0.3)
                      : Color.gray.opacity(0.25))

            // Achievement artwork
            if let img = tileImage {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .saturation(achievement.isUnlocked ? 1.0 : isWaiting ? 0.6 : 0.4)
                    .opacity(achievement.isUnlocked ? 1.0 : isWaiting ? 0.7 : 0.6)
            }

            // ID number — bottom left
            Text("\(achievement.id)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .shadow(color: .black, radius: 2, x: 0, y: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(4)

            // Star + status icons — bottom right
            HStack(spacing: 3) {
                if achievement.hasReward {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)
                        .shadow(color: .black, radius: 2)
                }
                if achievement.isUnlocked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                        .shadow(color: .black, radius: 2)
                } else if isWaiting {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Self.waitingColor)
                        .shadow(color: .black, radius: 2)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.red)
                        .shadow(color: .black, radius: 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(4)
        }
    }

    // MARK: - Garbled text (matches web's processText for obscured achievements)

    /// Deterministic garble: replaces each non-space character with a pseudo-random
    /// printable ASCII char, seeded by the character code and position.
    /// Mirrors `makeGarbledTemplate()` from NormalAchievement.vue.
    private func garbleText(_ text: String) -> String {
        var result = ""
        for (i, ch) in text.enumerated() {
            if ch == " " {
                result += " "
            } else {
                let n = Int(ch.asciiValue ?? UInt8(ch.unicodeScalars.first?.value ?? 0))
                let code = 33 + ((n * n + i * i) % 93)
                result += String(UnicodeScalar(code) ?? UnicodeScalar(63)) // 63 = '?'
            }
        }
        return result
    }

    /// Animated garble — mirrors web `processText` + `wordShift.randomCrossWords`:
    /// starts from the deterministic template and replaces ~70% of non-space
    /// chars with random Latin-1 supplement codepoints (192-241), seeded by
    /// the timeline tick so it cycles every render. Spaces stay intact so
    /// length / wrap behavior matches the original text.
    private func processText(_ text: String, seed: Int) -> String {
        let template = Array(garbleText(text))
        var chars = template
        let len = chars.count
        guard len > 0 else { return "" }
        let replacements = Int(Double(len) * 0.7)
        // Use a small linear congruential generator seeded by `seed + i`
        // so the random positions cycle each tick. Same idea as the JS
        // predictableRandom call but cheap enough to run inline at 3Hz.
        for i in 0..<replacements {
            let s = UInt32(bitPattern: Int32(truncatingIfNeeded: seed &* 1103515245 &+ Int(i) &* 12345))
            let pos = Int(s % UInt32(len))
            let glyphCode = 192 + Int((s >> 8) % 50)  // matches web's randomSymbol() range
            if let scalar = UnicodeScalar(glyphCode), template[pos] != " " {
                chars[pos] = Character(scalar)
            }
        }
        return String(chars)
    }

    // MARK: - Detail popover

    private var achievementDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            if achievement.isObscured {
                // Animate name + description in the detail popover too
                // (matches web's `processedName` / `processedDescription`,
                // both refreshed every garble tick). The ID stays obscured
                // — revealing the number on the popover would defeat the
                // hidden-row mechanic.
                TimelineView(.animation(minimumInterval: 0.3, paused: scenePhase != .active)) { ctx in
                    let seed = Int(ctx.date.timeIntervalSinceReferenceDate * 3.3)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            wrappingText(processText(achievement.name, seed: seed),
                                         font: .subheadline.weight(.semibold).monospaced())
                            Spacer(minLength: 4)
                            Text("#\(processText("\(achievement.id)", seed: seed))")
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        wrappingText(processText(achievement.description, seed: seed),
                                     font: .caption.monospaced(),
                                     style: .secondary)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    wrappingText(achievement.name, font: .subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Text("#\(achievement.id)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                wrappingText(achievement.description, font: .caption, style: .secondary)
                if let reward = achievement.reward {
                    Divider().padding(.vertical, 2)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        wrappingText(reward, font: .caption2)
                    }
                }
            }
        }
        .padding(10)
        .frame(idealWidth: 260, maxWidth: 320)
    }

    /// Text that wraps freely and reports its full wrapped height to the
    /// parent — explicit `.lineLimit(nil)` + per-Text `.fixedSize(vertical:)`
    /// avoids truncation inside the popover's height-computation pass.
    @ViewBuilder
    private func wrappingText(_ string: String, font: Font, style: HierarchicalShapeStyle = .primary) -> some View {
        Text(string)
            .font(font)
            .foregroundStyle(style)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
