//
//  EffarigStageBanner.swift
//  AntiMatter
//
//  Small banner shown at the top of the Glyphs tab while the player is inside
//  Effarig's Reality. Reports the current stage (Infinity / Eternity / Reality)
//  and the active Glyph level cap (100 / 1500 / 2000) so players understand why
//  newly-generated Glyphs are capped.
//

import SwiftUI

struct EffarigStageBanner: View {
    let stageName: String
    let glyphLevelCap: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("Ϙ")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Effarig's Reality — \(stageName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white)
                Text("New Glyph level cap: \(glyphLevelCap)")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(GameColor.effarig.opacity(0.85))
        )
    }
}
