//
//  GlyphFilterImportSheet.swift
//  AntiMatter
//
//  Half-height sheet that parses a pasted Glyph filter string and shows a
//  diff preview before committing. Mirrors web `ImportFilterModal.vue`:
//  auto-pastes the clipboard if it decodes cleanly, validates on each edit,
//  shows "Old ➜ New" for select mode / simple threshold / trash mode, and
//  summarises the per-type settings. Import button only enables when the
//  parsed preview is valid.
//

import SwiftUI

struct GlyphFilterImportSheet: View {
    let engine: GameEngine
    @Environment(\.dismiss) private var dismiss

    @State private var input: String = ""
    @State private var preview: GlyphFilterImportPreview = .invalid
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Paste a Glyph filter export. Importing overwrites settings across all modes, not just the currently-selected one.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Filter export string", text: $input, axis: .vertical)
                        .font(.caption.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .lineLimit(1...4)
                        .onChange(of: input) { _, newValue in
                            revalidate(newValue)
                        }

                    if preview.valid {
                        previewCard
                    } else if !input.isEmpty {
                        Label("Not a valid Glyph filter string", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(GameColor.badPink)
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .adaptiveSheetTitle("Import Glyph Filter")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(GameColor.effarig)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") {
                        commit()
                    }
                    .disabled(!preview.valid || isImporting)
                    .tint(GameColor.effarig)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            // Auto-paste if the clipboard contains a valid filter string.
            if input.isEmpty, let pasted = UIPasteboard.general.string, !pasted.isEmpty {
                input = pasted
                revalidate(pasted)
            }
        }
    }

    // MARK: - Preview card

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            previewRow(label: "Selection mode", value: preview.selectName)
            previewRow(label: "Effect Count", value: preview.simpleDiff)
            previewRow(label: "Rejected Glyphs", value: preview.trashLabel)
            if !preview.typeSummary.isEmpty {
                Text(preview.typeSummary)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(GameColor.effarig.opacity(0.4), lineWidth: 1)
                )
        )
    }

    private func previewRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(value == "(No change)" ? .white.opacity(0.55) : GameColor.effarig.readableOnDark())
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Logic

    private func revalidate(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            preview = .invalid
            return
        }
        engine.parseGlyphFilterImport(trimmed) { result in
            preview = result
        }
    }

    private func commit() {
        isImporting = true
        engine.importGlyphFilter(input.trimmingCharacters(in: .whitespacesAndNewlines)) { ok in
            isImporting = false
            if ok { dismiss() }
        }
    }
}
