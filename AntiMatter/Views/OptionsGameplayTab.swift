//
//  OptionsGameplayTab.swift
//  AntiMatter
//
//  Mirrors web `OptionsGameplayTab.vue` (Options → Gameplay subtab).
//  Excludes Hotkeys (no hardware keyboard on iOS) and "Run suspended time
//  as offline" (`hibernationCatchup` is force-cleared at every save load).
//

import SwiftUI

struct OptionsGameplayTab: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics

    /// Slider state for offline ticks. Seeded from `engine.offlineTicksValue`
    /// in `.onAppear` and refreshed when the underlying value changes (slot
    /// switches, imports). Web's mantissa-linear formula on values 22…54
    /// produces 500 / 600 / … / 900 / 1000 / 2000 / … / 1e6 ticks.
    @State private var offlineSlider: Double = 28

    /// Visible Tabs sheet presentation. Web's "Modify Visible Tabs" lives
    /// under Options → Gameplay; iOS surfaces the same entry here.
    @State private var showVisibleTabsSheet: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Gameplay")
                    .font(.headline)

                // 1) Switch tabs on game events ------------------------------
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { engine.automaticTabSwitching },
                        set: { engine.setAutomaticTabSwitching($0) }
                    )) {
                        Text("Switch tabs on game events")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(GameColor.good)

                    Text("When off, entering or exiting a challenge won't jump you to the Antimatter Dimensions tab.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // 2) Offline progress ---------------------------------------
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { engine.offlineProgressEnabledOption },
                        set: { engine.setOfflineProgressEnabled($0) }
                    )) {
                        Text("Offline progress")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(GameColor.good)

                    Text("When off, time spent away from the app does not advance the simulation. Default: on.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // 3) Offline ticks slider -----------------------------------
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Offline ticks: \(engine.offlineTicksValue.formatted())")
                            .font(.subheadline.weight(.medium).monospacedDigit())
                        Spacer()
                    }

                    Slider(value: $offlineSlider, in: 22...54, step: 1)
                        .tint(GameColor.good)
                        .onChange(of: offlineSlider) { _, newValue in
                            engine.setOfflineTicks(fromSlider: Int(newValue))
                        }

                    Text("Maximum simulation ticks used to catch up offline progress. Higher = more accurate, slower to complete. Use Speed up or Skip in the progress bar to finish a long catch-up early.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // 4) Glyph effect text colors -------------------------------
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { engine.glyphTextColorsOption },
                        set: { engine.setGlyphTextColors($0) }
                    )) {
                        Text("Color glyph effect text")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(GameColor.good)

                    Text("When on, active glyph effects and sacrifice totals are tinted in their glyph type's color with a soft halo. Default: on.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // 5) Button haptic feedback --------------------------------
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: Haptics.userDefaultsKey) },
                        set: { UserDefaults.standard.set($0, forKey: Haptics.userDefaultsKey) }
                    )) {
                        Text("Button haptics")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(GameColor.good)

                    Text("Gentle vibration on button taps. iPhone only — silently no-ops on iPad. Default: on.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // 6) Altered Glyphs detail visibility (post-Ra unlock) -------
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { !engine.hideAlterationOption },
                        set: { engine.setAlteredGlyphDetailsShown($0) }
                    )) {
                        Text("Show altered glyph details")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(GameColor.good)

                    Text("Show the addition/empower/boost sacrifice thresholds on the Glyphs tab. Only meaningful after unlocking Altered Glyphs (Ra). Default: on.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // 7) Automator log max (post-AP unlock) ---------------------
                if engine.gameState.automatorState.isUnlocked {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Automator Log Max: \(engine.automatorLogMaxEntries)")
                                .font(.subheadline.weight(.medium).monospacedDigit())
                            Spacer()
                        }

                        Slider(
                            value: Binding(
                                get: { Double(engine.automatorLogMaxEntries) },
                                set: { engine.setAutomatorLogMaxEntries(Int($0)) }
                            ),
                            in: 50...500,
                            step: 50
                        )
                        .tint(GameColor.good)

                        Text("Maximum number of automator log entries kept in memory.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // 8) Glyph selection prompt on Reality (post-Reality unlock) --
                // Web parity: `player.options.confirmations.glyphSelection`. When
                // off, manual Reality auto-picks a glyph (Effarig filter / random)
                // instead of showing the selection sheet.
                if engine.realityUnlocked {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: Binding(
                            get: { engine.glyphSelectionConfirmation },
                            set: { engine.setGlyphSelectionConfirmation($0) }
                        )) {
                            Text("Glyph selection prompt on Reality")
                                .font(.subheadline.weight(.medium))
                        }
                        .tint(GameColor.good)

                        Text("When on, making a new Reality asks you to choose a Glyph. When off, a Glyph is chosen automatically (using your Effarig filter, or at random). Default: on.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 4)

            // Modify Visible Tabs ----------------------------------------
            // Web parity: lives under Gameplay options. Lets the user
            // hide tabs/subtabs they don't actively use; state stored in
            // `player.options.hiddenTabBits` + `hiddenSubtabBits` (round-
            // trips with web saves).
            VStack(alignment: .leading, spacing: 8) {
                GameButton(borderColor: .white.opacity(0.4)) {
                    showVisibleTabsSheet = true
                } label: {
                    Text("Modify Visible Tabs")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }

                Text("Hide tabs and subtabs you don't need from the sidebar. The Options tab is always visible.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.bottom)
        }
        .sheet(isPresented: $showVisibleTabsSheet) {
            VisibleTabsSheet(engine: engine)
        }
        .onAppear {
            offlineSlider = Double(GameEngine.offlineSliderValue(forTicks: engine.offlineTicksValue))
        }
        .onChange(of: engine.offlineTicksValue) { _, newTicks in
            let target = Double(GameEngine.offlineSliderValue(forTicks: newTicks))
            if abs(offlineSlider - target) > 0.5 { offlineSlider = target }
        }
    }
}
