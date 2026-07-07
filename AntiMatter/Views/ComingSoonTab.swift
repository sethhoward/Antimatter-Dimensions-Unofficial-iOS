//
//  ComingSoonTab.swift
//  AntiMatter
//
//  Reusable placeholder for tabs not yet implemented.
//

import SwiftUI

struct ComingSoonTab: View {
    let title: String
    let accentColor: Color
    /// Optional one-liner teasing what the tab will contain. Useful for
    /// celestials whose mechanics are non-obvious (V's 9 achievements,
    /// Ra's pets, etc.) so the placeholder doesn't feel like a dead end.
    var hint: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.title2.weight(.medium))
                .foregroundStyle(accentColor)
            Text("Coming Soon")
                .font(.headline)
                .foregroundStyle(.secondary)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
