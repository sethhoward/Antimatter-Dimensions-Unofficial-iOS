//
//  AutomatorScriptListView.swift
//  AntiMatter
//
//  Script management list: select, create, rename, delete, import, export scripts.
//  Matches AutomatorScriptDropdownEntryList.vue + import/export from AutomatorDocs.vue.
//

import SwiftUI

struct AutomatorScriptListView: View {
    let engine: GameEngine
    let onSelectScript: (Int) -> Void
    private var state: AutomatorEditorState { engine.gameState.automatorEditorState }

    @State private var renamingScriptID: Int?
    @State private var renameText = ""
    @State private var deleteConfirmID: Int?
    @State private var showImportSheet = false
    @State private var menuScriptID: Int?

    var body: some View {
        VStack(spacing: 0) {
            // Header with char counts
            HStack {
                Text("Scripts (\(state.scripts.count)/\(state.maxScriptCount))")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(state.totalChars)/\(state.maxTotalChars) chars")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.scripts) { script in
                        scriptRow(script)
                        Divider().background(Color.white.opacity(0.06))
                    }
                }
            }

            Divider().background(Color.white.opacity(0.1))

            // Action buttons
            HStack(spacing: 0) {
                // New script
                if state.scripts.count < state.maxScriptCount {
                    actionButton(icon: "plus", label: "New") {
                        engine.automatorNewScript()
                    }
                }

                Divider().frame(height: 20).background(Color.white.opacity(0.1))

                // Export
                actionButton(icon: "square.and.arrow.up", label: "Export") {
                    engine.automatorExportScript()
                }

                Divider().frame(height: 20).background(Color.white.opacity(0.1))

                // Import
                actionButton(
                    icon: "square.and.arrow.down",
                    label: "Import",
                    enabled: state.scripts.count < state.maxScriptCount
                ) {
                    showImportSheet = true
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            AutomatorImportSheet(engine: engine)
        }
        .alert("Delete Script?", isPresented: Binding(
            get: { deleteConfirmID != nil },
            set: { if !$0 { deleteConfirmID = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = deleteConfirmID {
                    engine.automatorDeleteScript(id)
                }
                deleteConfirmID = nil
            }
            Button("Cancel", role: .cancel) { deleteConfirmID = nil }
        } message: {
            if let id = deleteConfirmID,
               let script = state.scripts.first(where: { $0.id == id }) {
                Text("Delete '\(script.name)'? This cannot be undone.")
            }
        }
        // Long-press menu — uses .confirmationDialog instead of .contextMenu because
        // context-menu actions don't fire inside SubtabPager's UIHostingController
        // (see the design notes "SubtabPager Known Issues → Context menu actions don't fire").
        .confirmationDialog(
            menuScriptID.flatMap { id in state.scripts.first(where: { $0.id == id })?.name } ?? "Script",
            isPresented: Binding(
                get: { menuScriptID != nil },
                set: { if !$0 { menuScriptID = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let id = menuScriptID,
               let script = state.scripts.first(where: { $0.id == id }) {
                Button("Rename") {
                    renameText = script.name
                    renamingScriptID = script.id
                    menuScriptID = nil
                }
                if state.scripts.count > 1 {
                    Button("Delete", role: .destructive) {
                        deleteConfirmID = script.id
                        menuScriptID = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { menuScriptID = nil }
        }
        // Rename via an alert with an embedded TextField — window-level, so it
        // presents reliably inside SubtabPager (the inline-edit row had no visible
        // affordance and didn't focus, so it looked like nothing happened). Matches
        // the SaveSlotsSection rename pattern.
        .alert("Rename Script", isPresented: Binding(
            get: { renamingScriptID != nil },
            set: { if !$0 { renamingScriptID = nil } }
        )) {
            TextField("Script name", text: $renameText)
            Button("Save") {
                if let id = renamingScriptID {
                    let trimmed = String(renameText.prefix(15)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        engine.automatorRenameScript(id, name: trimmed)
                    }
                }
                renamingScriptID = nil
            }
            Button("Cancel", role: .cancel) { renamingScriptID = nil }
        }
    }

    // MARK: - Action Button

    private func actionButton(icon: String, label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(enabled ? GameColor.reality : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(enabled)
    }

    // MARK: - Script Row

    private func scriptRow(_ script: AutomatorScriptInfo) -> some View {
        let isEditing = script.id == state.editingScriptID
        let isRunning = script.id == state.runningScriptID && state.isOn

        return HStack(spacing: 8) {
            // Status indicator
            if isRunning {
                Circle()
                    .fill(state.isRunning ? GameColor.reality : .yellow)
                    .frame(width: 6, height: 6)
            }

            // Name
            Text(script.name.isEmpty ? "Untitled" : script.name)
                .font(.caption.weight(isEditing ? .bold : .medium))
                .foregroundStyle(isEditing ? GameColor.reality : .white)
                .lineLimit(1)

            Spacer()

            // Char count
            Text("\(script.contentLength)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Status badge
            if isEditing {
                Text("editing")
                    .font(.caption2)
                    .foregroundStyle(GameColor.reality)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(isEditing ? Color.white.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            engine.automatorSelectScript(script.id)
            onSelectScript(script.id)
        }
        .onLongPressGesture {
            menuScriptID = script.id
        }
    }
}

// MARK: - Import Sheet

private struct AutomatorImportSheet: View {
    let engine: GameEngine
    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var preview: AutomatorImportPreview?
    @State private var parseError = false
    @State private var importConstants = true
    @State private var isParsing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Description
                    Text("This will create a new Automator script at the end of your list. Paste an exported script string below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    // Input field (single-line — no wrapping/hyphenation)
                    TextField("Paste exported script data...", text: $inputText)
                        .font(.system(.caption, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(white: 0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                        .onChange(of: inputText) { _, newValue in
                            parseInput(newValue)
                        }

                    if isParsing {
                        ProgressView()
                            .padding()
                    } else if parseError && !inputText.isEmpty {
                        Text("Could not parse the input. Make sure you have a valid exported automator script.")
                            .font(.caption)
                            .foregroundStyle(GameColor.badPink)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    } else if let preview {
                        previewSection(preview)
                    }

                    // Import button
                    if preview != nil {
                        GameButton(borderColor: GameColor.reality, isEnabled: true) {
                            performImport()
                        } label: {
                            Text("Import")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(GameColor.reality)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 40)
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color(white: 0.05))
            .adaptiveSheetTitle("Import Automator Script Data")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                // Auto-paste from clipboard
                if let clip = UIPasteboard.general.string {
                    let clean = sanitized(clip)
                    if clean.hasPrefix("AntimatterDimensions") {
                        inputText = clean
                        parseInput(clean)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    // MARK: - Preview Section

    private func previewSection(_ preview: AutomatorImportPreview) -> some View {
        VStack(spacing: 12) {
            // Script info
            VStack(spacing: 4) {
                Text("Script name: \(preview.name)")
                    .font(.subheadline.weight(.medium))
                Text("Line count: \(preview.lineCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Constants
            if !preview.constants.isEmpty {
                VStack(spacing: 6) {
                    HStack(spacing: 12) {
                        Text("Constants:")
                            .font(.caption.weight(.medium))
                        ForEach(preview.constants, id: \.self) { name in
                            Text("\"\(name)\"")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Toggle for importing constants
                    Button {
                        importConstants.toggle()
                    } label: {
                        Text(importConstants ? "Will Import Constants" : "Will Skip Constants")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(importConstants ? GameColor.reality : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(importConstants ? GameColor.reality : Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Presets
            if !preview.presets.isEmpty {
                HStack(spacing: 12) {
                    Text("Presets:")
                        .font(.caption.weight(.medium))
                    ForEach(preview.presets, id: \.self) { name in
                        Text("\"\(name)\"")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Error warning
            if preview.hasErrors {
                VStack(spacing: 2) {
                    Text("This script has errors which need to be fixed before it can be run!")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GameColor.badPink)
                        .multilineTextAlignment(.center)
                    if preview.isFullData {
                        Text("Some errors may be fixed with the additional data being imported.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Actions

    /// Strip whitespace, newlines, and hyphens that iOS text input may insert into the encoded string.
    /// Hyphens are not valid Base64 characters — they're artifacts of iOS text hyphenation.
    private func sanitized(_ text: String) -> String {
        var chars = CharacterSet.whitespacesAndNewlines
        chars.insert("-")
        return text.components(separatedBy: chars).joined()
    }

    private func parseInput(_ text: String) {
        let clean = sanitized(text)
        guard !clean.isEmpty else {
            preview = nil
            parseError = false
            return
        }
        isParsing = true
        parseError = false
        preview = nil
        engine.automatorParseImport(clean) { result in
            isParsing = false
            if let result {
                preview = result
                parseError = false
            } else {
                preview = nil
                parseError = true
            }
        }
    }

    private func performImport() {
        engine.automatorImportScript(sanitized(inputText), importConstants: importConstants) { _ in
            dismiss()
        }
    }
}
