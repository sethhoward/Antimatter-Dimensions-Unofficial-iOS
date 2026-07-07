//
//  OptionsTab.swift
//  AntiMatter
//

import SwiftUI

struct OptionsTab: View {
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebarState
    @Environment(\.layoutMetrics) private var metrics
    @State private var showImportConfirm = false
    @State private var clipboardSave: String = ""
    @State private var showResetWarning = false
    @State private var showResetConfirm = false
    @State private var resetPhrase: String = ""
    @State private var showCredits = false
    @State private var showNotationDialog = false
    @State private var showSpeedrunStartModal = false
    @State private var showKeyboardShortcuts = false
    @State private var showSTDStore = false

    /// Persisted UI refresh rate (CADisplayLink Hz). Default 30 Hz both platforms.
    /// Key "_v2" resets anyone on the old 15 Hz iPhone default to 30 Hz.
    @AppStorage("uiRefreshRate_v2") private var uiRefreshRate: Int = 0 // 0 = use default (30 Hz)
    @State private var updateRateMs: Double = 33

    private static let requiredPhrase = "Shrek is love, Shrek is life"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // MARK: - Support
                supportSection

                // MARK: - Display
                displaySection

                // MARK: - Save Slots (multi-save)
                SaveSlotsSection(engine: engine)

                // MARK: - iCloud Sync
                CloudSyncSection(engine: engine)

