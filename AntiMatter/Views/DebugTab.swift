//
//  DebugTab.swift
//  AntiMatter
//
//  Development debug controls — exposes the game's built-in `dev` commands
//  and game speed multiplier for testing.
//

import SwiftUI

struct DebugTab: View {
    let engine: GameEngine
    @State private var speedMultiplier: Double = 1
    @State private var antimatterExponent: String = "100"
    @State private var infinityExponent: String = "10"
    @State private var ipExponent: String = "10"
    @State private var eternitiesValue: String = "100"
    @State private var epExponent: String = "10"
    @State private var ttAmount: String = "100"
    @State private var tpExponent: String = "10"
    @State private var rmExponent: String = "10"
    @State private var relicShardsExponent: String = "15"
    @State private var showHardResetConfirm = false
    @State private var displayLinkFPS: Int = 15
    @State private var darkMatterExponent: String = "65"
    @State private var darkEnergyValue: String = "200"
    @State private var singularitiesValue: String = "100"
    @State private var imaginaryMachinesExponent: String = "12"
    @State private var showSpeedDialog = false



    private let speedOptions: [(label: String, value: Double)] = [
        ("1x", 1), ("5x", 5), ("10x", 10), ("100x", 100), ("200x", 200), ("1000x", 1000)
    ]

