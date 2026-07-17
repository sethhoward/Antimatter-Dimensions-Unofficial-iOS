//
//  AutomatorErrorListView.swift
//  AntiMatter
//
//  Displays compiler errors for the current Automator script.
//  Matches AutomatorErrorPage.vue layout.
//

import SwiftUI

struct AutomatorErrorListView: View {
    let errors: [AutomatorErrorInfo]
    let onTapError: (Int) -> Void   // Passes line number to scroll editor

    var body: some View {
        if errors.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(GameColor.reality)
                Text("No script errors found!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    Text("\(errors.count) error\(errors.count == 1 ? "" : "s") found")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GameColor.badPink)
                        .padding(.horizontal, 10)

                    ForEach(errors) { error in
                        errorCard(error)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func errorCard(_ error: AutomatorErrorInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(GameColor.badPink)
                Text("Line \(error.startLine)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GameColor.badPink)
                Spacer()
            }

            Text(error.info)
                .font(.caption2)
                .foregroundStyle(.white)

            if !error.tip.isEmpty {
                Text("Tip: \(error.tip)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(GameColor.badPink.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            onTapError(error.startLine)
        }
    }
}