                // MARK: - Save Management
                VStack(spacing: 10) {
                    Text("Save Management")
                        .font(.headline)

                    GameButton(borderColor: .green) {
                        engine.save()
                        engine.enqueueToast(type: "info", text: "Game saved")
                    } label: {
                        Text("Save Game")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }

                    GameButton(borderColor: .green) {
                        engine.exportSave()
                    } label: {
                        Text("Export Save to Clipboard")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }

                    GameButton(borderColor: .green) {
                        let text = UIPasteboard.general.string ?? ""
                        if text.isEmpty {
                            engine.enqueueToast(type: "error", text: "Clipboard is empty")
                        } else {
                            clipboardSave = text
                            showImportConfirm = true
                        }
                    } label: {
                        Text("Import Save from Clipboard")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

                // MARK: - Speedrun (post-completion only)
                // Web parity: visible once `player.records.fullGameCompletions > 0`.
                // The label varies with current state — active speedrun shows
                // "Restart Speedrun"; otherwise "Start a Speedrun Save".
                if engine.speedrunQuick.canShowOptionsEntry {
                    speedrunSection
                }

                // MARK: - Keyboard Shortcuts
                VStack(spacing: 10) {
                    GameButton(borderColor: .white.opacity(0.4)) {
                        showKeyboardShortcuts = true
                    } label: {
                        Text("Keyboard Shortcuts")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

                // MARK: - Credits
                VStack(spacing: 10) {
                    GameButton(borderColor: .white.opacity(0.4)) {
                        showCredits = true
                    } label: {
                        Text("Credits & Licenses")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }

                    // SecretAchievement(33) "A sound financial decision".
                    // Web's STDStore is gated on cloud login + IAP infra
                    // (`ShopTab.vue:67-72`); iOS doesn't port any of that
                    // — and can't surface anything that reads as a purchase
                    // affordance per App Store policy. Button + alert copy
                    // is rewritten to read as an explicit joke / easter
                    // egg, not a store. iOS divergence from web copy.
                    GameButton(borderColor: .white.opacity(0.4)) {
                        engine.devCommand("SecretAchievement(33).unlock();")
                        showSTDStore = true
                    } label: {
                        Text("STD Store")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

                // MARK: - Game Settings
                gameSettingsSection

                // MARK: - Danger Zone
                VStack(spacing: 10) {
                    Text("Danger Zone")
                        .font(.headline)
                        .foregroundStyle(GameColor.antimatter)

                    GameButton(borderColor: GameColor.antimatter) {
                        showResetWarning = true
                    } label: {
                        Text("Hard Reset")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }

                    Text("Completely wipe your save and start over.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(GameColor.antimatter.opacity(0.3), lineWidth: 1)
                )

                PhoneTabBarSpacer()
            }
            .padding()
        }
        .alert("Import Save", isPresented: $showImportConfirm) {
            Button("Import", role: .destructive) {
                engine.importSave(clipboardSave)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will overwrite your current save. Are you sure?")
        }
        .alert("Hard Reset", isPresented: $showResetWarning) {
            Button("Continue", role: .destructive) {
                resetPhrase = ""
                showResetConfirm = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will completely wipe your save. All progress will be lost forever. Are you sure you want to continue?")
        }
        .onAppear {
            // Set device-appropriate default on first launch (0 = never set)
            if uiRefreshRate == 0 {
                uiRefreshRate = 30
            }
            engine.setDisplayLinkFPS(uiRefreshRate)
            engine.readUpdateRate { ms in
                updateRateMs = Double(ms)
            }
        }
        .sheet(isPresented: $showCredits) {
            CreditsSheet()
        }
        .sheet(isPresented: $showKeyboardShortcuts) {
            KeyboardShortcutsSheet(engine: engine)
        }
        .alert("STD Store", isPresented: $showSTDStore) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing here. The web version has a joke STD coin store; the iOS port doesn't. You did, however, just find a Secret Achievement.")
        }
        .alert("Confirm Hard Reset", isPresented: $showResetConfirm) {
            TextField("Type the phrase to confirm", text: $resetPhrase)
            Button("Hard Reset", role: .destructive) {
                if resetPhrase == Self.requiredPhrase, let sidebar = sidebarState {
                    engine.hardReset(sidebarState: sidebar)
                } else if resetPhrase != Self.requiredPhrase {
                    engine.enqueueToast(type: "error", text: "Incorrect phrase — reset cancelled")
                }
            }
            Button("Cancel", role: .cancel) {
                // Web `HardResetModal.vue` destroyed() hook: if the phrase
                // matched but the modal closed without confirming, fire
                // SecretAchievement(38) "Knife's edge".
                if resetPhrase == Self.requiredPhrase {
                    engine.devCommand("SecretAchievement(38).unlock();")
                }
            }
        } message: {
            Text("Type \"\(Self.requiredPhrase)\" to confirm. This is irreversible.")
        }
    }

    // MARK: - Speedrun

    /// Visible only when `player.records.fullGameCompletions > 0` (web's
    /// gate, polled into `engine.speedrunQuick.canShowOptionsEntry`).
    /// Opens the shared `SpeedrunStartModal` in `.speedrunOnly` mode — the
    /// "Fresh Save" radio is hidden here because the Options route is
    /// specifically the speedrun entry point; players wanting a non-
    /// speedrun fresh save use the Hard Reset button below.
    private var speedrunSection: some View {
        let active = engine.speedrunQuick.isActive
        let title = active ? "Restart Speedrun Save" : "Start a Speedrun Save"
        return VStack(spacing: 10) {
            Text("Speedrun Mode")
                .font(.headline)
            if active {
                let name = engine.speedrunQuick.name
                if !name.isEmpty {
                    Text("Current run: \(name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Start a new save with milestone tracking and stripped confirmations. Hard-resets your current progress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            GameButton(borderColor: GameColor.eternity) {
                showSpeedrunStartModal = true
            } label: {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .sheet(isPresented: $showSpeedrunStartModal) {
            // Re-inject `.sidebarState` so the modal's post-confirm tab
            // navigation lands on the real `SidebarState` — SwiftUI does
            // NOT propagate custom env keys across `.sheet` boundaries.
            // Without this, `selectSubtab` writes to a phantom object and
            // the app's tab stays on Options.
            SpeedrunStartModal(engine: engine, mode: .speedrunOnly)
                .environment(\.sidebarState, sidebarState)
        }
    }

    // MARK: - Support

    private var supportSection: some View {
        VStack(spacing: 10) {
            // Reads from Info.plist — never hardcoded so the displayed
            // value tracks the bundle's CFBundleShortVersionString (and
            // CFBundleVersion build number) automatically.
            if !Self.appVersionDisplay.isEmpty {
                Text(Self.appVersionDisplay)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GameButton(borderColor: .blue) {
                if let url = URL(string: "https://github.com/sethhoward/Infinity-Dimensions") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                    Text("Support & Feedback")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    /// `Version X.Y.Z` pulled from Info.plist's CFBundleShortVersionString.
    /// Empty when the key is missing (defensive — shouldn't happen in
    /// practice).
    private static let appVersionDisplay: String = {
        let short = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        return short.isEmpty ? "" : "Version \(short)"
    }()

    // MARK: - Game Settings (matches web Options)

    private var gameSettingsSection: some View {
        VStack(spacing: 10) {
            Text("Game Settings")
                .font(.headline)

            VStack(spacing: 6) {
                HStack {
                    Text("Update rate: \(Int(updateRateMs)) ms")
                        .font(.subheadline.weight(.medium).monospacedDigit())
                    Spacer()
                }

                Slider(value: $updateRateMs, in: 33...200, step: 1)
                    .tint(GameColor.good)
                    .onChange(of: updateRateMs) { _, ms in
                        engine.setUpdateRate(Int(ms))
                    }

                Text("Controls how often the game simulation updates. Lower values are smoother but use more battery. Default is 33 ms.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Display / Performance

    private var displaySection: some View {
        VStack(spacing: 10) {
            Text("Display")
                .font(.headline)

            Toggle(isOn: Binding(
                get: { engine.newsEnabled },
                set: { _ in engine.toggleNewsEnabled() }
            )) {
                Text("News Ticker")
                    .font(.subheadline.weight(.medium))
            }
            .tint(GameColor.good)

            Text("Controls how often the screen refreshes. Lower values use less battery and produce less heat. The game runs at full speed regardless — only the display refresh changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Picker("Refresh Rate", selection: $uiRefreshRate) {
                Text("10 Hz").tag(10)
                Text("15 Hz").tag(15)
                Text("20 Hz").tag(20)
                Text("30 Hz").tag(30)
            }
            .pickerStyle(.segmented)
            .onChange(of: uiRefreshRate) { _, hz in
                engine.setDisplayLinkFPS(hz)
            }

            HStack(spacing: 4) {
                Image(systemName: refreshRateIcon)
                    .foregroundStyle(refreshRateColor)
                Text(refreshRateDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.vertical, 4)

            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "dynamicThrottling") },
                set: { engine.setDynamicThrottling($0) }
            )) {
                Text("Dynamic Throttling")
                    .font(.subheadline.weight(.medium))
            }
            .tint(GameColor.good)

            Text("Automatically reduces the display refresh rate after a period of inactivity. The game continues running at full speed — only visual updates slow down. Helps reduce heat and save battery during idle play.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 4)

            Text("Notation")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showNotationDialog = true
            } label: {
                HStack {
                    Text(GameNotation(rawValue: engine.notationName)?.rawValue ?? engine.notationName)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "Notation",
                isPresented: $showNotationDialog,
                titleVisibility: .visible
            ) {
                ForEach(GameNotation.allCases, id: \.self) { n in
                    Button(n.rawValue) { engine.setNotation(n.rawValue) }
                }
                Button("Cancel", role: .cancel) {}
            }

            Text("How large numbers are displayed. Only the notations ported to iOS are listed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var refreshRateIcon: String {
        switch uiRefreshRate {
        case 10: "leaf.fill"
        case 15: "leaf.fill"
        case 20: "gauge.with.dots.needle.33percent"
        default: "gauge.with.dots.needle.67percent"
        }
    }

    private var refreshRateColor: Color {
        switch uiRefreshRate {
        case 10: .green
        case 15: .green
        case 20: .yellow
        default: .orange
        }
    }

    private var refreshRateDescription: String {
        switch uiRefreshRate {
        case 10: "Maximum battery savings — lightest on your device"
        case 15: "Great battery life — recommended for most players"
        case 20: "Balanced — smoother updates with moderate battery use"
        default: "Smoothest — highest refresh rate, uses more battery"
        }
    }
}

// MARK: - Credits Sheet

private struct CreditsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Dedication
                    VStack(spacing: 8) {
                        Text("Dedicated to")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Atolite")
                            .font(.title.weight(.bold))
                            .foregroundStyle(GameColor.antimatter)
                    }
                    .padding(.top, 8)

                    Divider()

                    // MIT License
                    VStack(alignment: .leading, spacing: 8) {
                        Text("License")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text("MIT License")
                            .font(.subheadline.weight(.semibold))

                        Text("Copyright (c) 2017 IvarK")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("""
                        Permission is hereby granted, free of charge, to any person obtaining a copy \
                        of this software and associated documentation files (the "Software"), to deal \
                        in the Software without restriction, including without limitation the rights \
                        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
                        copies of the Software, and to permit persons to whom the Software is \
                        furnished to do so, subject to the following conditions:

                        The above copyright notice and this permission notice shall be included in \
                        all copies or substantial portions of the Software.

                        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
                        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
                        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
                        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
                        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
                        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
                        SOFTWARE.
                        """)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(GameColor.baseBackground)
            .adaptiveSheetTitle("Credits")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

}
