//
//  AutomatorConstantsView.swift
//  AntiMatter
//
//  Automator Constants editor — define case-sensitive named constants usable in
//  scripts in place of numbers or Time Study import strings. Port of
//  AutomatorDefinePage.vue + AutomatorDefineSingleEntry.vue.
//
//  Constants are fetched on demand (not per-tick). Each row commits on focus
//  loss / submit, validating JS-side and routing to add/modify/rename/delete
//  exactly like the web handleFocus().
//

import SwiftUI

struct AutomatorConstantsView: View {
    let engine: GameEngine

    @State private var snapshot: AutomatorConstantsSnapshot = .empty
    @State private var showClearConfirm = false

    private var hasConstants: Bool { !snapshot.constants.isEmpty }
    private var atLimit: Bool { snapshot.constants.count >= snapshot.maxCount }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Define case-sensitive constants to use in place of numbers or Time Study import strings. These are shared across all scripts (max \(snapshot.maxCount)). Names and values are limited to \(snapshot.maxNameLength) and \(snapshot.maxValueLength) characters. Changes apply once any running script is restarted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Example: defining first 🠈 11,21,22,31,32,33 lets you use studies purchase first.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    GameButton(borderColor: GameColor.badPink, isEnabled: hasConstants) {
                        showClearConfirm = true
                    } label: {
                        Text("Delete all constants")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(hasConstants ? GameColor.badPink : .secondary)
                            .padding(.vertical, 8)
                    }

                    GameButton(borderColor: GameColor.reality, isEnabled: true) {
                        engine.importTSConstants()
                        refresh(after: 0.2)
                    } label: {
                        Text("Import Time Study Presets")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(GameColor.reality)
                            .padding(.vertical, 8)
                    }
                }

                VStack(spacing: 6) {
                    ForEach(snapshot.constants) { constant in
                        ConstantRow(
                            engine: engine,
                            existing: constant,
                            maxNameLength: snapshot.maxNameLength,
                            maxValueLength: snapshot.maxValueLength,
                            onChanged: { refresh(after: 0.15) }
                        )
                        .id(constant.name)
                    }

                    if !atLimit {
                        // New-constant row. Keyed on count so it resets to empty
                        // once an add succeeds and the snapshot grows.
                        ConstantRow(
                            engine: engine,
                            existing: nil,
                            maxNameLength: snapshot.maxNameLength,
                            maxValueLength: snapshot.maxValueLength,
                            onChanged: { refresh(after: 0.15) }
                        )
                        .id("new-\(snapshot.constants.count)")
                    }
                }
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(GameColor.reality.opacity(0.4), lineWidth: 1)
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .onAppear { refresh() }
        .alert("Delete all constants?", isPresented: $showClearConfirm) {
            Button("Delete All", role: .destructive) {
                engine.clearAutomatorConstants()
                refresh(after: 0.2)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every defined constant. This cannot be undone.")
        }
    }

    private func refresh(after delay: Double = 0) {
        let load = { engine.loadAutomatorConstants { snapshot = $0 } }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: load)
        } else {
            load()
        }
    }
}

// MARK: - Single constant row

private struct ConstantRow: View {
    let engine: GameEngine
    let existing: AutomatorConstantInfo?
    let maxNameLength: Int
    let maxValueLength: Int
    let onChanged: () -> Void

    @State private var oldAlias: String = ""
    @State private var aliasString: String = ""
    @State private var valueString: String = ""
    @State private var errorText: String = ""
    @FocusState private var focusedField: Field?

    private enum Field { case name, value }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                TextField("New constant…", text: $aliasString)
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(GameColor.reality)
                    .focused($focusedField, equals: .name)
                    .onChange(of: aliasString) { _, newValue in
                        if newValue.count > maxNameLength {
                            aliasString = String(newValue.prefix(maxNameLength))
                        }
                    }
                    .onSubmit { commit() }
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !aliasString.isEmpty {
                    Text("🠈")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Value…", text: $valueString)
                        .font(.system(.caption, design: .monospaced))
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(GameColor.reality)
                        .focused($focusedField, equals: .value)
                        .onChange(of: valueString) { _, newValue in
                            if newValue.count > maxValueLength {
                                valueString = String(newValue.prefix(maxValueLength))
                            }
                        }
                        .onSubmit { commit() }
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        deleteRow()
                    } label: {
                        Image(systemName: "eraser")
                            .font(.caption)
                            .foregroundStyle(GameColor.badPink)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        errorText.isEmpty ? Color.white.opacity(0.12) : GameColor.badPink.opacity(0.6),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption2)
                    .foregroundStyle(GameColor.badPink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            aliasString = existing?.name ?? ""
            valueString = existing?.value ?? ""
            oldAlias = existing?.name ?? ""
        }
        .onChange(of: focusedField) { _, newValue in
            // Commit when the whole row loses focus. The async re-check absorbs
            // the transient nil while focus moves name -> value within the row.
            guard newValue == nil else { return }
            DispatchQueue.main.async {
                if focusedField == nil { commit() }
            }
        }
    }

    /// Mirrors AutomatorDefineSingleEntry.handleFocus(false).
    private func commit() {
        validate { error in
            errorText = error
            if !error.isEmpty { return }

            if aliasString.isEmpty {
                if !oldAlias.isEmpty {
                    engine.deleteAutomatorConstant(oldAlias)
                    onChanged()
                }
            } else if oldAlias.isEmpty {
                engine.addAutomatorConstant(name: aliasString, value: valueString)
                onChanged()
            } else if oldAlias == aliasString {
                engine.modifyAutomatorConstant(name: aliasString, value: valueString)
                onChanged()
            } else {
                engine.renameAutomatorConstant(old: oldAlias, new: aliasString)
                onChanged()
            }
            oldAlias = aliasString
        }
    }

    private func validate(_ completion: @escaping (String) -> Void) {
        // An empty alias on an existing row is a delete request — always valid.
        if aliasString.isEmpty {
            completion("")
            return
        }
        engine.validateAutomatorConstant(name: aliasString, value: valueString, oldName: oldAlias, completion: completion)
    }

    private func deleteRow() {
        if !oldAlias.isEmpty {
            engine.deleteAutomatorConstant(oldAlias)
        }
        oldAlias = ""
        aliasString = ""
        valueString = ""
        errorText = ""
        onChanged()
    }
}