    var body: some View {
        List {
         //   performanceSection
            speedSection
            resourcesSection
            achievementsSection
            gameStateSection
            #if DEBUG
            laitelaSection
            tabNotificationsSection
            onboardingSection
            toastsSection
            jitBenchSection
            layoutDebugSection
            #endif
            dangerZoneSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Debug")
        .alert("Hard Reset", isPresented: $showHardResetConfirm) {
            Button("Reset", role: .destructive) {
                engine.devCommand("dev.hardReset()")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will completely reset your game save. Are you sure?")
        }
    }

    // MARK: - Performance Tuning

    private let displayLinkOptions = [10, 15, 20, 30]

    private var performanceSection: some View {
        Section("Performance") {
            // Thermal state (live)
            HStack {
                Text("Thermal State")
                Spacer()
                Text(engine.thermalStateDescription)
                    .foregroundStyle(thermalColor)
                    .fontWeight(.semibold)
            }

            HStack {
                Text("Simulation")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("30 Hz / 33ms (web default, locked)")
                    .font(.caption.monospacedDigit())
            }

            // Display link — controls how often Swift reads state for UI
            VStack(alignment: .leading, spacing: 6) {
                Text("Display: \(displayLinkFPS) Hz (CADisplayLink)")
                    .font(.caption.monospacedDigit())
                Picker("Display Hz", selection: $displayLinkFPS) {
                    ForEach(displayLinkOptions, id: \.self) { hz in
                        Text("\(hz)").tag(hz)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: displayLinkFPS) { _, hz in
                    engine.setDisplayLinkFPS(hz)
                }
            }

            Text("Simulation is locked to web default. Display refresh only affects how often Swift reads state — never touches game logic.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle("PERF + JS-PROF Logging", isOn: Binding(
                get: { engine._perfLoggingEnabled },
                set: { _ in engine.togglePerfLogging() }
            ))

            Text("Prints per-subsystem JS game loop breakdown to Xcode console every 5 seconds.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var thermalColor: Color {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  .green
        case .fair:     .yellow
        case .serious:  .orange
        case .critical: .red
        @unknown default: .gray
        }
    }

    // MARK: - Speed Control

    private var speedSection: some View {
        Section("Game Speed") {
            Button {
                showSpeedDialog = true
            } label: {
                HStack {
                    Text("Speed Multiplier")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(speedOptions.first(where: { $0.value == speedMultiplier })?.label ?? "\(speedMultiplier)x")
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "Speed Multiplier",
                isPresented: $showSpeedDialog,
                titleVisibility: .visible
            ) {
                ForEach(speedOptions, id: \.value) { option in
                    Button(option.label) {
                        speedMultiplier = option.value
                        engine.setDebugSpeed(option.value)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Resources

    private var resourcesSection: some View {
        Section("Resources") {
            HStack {
                Text("Set Antimatter to 1e")
                TextField("exponent", text: $antimatterExponent)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Set") {
                    engine.devCommand("Currency.antimatter.value = new Decimal(\"1e\(antimatterExponent)\")")
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Text("Set Infinities to 1e")
                TextField("exponent", text: $infinityExponent)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Set") {
                    engine.devCommand("Currency.infinities.value = new Decimal(\"1e\(infinityExponent)\")")
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Text("Set IP to 1e")
                TextField("exponent", text: $ipExponent)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Set") {
                    engine.devCommand("Currency.infinityPoints.value = new Decimal(\"1e\(ipExponent)\")")
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Text("Set Eternities to")
                TextField("amount", text: $eternitiesValue)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Set") {
                    engine.devCommand("Currency.eternities.value = new Decimal(\"\(eternitiesValue)\")")
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Text("Set EP to 1e")
                TextField("exponent", text: $epExponent)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Set") {
                    engine.devCommand("Currency.eternityPoints.value = new Decimal(\"1e\(epExponent)\")")
                }
                .buttonStyle(.bordered)
            }
            Button("Give 1 Eternity") {
                engine.devCommand("Currency.eternities.value = Currency.eternities.value.plus(1)")
            }
            Button("Give 1 EP") {
                engine.devCommand("Currency.eternityPoints.value = Currency.eternityPoints.value.plus(1)")
            }
            HStack {
                Text("Set TP to 1e")
                TextField("exponent", text: $tpExponent)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Set") {
                    engine.devCommand("Currency.tachyonParticles.value = new Decimal(\"1e\(tpExponent)\")")
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Text("Set RM to 1e")
                TextField("exponent", text: $rmExponent)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Set") {
                    engine.devCommand("Currency.realityMachines.value = new Decimal(\"1e\(rmExponent)\")")
                }
                .buttonStyle(.bordered)
            }
            Button("Give 10,000 Realities") {
                engine.devCommand("Currency.realities.add(10000)")
            }
            Button("Give 1 Perk Point") {
                engine.devCommand("Currency.perkPoints.add(1)")
            }
            Button("Max Perk Points") {
                engine.devCommand("Currency.perkPoints.value = 20000")
            }
            HStack {
                Text("Give Time Theorems")
                TextField("amount", text: $ttAmount)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Give") {
                    engine.devCommand("Currency.timeTheorems.add(new Decimal(\"\(ttAmount)\"))")
                }
                .buttonStyle(.bordered)
            }

            // Relic Shards (Effarig currency) — plain JS number, so no Decimal wrap needed.
            HStack {
                Text("Set Relic Shards to 1e")
                TextField("exponent", text: $relicShardsExponent)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Set") {
                    engine.devCommand("Currency.relicShards.value = 1e\(relicShardsExponent)")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Achievements

    private var achievementsSection: some View {
        Section("Achievements") {
            Button("Give All Achievements") {
                engine.devCommand("dev.giveAllAchievements()")
            }
            Button("Remove All Achievements") {
                engine.devCommand("dev.removeAch('all')")
            }
            .foregroundStyle(.orange)
        }
    }

    // MARK: - Game State Shortcuts

    private var gameStateSection: some View {
        Section("Game State") {
            Button("Load this save") {
                engine.importSave("""
                    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
                    """)
            }
            
            Button("Max All Dimensions") {
                engine.maxAll()
            }
            Button("Give 10 Dimension Boosts") {
                engine.devCommand("for (var i = 0; i < 10; i++) manualRequestDimensionBoost(false)")
            }
            Button("Give 10 Galaxies") {
                engine.devCommand("for (var i = 0; i < 10; i++) manualRequestGalaxyReset(false)")
            }
            Button("Fix Save") {
                engine.devCommand("dev.fixSave()")
            }
            Toggle("Fake 90-min offline gap on background", isOn: Binding(
                get: { engine.debugFakeOfflineGap },
                set: { engine.debugFakeOfflineGap = $0 }
            ))

            // Effarig quick-unlock helpers.
            Button("Unlock all Effarig shop upgrades") {
                engine.devCommand("EffarigUnlock.adjuster.unlock(); EffarigUnlock.glyphFilter.unlock(); EffarigUnlock.setSaves.unlock(); EffarigUnlock.run.unlock()")
            }
            Button("Complete all Effarig stages") {
                engine.devCommand("EffarigUnlock.infinity.unlock(); EffarigUnlock.eternity.unlock(); EffarigUnlock.reality.unlock()")
            }
            Button("Toggle V.isFlipped (Cursed Glyph button)") {
                engine.devCommand("V.isFlipped = !V.isFlipped")
            }
            // Laitela.isUnlocked = ImaginaryUpgrade(15).isBought. Set the bit
            // directly so the cheat doesn't require the upgrade's
            // prerequisites. Fires the bought event so any listeners update.
            Button("Unlock Lai'tela (buy ImaginaryUpgrade(15))") {
                engine.devCommand("player.reality.imaginaryUpgradeBits |= (1 << 15); EventHub.dispatch(GAME_EVENT.IMAGINARY_UPGRADE_BOUGHT)")
            }
            Button("Grant 1e12 Imaginary Machines") {
                engine.devCommand("Currency.imaginaryMachines.value = 1e12")
            }
        }
    }

    // MARK: - Lai'tela / Alchemy cheats

    #if DEBUG
    private var laitelaSection: some View {
        Section("Lai'tela / Alchemy") {
            HStack {
                Text("Set Dark Matter to 1e")
                TextField("exponent", text: $darkMatterExponent)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Set") {
                    let v = pow(10.0, Double(darkMatterExponent) ?? 0)
                    engine.devSetDarkMatter(v)
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Text("Set Dark Energy to")
                TextField("value", text: $darkEnergyValue)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Set") {
                    engine.devSetDarkEnergy(Double(darkEnergyValue) ?? 0)
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Text("Set Singularities to")
                TextField("value", text: $singularitiesValue)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Set") {
                    engine.devSetSingularities(Double(singularitiesValue) ?? 0)
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Text("Set iM to 1e")
                TextField("exponent", text: $imaginaryMachinesExponent)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Set") {
                    let v = pow(10.0, Double(imaginaryMachinesExponent) ?? 0)
                    engine.devSetImaginaryMachines(v)
                }
                .buttonStyle(.bordered)
            }
            Button("+1 Lai'tela tier (destabilise)") {
                engine.devCompleteLaitelaTier()
            }
            Button("Grant 100 Singularities") {
                engine.devGrantSingularities(100)
            }
            Button("Grant 1e6 Singularities") {
                engine.devGrantSingularities(1e6)
            }
            Button("Max All Alchemy") {
                engine.devMaxAllAlchemy()
            }
            .tint(.orange)
        }
    }
    #endif

    // MARK: - Tab Notification Badges (audit harness)

    #if DEBUG
    private var tabNotificationsSection: some View {
        Section("Tab Notification Badges") {
            Text("Adds keys directly to player.tabNotifications. Verify badge appears on the named parent tab, then navigate to the subtab to confirm it clears.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Trigger: Black Hole (Reality)") {
                engine.devTriggerBadge(keys: ["realityhole"])
            }
            Button("Trigger: Automator (Automation)") {
                engine.devTriggerBadge(keys: ["automationautomator"])
            }
            Button("Trigger: Teresa (Celestials × 2)") {
                engine.devTriggerBadge(keys: ["celestialscelestial-navigation", "celestialsteresa"])
            }
            Button("Trigger: Alchemy (Reality × 2)") {
                engine.devTriggerBadge(keys: ["realityglyphs", "realityalchemy"])
            }
            Button("Trigger: Imag Upgrades (Reality)") {
                engine.devTriggerBadge(keys: ["realityimag_upgrades"])
            }
            Button("Trigger: Lai'tela (Celestials)") {
                engine.devTriggerBadge(keys: ["celestialslaitela"])
            }
            Button("Trigger: Pelle (Celestials)") {
                engine.devTriggerBadge(keys: ["celestialspelle"])
            }
            Button("Trigger: New Glyph Cosmetic (Reality)") {
                engine.devTriggerBadge(keys: ["realityglyphs"])
            }
            Button("Clear all badges") {
                engine.devClearAllBadges()
            }
            .foregroundStyle(.orange)
        }
    }
    #endif

    // MARK: - Onboarding (new-player flow)

    #if DEBUG
    private var onboardingSection: some View {
        Section("Onboarding") {
            Text("Re-arms the new-player welcome flow. Clears the persistent 'seen' flag and shows the welcome modal now, bypassing the fresh-save check.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Show onboarding now") {
                engine.devReArmOnboarding()
            }
            Button("Clear 'seen' flag only") {
                UserDefaults.standard.removeObject(forKey: "am_hasSeenOnboarding")
            }
            .foregroundStyle(.orange)
        }
    }
    #endif

    // MARK: - Toasts (visual harness)

    #if DEBUG
    private var toastsSection: some View {
        Section("Toasts") {
            Text("Fires each toast type so you can verify color, layout, line count, and dismiss timing against the current screen state. The long `modalMessage` button is the C55 \"Big Crunch in under a minute\" message verbatim — useful for verifying the length-scaled auto-dismiss.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Toast: success (yellow)") {
                engine.enqueueToast(type: "success", text: "Achievement: Faster than a squared potato")
            }
            Button("Toast: info (blue)") {
                engine.enqueueToast(type: "info", text: "Preset 1 saved")
            }
            Button("Toast: error (red)") {
                engine.enqueueToast(type: "error", text: "Could not import save (invalid format)")
            }
            Button("Toast: infinity (orange)") {
                engine.enqueueToast(type: "infinity", text: "You broke Infinity!")
            }
            Button("Toast: eternity (purple)") {
                engine.enqueueToast(type: "eternity", text: "First Eternity reached")
            }
            Button("Toast: reality (green)") {
                engine.enqueueToast(type: "reality", text: "Reality complete \u{2014} 3 Reality Machines gained")
            }
            Button("Modal: short (~6s)") {
                engine.enqueueModalMessage(text: "Short modal message.")
            }
            Button("Modal: long (C55, ~17s, tap to dismiss)") {
                engine.enqueueModalMessage(text: """
                    Since you performed an Infinity in under a minute, the UI changed on the screen. \
                    Instead of the Dimensions disappearing, they stay and the Big Crunch button appears on top of them. \
                    This is purely visual, and is there to prevent flickering.
                    """)
            }
            Button("Modal: very long (clamped to 20s)") {
                engine.enqueueModalMessage(text: String(repeating: "Lorem ipsum dolor sit amet. ", count: 30))
            }
        }
    }
    #endif

    // MARK: - JIT Microbench

    #if DEBUG
    private var jitBenchSection: some View {
        Section("JIT Microbench") {
            Text("Compares Decimal arithmetic in JSContext (no JIT on iOS apps) against a hidden WKWebView (JIT in WebContent process). Decision criteria: ≥3× → green-light WebView offline-sim plan, <2× → abandon.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                Task { @MainActor in
                    await engine.runJITBench()
                }
            } label: {
                HStack {
                    Text(engine.jitBenchRunning ? "Running…" : "Run JIT Bench (1M iters)")
                    if engine.jitBenchRunning {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(engine.jitBenchRunning)

            if let r = engine.lastJITBenchResult {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "JSContext: %.0f ms", r.jsContextMs))
                        .font(.caption.monospacedDigit())
                    if let err = r.webViewError {
                        Text("WKWebView: \(err)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.red)
                    } else {
                        Text(String(format: "WKWebView: %.0f ms", r.webViewMs))
                            .font(.caption.monospacedDigit())
                        Text(String(format: "Speedup: %.2f×", r.speedup))
                            .font(.caption.monospacedDigit())
                            .fontWeight(.semibold)
                    }
                    Text(r.verdict)
                        .font(.caption2)
                        .foregroundStyle(verdictColor(for: r))
                    if !r.checksumsMatch && r.webViewError == nil {
                        Text("⚠️ Checksums differ between contexts — result is invalid")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "offlineSimUseWebView") },
                set: { UserDefaults.standard.set($0, forKey: "offlineSimUseWebView") }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use WebView for offline sim")
                    Text("Routes runOfflineSimulation through a hidden WKWebView (which has JIT) for sims with elapsed ≥ 50s. Falls back to JSContext on any failure.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "offlineSimDebugProfiler") },
                set: { UserDefaults.standard.set($0, forKey: "offlineSimDebugProfiler") }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WebView profiler logging")
                    Text("Installs subsystem probes inside the WebView's gameLoop and emits per-batch ms breakdowns to the debug log. Wrapper overhead measurable on hot paths — leave off unless diagnosing.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "gameDecimalUseCAPI") },
                set: { setGameDecimalUseCAPI($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GameDecimal C-API fast path")
                    Text("Reads break_infinity Decimal mantissa/exponent via JSObjectGetProperty + JSValueToNumber, skipping the per-property ObjC JSValue wrapper. Debug builds run both paths and log any divergence (throttled 1/s). Expected ~50% reduction in GameDecimal.init CPU.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "decimalDivergenceHarnessEnabled") },
                set: { UserDefaults.standard.set($0, forKey: "decimalDivergenceHarnessEnabled") }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Decimal divergence harness")
                    Text("Wraps every patched Decimal.prototype method (cmp/lt/gt/add/sub/div/mul/pow/max/min/sqrt/recip/sqr/abs/neg/clamp/timesEffectsOf + statics) so 1-in-50 calls also runs the original and logs any mismatch via _nativeLog. Catches latent perf-patch regressions like the 2026-05 glyph-mult miss. Takes effect on next app launch. Log budget: 200 entries per session.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("Stage-5 divergence test: runs the same save+elapsed through JSContext and WebView, compares post-sim saves byte-for-byte and key fields. Restores user state in between. Confirms (or refutes) that both paths produce equivalent game state — gates trust in WebView-default with cloud-sync's hash-based conflict detection.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                Task { @MainActor in
                    await engine.runDivergenceTest(elapsedSeconds: 0.5)
                }
            } label: {
                Text(engine.divergenceRunning ? "Running…" : "Divergence: 10 ticks (0.5s sim)")
            }
            .disabled(engine.divergenceRunning)

            Button {
                Task { @MainActor in
                    await engine.runDivergenceTest(elapsedSeconds: 60)
                }
            } label: {
                HStack {
                    Text(engine.divergenceRunning ? "Running divergence…" : "Divergence: 1200 ticks (60s sim)")
                    if engine.divergenceRunning {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(engine.divergenceRunning)

            if let status = engine.lastDivergenceStatus {
                Text(status)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(
                        status.contains("BYTE-IDENTICAL") ? .green :
                        status.contains("DIVERGE") ? .orange :
                        status.contains("failed") ? .red : .primary
                    )
            }
        }
    }

    private func verdictColor(for r: JITBenchResult) -> Color {
        if r.webViewError != nil || !r.checksumsMatch { return .red }
        let s = r.speedup
        if s >= 3.0 { return .green }
        if s >= 2.0 { return .orange }
        return .secondary
    }
    #endif

    // MARK: - Layout Debug

    #if DEBUG
    /// Layout-calibration toggles. Currently houses the compact-header
    /// height overlay — enable it to plot the formula output, the debounced
    /// frame size, the measured content height, and any pending shrink
    /// countdown. See the design notes → "Compact header sizing invariants".
    private var layoutDebugSection: some View {
        Section("Layout Debug") {
            Toggle("Show compact header height overlay", isOn: Binding(
                get: { engine.showCompactHeaderHeightOverlay },
                set: { engine.showCompactHeaderHeightOverlay = $0 }
            ))

            Text("Plots Reserved (formula) / Stable (debounced frame) / Actual (rendered VStack) / Δ / shrink countdown on the iPhone header. Δ should stay in [0, 1] at every state; anything higher means the constants table in CompactHeaderView.swift drifted from the actual leaf heights.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    #endif

    // MARK: - Danger Zone

    @Environment(\.sidebarState) private var sidebar

    private var dangerZoneSection: some View {
        Section("Danger Zone") {
            Button("Hard Reset") {
                showHardResetConfirm = true
            }
            .foregroundStyle(.red)
            .onLongPressGesture(minimumDuration: 0.5) {
                if let sidebar { engine.hardReset(sidebarState: sidebar) }
            }
        }
    }
}
