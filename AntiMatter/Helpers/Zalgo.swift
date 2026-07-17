//
//  Zalgo.swift
//  AntiMatter
//
//  Pure Swift port of `src/core/celestials/pelle/zalgo.js`. Applies a
//  deterministic combining-mark corruption to a string at a given level.
//  Used by the GameEnd finale to garble UI text as `endState` increases.
//
//  The web's algorithm is itself adapted from a JS Fiddle (jsfiddle.net/JKirchartz/wwckP);
//  it uses a 3-array combining-mark table (up / down / mid) and a tiny
//  PRNG seeded by character codes, so identical inputs produce identical
//  outputs at the same level. Re-randomization across time comes from
//  changing the seed, not from rerolling Math.random.
//

import Foundation
import SwiftUI

enum Zalgo {
    /// Combining marks above the baseline (web `Zalgo.chars[0]`).
    static let upMarks: [Character] = [
        "\u{030d}", "\u{030e}", "\u{0304}", "\u{0305}", "\u{033f}",
        "\u{0311}", "\u{0306}", "\u{0310}", "\u{0352}", "\u{0357}",
        "\u{0351}", "\u{0307}", "\u{0308}", "\u{030a}", "\u{0342}",
        "\u{0343}", "\u{0344}", "\u{034a}", "\u{034b}", "\u{034c}",
        "\u{0303}", "\u{0302}", "\u{030c}", "\u{0350}", "\u{0300}",
        "\u{0301}", "\u{030b}", "\u{030f}", "\u{0312}", "\u{0313}",
        "\u{0314}", "\u{033d}", "\u{0309}", "\u{0363}", "\u{0364}",
        "\u{0365}", "\u{0366}", "\u{0367}", "\u{0368}", "\u{0369}",
        "\u{036a}", "\u{036b}", "\u{036c}", "\u{036d}", "\u{036e}",
        "\u{036f}", "\u{033e}", "\u{035b}", "\u{0346}", "\u{031a}"
    ]
    /// Combining marks below the baseline (web `Zalgo.chars[1]`).
    static let downMarks: [Character] = [
        "\u{0316}", "\u{0317}", "\u{0318}", "\u{0319}", "\u{031c}",
        "\u{031d}", "\u{031e}", "\u{031f}", "\u{0320}", "\u{0324}",
        "\u{0325}", "\u{0326}", "\u{0329}", "\u{032a}", "\u{032b}",
        "\u{032c}", "\u{032d}", "\u{032e}", "\u{032f}", "\u{0330}",
        "\u{0331}", "\u{0332}", "\u{0333}", "\u{0339}", "\u{033a}",
        "\u{033b}", "\u{033c}", "\u{0345}", "\u{0347}", "\u{0348}",
        "\u{0349}", "\u{034d}", "\u{034e}", "\u{0353}", "\u{0354}",
        "\u{0355}", "\u{0356}", "\u{0359}", "\u{035a}", "\u{0323}"
    ]
    /// Combining marks through the baseline (web `Zalgo.chars[2]`).
    static let midMarks: [Character] = [
        "\u{0315}", "\u{031b}", "\u{0340}", "\u{0341}", "\u{0358}",
        "\u{0321}", "\u{0322}", "\u{0327}", "\u{0328}", "\u{0334}",
        "\u{0335}", "\u{0336}", "\u{034f}", "\u{035c}", "\u{035d}",
        "\u{035e}", "\u{035f}", "\u{0360}", "\u{0362}", "\u{0338}",
        "\u{0337}", "\u{0361}", "\u{0489}"
    ]

    /// Web `Zalgo.random` — deterministic PRNG. Returns an index in `[0, len)`
    /// (or 0 when len <= 1).
    private static func random(_ len: Int, seed: Int) -> Int {
        if len <= 1 { return 0 }
        // 66669 * seed % 981 / 997 mirrors the JS exactly (integer % then
        // float divide). Use Double to avoid overflow on the * 66669.
        let x = Double(66669 &* seed % 981) / 997.0
        return Int(floor(x * Double(len) + 1)) - 1
    }

    /// Generate a zalgo-corrupted version of `str` at the given `level`.
    /// `level == 0` returns the input unchanged; higher levels stack more
    /// combining marks per character (capped by an additional 50% gate).
    static func generate(_ str: String, level: Int) -> String {
        if level <= 0 { return str }
        let chars = Array(str)
        // Seed from sum of UTF-16 code units (mirrors `charCodeAt` reduce).
        var seed = chars.reduce(0) { acc, ch in
            acc + Int(ch.unicodeScalars.first?.value ?? 0)
        }
        var out = ""
        out.reserveCapacity(str.count * (1 + level / 2))
        for ch in chars {
            if ch == " " { out.append(ch); continue }
            var aug = String(ch)
            for _ in 0..<level {
                let bucket = random(3, seed: seed); seed += 1
                let coin = random(10, seed: seed); seed += 1
                if Double(coin) / 10.0 >= 0.5 {
                    let table: [Character] = bucket == 0 ? upMarks
                        : (bucket == 1 ? downMarks : midMarks)
                    let pick = random(table.count, seed: seed); seed += 1
                    aug.append(table[pick])
                }
            }
            out.append(aug)
        }
        return out
    }
}

// MARK: - SwiftUI view modifier

/// Wraps any `Text`-shaped content with a periodic zalgo re-roll. When
/// `intensity` is 0, passes the input through unchanged (no animation,
/// no per-frame work). When > 0 and the scene is active, re-corrupts
/// every 500ms (matches web's perception of mounting decay).
struct ZalgoModifier: ViewModifier {
    let text: String
    let intensity: Double
    @Environment(\.scenePhase) private var scenePhase

    private var level: Int {
        // 0..6 — by CREDITS_START (4.5) we want ~6 layers, well-corrupted
        // but still legible enough to read role names.
        max(0, min(6, Int(round(intensity * 6))))
    }

    private var isAnimating: Bool {
        scenePhase == .active && level > 0
    }

    func body(content: Content) -> some View {
        if isAnimating {
            TimelineView(.animation(minimumInterval: 0.5, paused: false)) { ctx in
                let seed = Int(ctx.date.timeIntervalSinceReferenceDate * 2)
                Text(Zalgo.generate(text + " " + String(seed % 7), level: level)
                        .replacingOccurrences(of: " " + String(seed % 7), with: ""))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else if level > 0 {
            Text(Zalgo.generate(text, level: level))
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            content
        }
    }
}

extension View {
    /// Apply zalgo corruption to the text at the given intensity (0..1).
    /// At 0 the view is unchanged. Above 0 a 500ms re-roll kicks in while
    /// the scene is active. Pass the original text so the modifier can
    /// re-corrupt deterministically each tick.
    func zalgofied(_ text: String, intensity: Double) -> some View {
        modifier(ZalgoModifier(text: text, intensity: intensity))
    }
}
