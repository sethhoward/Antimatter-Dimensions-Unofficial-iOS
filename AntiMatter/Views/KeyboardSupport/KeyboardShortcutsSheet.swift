//
//  KeyboardShortcutsSheet.swift
//  AntiMatter
//
//  Options-tab sheet listing every visible keyboard shortcut, grouped by
//  category. Visibility is resolved once on appear (single batched JS eval
//  via `GameEngine.loadKeyboardShortcutVisibility`); the sheet does not
//  refresh while open.
//

import SwiftUI

struct KeyboardShortcutsSheet: View {
    let engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    @State private var visibilityFlags: [String: Bool] = [:]
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Connect a hardware keyboard to use these shortcuts. Some keys may need configuration in Settings → General → Keyboard → Hardware Keyboard for non-US layouts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    ForEach(KeyboardShortcutCategory.allCases.sorted(by: { $0.sortIndex < $1.sortIndex }), id: \.self) { category in
                        let rows = visibleRows(in: category)
                        if !rows.isEmpty {
                            categorySection(title: category.rawValue, rows: rows)
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color.black.opacity(0.001))
            .adaptiveSheetTitle("Keyboard Shortcuts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            engine.loadKeyboardShortcutVisibility { flags in
                self.visibilityFlags = flags
            }
        }
    }

    private func visibleRows(in category: KeyboardShortcutCategory) -> [KeyboardShortcutDescriptor] {
        KeyboardShortcuts.visibleRows(for: visibilityFlags).filter { $0.category == category }
    }

    private func categorySection(title: String, rows: [KeyboardShortcutDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    HStack {
                        Text(row.name)
                            .font(.subheadline)
                        Spacer()
                        Text(row.displayCombo)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    if idx < rows.count - 1 {
                        Divider().background(Color.white.opacity(0.06))
                    }
                }
            }
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }
}
