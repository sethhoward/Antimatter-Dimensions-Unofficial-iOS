//
//  GameEngine+Celestials.swift
//  AntiMatter
//
//  Celestials poll functions + Teresa/quote actions. Runs on jsQueue and
//  communicates via the celestial-helpers.js bridge (loaded in
//  setupCelestialHelpers, called from finishStartup / importSave / hardReset).
//

import JavaScriptCore
import Foundation
import UIKit

extension GameEngine {

    // MARK: - JS helpers injection

    /// Injects _nativeNavigationState / _nativeTeresaState / _nativeQuoteState and
    /// related action wrappers from celestial-helpers.js. Must run on jsQueue
    /// after cacheJSRefs(), before pollDirect() runs.
    func setupCelestialHelpers() {
        guard let url = Bundle.main.url(forResource: "celestial-helpers", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("🔴 GameEngine: missing celestial-helpers.js in app bundle")
            return
        }
        _ = context.evaluateScript(source)
        // Pull canonical Pelle disabled-item registries once. The lists are
        // static literals on the JS side (see `pelle.js:184-204`); no need to
        // re-poll. Same lifecycle as helper setup — runs again on
        // importSave/hardReset/slot-switch/backup-restore.
        loadPelleDisabledListsSync()
    }

    /// Synchronously loads `_nativePelleDisabledLists()` JSON, parses the 5
    /// canonical arrays, and dispatches to main for @Observable commit.
    /// Must be called on jsQueue (e.g. inside `setupCelestialHelpers`).
    /// Failure mode: empty sets — consumers gate on `pelleDoomed && set.contains`,
    /// so empty sets simply mean no items are flagged (graceful no-op rather
    /// than incorrect strikethroughs).
    private func loadPelleDisabledListsSync() {
        let json = context.evaluateScript("_nativePelleDisabledLists()")?.toString() ?? ""
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        // JSONSerialization returns `[NSNumber]` for number arrays. The
        // direct `as? [Int]` cast is unreliable across runtime versions —
        // sometimes it bridges, sometimes it returns nil, leaving the Sets
        // empty and breaking every doom strikethrough downstream. Map
        // explicitly through NSNumber.intValue so the conversion is total.
        func intSet(_ key: String) -> Set<Int> {
            if let nums = obj[key] as? [NSNumber] { return Set(nums.map { $0.intValue }) }
            if let ints = obj[key] as? [Int] { return Set(ints) }
            return []
        }
        let perks = intSet("uselessPerks")
        let studies = intSet("uselessTimeStudies")
        let rupgs = intSet("disabledRUPGs")
        let achs = intSet("disabledAchievements")
        let infs = Set((obj["uselessInfinityUpgrades"] as? [String]) ?? [])
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pelleUselessPerks = perks
            self.pelleUselessTimeStudies = studies
            self.pelleDisabledRUPGs = rupgs
            self.pelleDisabledAchievements = achs
            self.pelleUselessInfinityUpgrades = infs
        }
    }

    /// Injects the GameEnd helpers (`_nativeGameEndState`, `_nativeGameEndSpectate`,
    /// etc.) from `game-end-helpers.js`. Idempotent. Same lifecycle as
    /// `setupCelestialHelpers` — call from `finishStartup` / `importSave`
    /// / `hardReset` / slot-switch / backup-restore.
    func setupGameEndHelpers() {
        guard let url = Bundle.main.url(forResource: "game-end-helpers", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("🔴 GameEngine: missing game-end-helpers.js in app bundle")
            return
        }
        _ = context.evaluateScript(source)
    }

    // MARK: - GameEnd actions

    /// Triggers Spectate Mode. The web's `removeAdditionalEnd = true` flips
    /// off the natural endState progression and starts decreasing
    /// `additionalEnd` over time, eventually unlocking the full game again.
    func gameEndSpectate() {
        jsAsync("_nativeGameEndSpectate()")
    }

    /// Closes the credits overlay (sets `GameEnd.creditsClosed = true`).
    /// Survives across visits to the finale.
    func gameEndCloseCredits() {
        jsAsync("_nativeGameEndCloseCredits()")
    }

    /// Loads the full GameEnd state for the credits overlay (button visibility,
    /// spectate flag, etc.). Async — invokes `completion` on the main thread.
    func loadGameEndState(completion: @escaping (GameEndState?) -> Void) {
        jsQueue.async { [weak self] in
            autoreleasepool {
                guard let self else { DispatchQueue.main.async { completion(nil) }; return }
                let json = self.context.evaluateScript("_nativeGameEndState()")?.toString() ?? ""
                guard let data = json.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                let state = GameEndState(
                    ready: (obj["ready"] as? Bool) ?? false,
                    endState: (obj["endState"] as? Double) ?? 0,
                    creditsClosed: (obj["creditsClosed"] as? Bool) ?? false,
                    removeAdditionalEnd: (obj["removeAdditionalEnd"] as? Bool) ?? false,
                    canShowNewGame: (obj["canShowNewGame"] as? Bool) ?? false,
                    canSpectate: (obj["canSpectate"] as? Bool) ?? false
                )
                DispatchQueue.main.async { completion(state) }
            }
        }
    }

    #if DEBUG
    /// DEBUG-only: jump endState to a target marker (e.g. CREDITS_START = 4.5).
    /// Lets us walk through finale phases without grinding antimatter.
    func devGameEndJumpTo(_ target: Double) {
        jsAsync("_nativeGameEndJumpTo(\(target))")
    }
    func devGameEndReset() {
        jsAsync("_nativeGameEndReset()")
    }
    #endif

    // MARK: - Actions (main-thread entry points; dispatch to jsQueue)

    /// Continuous hold-to-pour — call each frame while user holds the button.
    /// `diffSec` is the elapsed seconds since the previous call.
    func pourRM(diffSec: Double) {
        let clamped = max(0, min(diffSec, 1.0))
        jsAsync("_nativeTeresaPour(\(clamped))")
    }

    /// Called on touch release / cancel — resets Teresa.timePoured so the
    /// quadratic acceleration restarts from 0 next press.
    func stopPourRM() {
        jsAsync("_nativeTeresaStopPour()")
    }

    /// Buy a Perk Shop upgrade by its numeric id (0..5).
    func buyPerkShopUpgrade(id: Int) {
        jsAsync("_nativeBuyPerkShop(\(id))")
    }

    /// Start Teresa's Reality. Shows confirmation modal unless the user
    /// has disabled it via the "Don't show again" toggle.
    func requestTeresaRun() {
        if pelleDoomed { return }
        jsQueue.async { [weak self] in
            guard let self else { return }
            let confirmKey = "teresa"
            let shouldConfirm = self.confirmationEnabled(confirmKey)
            if shouldConfirm {
                DispatchQueue.main.async { self.pendingModal = .teresaRun }
            } else {
                _ = self.context.evaluateScript("_nativeStartTeresaRun()")
            }
        }
    }

    /// Called from PrestigeConfirmation when user confirms teresaRun.
    func performTeresaRun() {
        jsAsync("_nativeStartTeresaRun()")
    }

    // MARK: - Effarig actions

    /// Request-to-start wrapper: shows the PrestigeModal.effarigRun sheet unless
    /// the user disabled confirmations. Pattern mirrors requestTeresaRun.
    func requestEffarigRun() {
        if pelleDoomed { return }
        jsQueue.async { [weak self] in
            guard let self else { return }
            let shouldConfirm = self.confirmationEnabled("effarig")
            if shouldConfirm {
                DispatchQueue.main.async { self.pendingModal = .effarigRun }
            } else {
                _ = self.context.evaluateScript("_nativeStartEffarigRun()")
            }
        }
    }

    /// Purchase an Effarig shop upgrade by numeric id (0..3).
    func buyEffarigUpgrade(id: Int) {
        jsAsync("_nativeBuyEffarigUpgrade(\(id))")
    }

    /// Tap the "Get a Cursed Glyph..." easter-egg button (visible only while V.isFlipped).
    func giveCursedGlyph() {
        jsAsync("_nativeGiveCursedGlyph()")
    }

    // MARK: - Enslaved (Nameless Ones) actions

    /// Request-to-start — shows the PrestigeModal.enslavedRun sheet unless the
    /// user disabled confirmations. Mirrors requestTeresaRun / requestEffarigRun.
    func requestEnslavedRun() {
        if pelleDoomed { return }
        jsQueue.async { [weak self] in
            guard let self else { return }
            let shouldConfirm = self.confirmationEnabled("enslaved")
            if shouldConfirm {
                DispatchQueue.main.async { self.pendingModal = .enslavedRun }
            } else {
                _ = self.context.evaluateScript("_nativeStartEnslavedRun()")
            }
        }
    }

    /// Called from PrestigeConfirmation when the user confirms enslavedRun.
    func performEnslavedRun() {
        jsAsync("_nativeStartEnslavedRun()")
    }

    /// Buy an ENSLAVED_UNLOCKS entry by id (0 = FREE_TICKSPEED_SOFTCAP, 1 = RUN).
    func buyEnslavedUnlock(id: Int) {
        jsAsync("_nativeBuyEnslavedUnlock(\(id))")
    }

    /// Toggle `Enslaved.toggleStoreBlackHole()` — starts/stops charging stored game time.
    func toggleEnslavedStoreBlackHole() {
        jsAsync("_nativeToggleEnslavedStoreBH()")
    }

    /// Toggle `Enslaved.toggleStoreReal()` — starts/stops storing real time (halts production).
    func toggleEnslavedStoreReal() {
        jsAsync("_nativeToggleEnslavedStoreReal()")
    }

    /// Toggle `player.celestials.enslaved.autoStoreReal` — whether offline time is stored vs used for production.
    func toggleEnslavedAutoStoreReal() {
        jsAsync("_nativeToggleEnslavedAutoStoreReal()")
    }

    /// Discharge Black Hole — calls `Enslaved.useStoredTime(false)`.
    func dischargeEnslavedBlackHole() {
        jsAsync("_nativeEnslavedUseStored()")
    }

    /// Toggle `Enslaved.boostReality` — amplify next Reality's rewards by
    /// `realityBoostRatio` in exchange for stored real time.
    func toggleEnslavedAmplify() {
        jsAsync("_nativeToggleEnslavedAmplify()")
    }

    /// Reads `_nativeEnslavedAmplifyState()` and writes the four amplify
    /// fields onto `state.celestials.enslaved`. Called from both
    /// `pollEnslaved` (Celestials tab) and from the Glyphs poll site so the
    /// Reality Amplify button stays live on whichever tab the player is
    /// looking at.
    func pollEnslavedAmplifyState(_ state: inout GameState) {
        guard let json = context.evaluateScript("_nativeEnslavedAmplifyState()")?.toString(),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["ready"] as? Bool) == true else { return }
        state.celestials.enslaved.amplifyCanAmplify = (obj["canAmplify"] as? Bool) ?? false
        state.celestials.enslaved.amplifyIsActive = (obj["isActive"] as? Bool) ?? false
        state.celestials.enslaved.amplifyRatio = (obj["ratio"] as? Int) ?? 0
        state.celestials.enslaved.amplifyIsInCelestialReality = (obj["isInCelestialReality"] as? Bool) ?? false
    }

    /// Sets the Black Hole inversion slider (0…300). Mirrors
    /// BlackHoleChargingSliders.adjustSliderNegative — also bumps
    /// `player.requirementChecks.reality.slowestBH`.
    func setEnslavedNegativeSlider(_ value: Double) {
        let clamped = max(0, min(value, 300))
        jsAsync("_nativeSetEnslavedNegativeSlider(\(clamped))")
    }

    #if DEBUG
    /// DEBUG-only: cheat button — adds `years` years of stored game time so the
    /// Enslaved unlock shop can be tested without porting Black Hole charging.
    func devAddEnslavedStoredYears(_ years: Double) {
        // Use scientific notation rendering for huge numbers (1e35, 1e40, …).
        let arg = String(format: "%.15e", years)
        jsAsync("_nativeDevAddEnslavedYears(\(arg))")
    }

    /// DEBUG-only: resets stored game time to 0.
    func devResetEnslavedStoredTime() {
        jsAsync("_nativeDevResetEnslavedTime()")
    }
    #endif  // DEBUG

    // MARK: - Enslaved speedrun-path actions

    /// Tap-to-claim the +100 TT secret study rendered to the right of TS 11
    /// while inside the Nameless Reality. JS helper gates on
    /// `Enslaved.isRunning && !hasSecretStudy` so re-taps / edge cases
    /// (exit-while-sheet-animating, etc.) can't double-reward.
    func claimEnslavedSecretStudy() {
        jsAsync("_nativeClaimEnslavedSecretStudy()")
    }

    /// Swap-action for the Break Infinity button while inside the Nameless
    /// Reality. Delegates to `Enslaved.feelEternity()` which routes the
    /// first-time / repeat message through `Modal.message.show()` — our
    /// `_nativeMessage` bridge surfaces that as a SwiftUI alert.
    func enslavedFeelEternity() {
        jsAsync("_nativeEnslavedFeelEternity()")
    }

    // MARK: - Enslaved hints modal

    /// Fetches the full `EnslavedProgress` snapshot + cost + time-to-next
    /// estimate. Lazy (called on sheet appear + 1Hz timer while visible),
    /// NOT part of the per-tick poll. Dispatches the decoded state to the
    /// main thread via `engine.enslavedHints`.
    func loadEnslavedHints() {
        jsQueue.async { [weak self] in
            guard let self else { return }
            let json = self.context.evaluateScript("_nativeEnslavedHintsState()")?.toString() ?? ""
            guard let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["ready"] as? Bool) == true else {
                DispatchQueue.main.async { self.enslavedHints = nil }
                return
            }
            var state = EnslavedHintsState()
            state.canShowHintsButton = (obj["canShowHintsButton"] as? Bool) ?? false
            state.realityHintsUnlocked = (obj["realityHintsUnlocked"] as? Int) ?? 0
            state.realityHintsTotal = (obj["realityHintsTotal"] as? Int) ?? 8
            state.glyphHintsGiven = (obj["glyphHintsGiven"] as? Int) ?? 0
            state.glyphHintsTotal = (obj["glyphHintsTotal"] as? Int) ?? 3
            state.allRealityHintsShown = (obj["allRealityHintsShown"] as? Bool) ?? false
            state.allGlyphHintsShown = (obj["allGlyphHintsShown"] as? Bool) ?? false
            state.nextHintCostText = (obj["nextHintCostText"] as? String) ?? ""
            state.canAffordHint = (obj["canAffordHint"] as? Bool) ?? false
            state.timeToNextHintText = (obj["timeToNextHintText"] as? String) ?? ""
            state.hintCostIncreases = (obj["hintCostIncreases"] as? Int) ?? 0
            if let arr = obj["realityEntries"] as? [[String: Any]] {
                state.realityEntries = arr.compactMap { d in
                    guard let id = d["id"] as? Int else { return nil }
                    return EnslavedProgressEntry(
                        id: id,
                        hint: (d["hint"] as? String) ?? "",
                        condition: (d["condition"] as? String) ?? "",
                        hasHint: (d["hasHint"] as? Bool) ?? false,
                        hasProgress: (d["hasProgress"] as? Bool) ?? false
                    )
                }.sorted { $0.id < $1.id }
            }
            if let arr = obj["glyphHints"] as? [Any] {
                state.glyphHints = arr.compactMap { $0 as? String }
            }
            DispatchQueue.main.async { self.enslavedHints = state }
        }
    }

    func spendTimeForRealityHint() {
        jsAsync("_nativeSpendTimeForRealityHint()")
        loadEnslavedHints()
    }

    func spendTimeForGlyphHint() {
        jsAsync("_nativeSpendTimeForGlyphHint()")
        loadEnslavedHints()
    }

    // MARK: - Effarig: Glyph Level Factors (shared with Glyphs tab)

    /// Refresh `engine.glyphLevelFactorsSnapshot`. Callable any time — does NOT
    /// require the `.reality` poll category, so the Effarig weights sheet can
    /// show live factor values even when opened from the Celestials tab.
    func loadGlyphLevelFactors() {
        jsQueue.async { [weak self] in
            guard let self else { return }
            let json = self.context.evaluateScript("_nativeGlyphLevelFactors()")?.toString() ?? ""
            var state = GlyphLevelFactorsState.empty
            if let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let arr = (obj["factors"] as? [[String: Any]]) ?? []
                state.factors = arr.compactMap { d in
                    guard let name = d["name"] as? String else { return nil }
                    return GlyphLevelFactor(
                        name: name,
                        formula: (d["formula"] as? String) ?? "",
                        value: (d["value"] as? String) ?? "",
                        op: (d["op"] as? String) ?? "×"
                    )
                }
                state.finalLevel = (obj["finalLevel"] as? String) ?? ""
            }
            DispatchQueue.main.async { self.glyphLevelFactorsSnapshot = state }
        }
    }

    // MARK: - Effarig: Glyph Weights

    func loadEffarigWeights() {
        jsQueue.async { [weak self] in
            guard let self else { return }
            let json = self.context.evaluateScript("_nativeEffarigWeights()")?.toString() ?? ""
            var state = EffarigGlyphWeightsState()
            if let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                state.ep = (obj["ep"] as? Int) ?? 25
                state.repl = (obj["repl"] as? Int) ?? 25
                state.dt = (obj["dt"] as? Int) ?? 25
                state.eternities = (obj["eternities"] as? Int) ?? 25
                state.autoAdjust = (obj["autoAdjust"] as? Bool) ?? false
                state.autoAdjustUnlocked = (obj["autoAdjustUnlocked"] as? Bool) ?? false
            }
            DispatchQueue.main.async { self.effarigGlyphWeights = state }
        }
    }

    func setEffarigWeight(key: String, value: Int) {
        let esc = key.replacingOccurrences(of: "'", with: "\\'")
        jsAsync("_nativeSetEffarigWeight('\(esc)', \(value))")
        // Re-fetch after a brief hop so the sheet sees the canonical value
        // (JS may proportionally rebalance the other three to keep total <= 100).
        loadEffarigWeights()
    }

    func resetEffarigWeights() {
        jsAsync("_nativeResetEffarigWeights()")
        loadEffarigWeights()
    }

    func toggleEffarigAutoWeights() {
        jsAsync("_nativeToggleEffarigAutoWeights()")
        loadEffarigWeights()
    }

    // MARK: - Effarig: Glyph Filter

    func loadGlyphFilter() {
        jsQueue.async { [weak self] in
            guard let self else { return }
            let json = self.context.evaluateScript("_nativeGlyphFilter()")?.toString() ?? ""
            var state = GlyphFilterState()
            if let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                state.selectMode = (obj["selectMode"] as? Int) ?? 0
                state.trashMode = (obj["trashMode"] as? Int) ?? 0
                state.simpleThreshold = (obj["simpleThreshold"] as? Int) ?? 0
                state.alchemyUnlocked = (obj["alchemyUnlocked"] as? Bool) ?? false
                state.autoRealityForFilter = (obj["autoRealityForFilter"] as? Bool) ?? false
                if let typeArr = obj["types"] as? [[String: Any]] {
                    state.types = typeArr.compactMap { d in
                        guard let t = d["type"] as? String else { return nil }
                        return GlyphFilterTypeConfig(
                            type: t,
                            typeDisplayName: (d["typeDisplayName"] as? String) ?? t,
                            typeSymbol: (d["typeSymbol"] as? String) ?? "?",
                            typeColor: (d["typeColor"] as? String) ?? "",
                            rarity: (d["rarity"] as? Int) ?? 0,
                            score: (d["score"] as? Int) ?? 0,
                            effectCount: (d["effectCount"] as? Int) ?? 0,
                            specifiedMask: (d["specifiedMask"] as? Int) ?? 0,
                            effectScores: (d["effectScores"] as? [Int]) ?? [],
                            effectIds: (d["effectIds"] as? [String]) ?? [],
                            effectNames: (d["effectNames"] as? [String]) ?? [],
                            effectBitmaskIndices: (d["effectBitmaskIndices"] as? [Int]) ?? []
                        )
                    }
                }
            }
            DispatchQueue.main.async { self.effarigGlyphFilter = state }
        }
    }

    func setGlyphFilterMode(which: String, value: Int) {
        let esc = which.replacingOccurrences(of: "'", with: "\\'")
        jsAsync("_nativeSetGlyphFilterMode('\(esc)', \(value))")
        loadGlyphFilter()
    }

    func setGlyphFilterType(type: String, field: String, value: Int) {
        let t = type.replacingOccurrences(of: "'", with: "\\'")
        let f = field.replacingOccurrences(of: "'", with: "\\'")
        jsAsync("_nativeSetGlyphFilterType('\(t)', '\(f)', \(value))")
        loadGlyphFilter()
    }

    func setGlyphFilterEffectScore(type: String, idx: Int, value: Int) {
        let t = type.replacingOccurrences(of: "'", with: "\\'")
        jsAsync("_nativeSetGlyphFilterEffectScore('\(t)', \(idx), \(value))")
        loadGlyphFilter()
    }

    /// Mirrors web's GlyphFilterPanel.toggleAutoReality. The JS helper also
    /// resets `player.reality.hasCheckedFilter` so the Reality Autobuyer
    /// re-evaluates on its next tick.
    func toggleGlyphFilterAutoReality() {
        jsAsync("_nativeToggleGlyphFilterAutoReality()")
        loadGlyphFilter()
    }

    // MARK: - Glyph Filter: Import / Export

    /// Copy the current filter's exported string to UIPasteboard + show a toast.
    /// Runs on jsQueue to read the filter, hops to main for pasteboard + toast.
    func exportGlyphFilter() {
        jsQueue.async { [weak self] in
            guard let self else { return }
            let encoded = self.context.evaluateScript("_nativeExportGlyphFilter()")?.toString() ?? ""
            DispatchQueue.main.async {
                if encoded.isEmpty {
                    self.enqueueToast(type: "error", text: String(localized: "Failed to export Glyph filter."))
                } else {
                    UIPasteboard.general.string = encoded
                    self.enqueueToast(type: "info", text: String(localized: "Filter settings copied to clipboard"))
                }
            }
        }
    }

    /// Parse + validate an import string WITHOUT applying it. Returns preview
    /// via completion on the main thread.
    func parseGlyphFilterImport(_ raw: String, completion: @escaping (GlyphFilterImportPreview) -> Void) {
        let esc = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "")
        jsQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(.invalid) }
                return
            }
            let json = self.context.evaluateScript("_nativeParseGlyphFilterImport('\(esc)')")?.toString() ?? ""
            let preview = Self.decodeFilterImportPreview(json)
            DispatchQueue.main.async { completion(preview) }
        }
    }

    /// Commit an import string. `completion(true)` fires on success.
    func importGlyphFilter(_ raw: String, completion: @escaping (Bool) -> Void) {
        let esc = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "")
        jsQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let result = self.context.evaluateScript("_nativeImportGlyphFilter('\(esc)')")?.toString() ?? ""
            let ok = result == "ok"
            DispatchQueue.main.async {
                if ok {
                    self.enqueueToast(type: "info", text: String(localized: "Glyph filter imported."))
                } else {
                    self.enqueueToast(type: "error", text: String(localized: "Invalid Glyph filter string."))
                }
                self.loadGlyphFilter()
                completion(ok)
            }
        }
    }

    private static func decodeFilterImportPreview(_ json: String) -> GlyphFilterImportPreview {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["valid"] as? Bool) == true else {
            return .invalid
        }
        let newSelect = (obj["select"] as? Int) ?? 0
        let newSimple = (obj["simple"] as? Int) ?? 0
        let newTrash = (obj["trash"] as? Int) ?? 0
        let curSelect = (obj["currentSelect"] as? Int) ?? 0
        let curSimple = (obj["currentSimple"] as? Int) ?? 0
        let curTrash = (obj["currentTrash"] as? Int) ?? 0
        let selName = (obj["selectName"] as? String) ?? ""
        let curSelName = (obj["currentSelectName"] as? String) ?? ""
        let trashLabel = (obj["trashLabel"] as? String) ?? ""
        let curTrashLabel = (obj["currentTrashLabel"] as? String) ?? ""

        let diff: (Int, Int, (Int) -> String) -> String = { oldVal, newVal, fmt in
            oldVal == newVal ? "(No change)" : "\(fmt(oldVal)) ➜ \(fmt(newVal))"
        }
        let selectDiff = curSelect == newSelect ? "(No change)" : "\(curSelName) ➜ \(selName)"
        let simpleDiff = diff(curSimple, newSimple) { String($0) }
        let trashDiff = curTrash == newTrash ? "(No change)" : "\(curTrashLabel) ➜ \(trashLabel)"

        var typeSummary = ""
        if let types = obj["types"] as? [String: Any], !types.isEmpty {
            let names = types.keys.sorted().joined(separator: ", ")
            typeSummary = "Per-type settings (rarity / score / effectCount / mask / scores) will be replaced for: \(names)."
        }

        return GlyphFilterImportPreview(
            valid: true,
            selectName: selectDiff,
            simpleDiff: simpleDiff,
            trashLabel: trashDiff,
            currentTrashLabel: curTrashLabel,
            newSelect: newSelect, newSimple: newSimple, newTrash: newTrash,
            currentSelect: curSelect, currentSimple: curSimple, currentTrash: curTrash,
            typeSummary: typeSummary
        )
    }

    // MARK: - Effarig: Glyph Presets

    func loadGlyphPresets() {
        jsQueue.async { [weak self] in
            guard let self else { return }
            let json = self.context.evaluateScript("_nativeGlyphPresets()")?.toString() ?? ""
            var state = EffarigPresetsState()
            if let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                state.hasEquipped = (obj["hasEquipped"] as? Bool) ?? false
                state.ignoreEffects = (obj["ignoreEffects"] as? Bool) ?? true
                state.ignoreRarity = (obj["ignoreRarity"] as? Bool) ?? true
                state.ignoreLevel = (obj["ignoreLevel"] as? Bool) ?? true
                if let slotArr = obj["slots"] as? [[String: Any]] {
                    state.slots = slotArr.compactMap { d in
                        guard let slotId = d["id"] as? Int else { return nil }
                        let name = (d["name"] as? String) ?? ""
                        let isEmpty = (d["isEmpty"] as? Bool) ?? true
                        let records: [TeresaGlyphRecord] = ((d["glyphs"] as? [[String: Any]]) ?? []).enumerated().compactMap { (idx, g) in
                            TeresaGlyphRecord(
                                id: idx,
                                type: (g["type"] as? String) ?? "",
                                symbol: (g["symbol"] as? String) ?? "?",
                                level: (g["level"] as? Int) ?? 0,
                                effectCount: (g["effectCount"] as? Int) ?? 0,
                                typeColor: (g["typeColor"] as? String) ?? "",
                                rarityColor: (g["rarityColor"] as? String) ?? "",
                                rarityPercent: (g["rarityPercent"] as? String) ?? "",
                                rarityPercentNum: (g["rarityPercentNum"] as? Double) ?? 0,
                                rarityName: (g["rarityName"] as? String) ?? "",
                                effects: (g["effects"] as? [String]) ?? []
                            )
                        }
                        return GlyphPresetSlot(id: slotId, name: name, glyphs: records, isEmpty: isEmpty)
                    }
                }
            }
            DispatchQueue.main.async { self.effarigGlyphPresets = state }
        }
    }

    func saveGlyphPreset(slot: Int) {
        jsAsync("_nativeSaveGlyphPreset(\(slot))")
        loadGlyphPresets()
    }

    func loadGlyphPreset(slot: Int) {
        jsAsync("_nativeLoadGlyphPreset(\(slot))")
        loadGlyphPresets()
    }

    func deleteGlyphPreset(slot: Int) {
        jsAsync("_nativeDeleteGlyphPreset(\(slot))")
        loadGlyphPresets()
    }

    func renameGlyphPreset(slot: Int, name: String) {
        let esc = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
        jsAsync("_nativeRenameGlyphPreset(\(slot), '\(esc)')")
        loadGlyphPresets()
    }

    func setGlyphPresetIgnore(field: String, value: Bool) {
        let f = field.replacingOccurrences(of: "'", with: "\\'")
        jsAsync("_nativeSetGlyphPresetIgnore('\(f)', \(value ? "true" : "false"))")
        loadGlyphPresets()
    }

    /// Advance the quote queue (dismisses the current quote and shows the next
    /// if any is queued).
    func advanceQuoteQueue() {
        jsAsync("_nativeAdvanceQuote()")
    }

    /// Populate `engine.gameState.celestials.quoteHistory` with the given
    /// celestial's unlocked quotes. Called when user taps the History button.
    func loadQuoteHistory(for celestialKey: String) {
        let esc = celestialKey.replacingOccurrences(of: "'", with: "\\'")
        jsQueue.async { [weak self] in
            guard let self else { return }
            let json = self.context.evaluateScript("_nativeShowQuoteHistory('\(esc)')")?.toString() ?? "[]"
            let entries: [QuoteHistoryEntry]
            if let data = json.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                entries = arr.compactMap { d in
                    guard let qid = d["quoteId"] as? Int,
                          let first = d["firstLine"] as? String,
                          let total = d["totalLines"] as? Int else { return nil }
                    return QuoteHistoryEntry(quoteId: qid, firstLine: first, totalLines: total)
                }
            } else {
                entries = []
            }
            DispatchQueue.main.async {
                self.celestialQuoteHistory = entries
            }
        }
    }

    func replayQuote(celestialKey: String, quoteId: Int) {
        let esc = celestialKey.replacingOccurrences(of: "'", with: "\\'")
        jsAsync("_nativeReplayQuote('\(esc)', \(quoteId))")
    }

    // MARK: - Polling (called from pollDirect on jsQueue)

    /// Reads navigation + Teresa data. Tab-gated on PollCategory.celestials.
    /// Mutates `state.celestials` in place.
    func pollCelestialsTab(_ state: inout GameState) {
        pollNavigation(&state)
        // Only poll the active celestial subtab (each does an evaluateScript +
        // JSON round trip; running all 4+ every frame when only one is visible
        // is wasteful and will compound as more celestials ship).
        switch _jsActiveSubtab {
        case .teresa:      pollTeresa(&state)
        case .effarig:     pollEffarig(&state)
        case .namelessOnes: pollEnslaved(&state)
        case .v:           pollV(&state)
        case .ra:          pollRa(&state)
        case .laitela:     pollLaitela(&state)
        case .pelle:       pollPelle(&state)
        default:           break  // navigation-only, or future celestials
        }
    }

    /// Always-on (once per tick) quote poll. Writes to main-thread published
    /// `activeQuote` via DispatchQueue.main.async so the sheet can present
    /// regardless of which tab is active.
    ///
    /// Fast path: a ~20-byte fingerprint (`<celestialKey>/<quoteId>/<queueSize>`)
    /// is read first. If it matches the last-seen value, we skip the full JSON
    /// serialize + parse + main dispatch entirely. Steady state is therefore a
    /// single JSValue.toString() per tick.
    func pollQuoteQueue() {
        let key = context.evaluateScript("_nativeQuoteKey()")?.toString() ?? ""
        // Fingerprint format: "<celestial>/<quoteId>/<queueSize>" or
        // "/0/<queueSize>" when no quote. Skip the JSON parse only when
        // the fingerprint is unchanged AND there's no active quote — when
        // a quote IS active, the wordShift.wordCycle text changes every
        // 250ms and we need to repoll to surface the animation.
        let hasActive = !key.isEmpty && !key.hasPrefix("/0/")
        if !hasActive && key == _lastQuoteKey { return }
        _lastQuoteKey = key

        guard let json = context.evaluateScript("_nativeQuoteState()")?.toString(),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let queueSize = (obj["queueSize"] as? Int) ?? 0
        let currentDict = obj["current"] as? [String: Any]
        let newState = currentDict.flatMap { d -> QuoteState? in
            guard let celKey = d["celestialKey"] as? String,
                  let display = d["celestialDisplayName"] as? String,
                  let symbol = d["celestialSymbol"] as? String,
                  let qid = d["quoteId"] as? Int,
                  let lineArr = d["lines"] as? [[String: Any]] else { return nil }
            let lines: [QuoteLineInfo] = lineArr.map { ln in
                QuoteLineInfo(
                    text: (ln["text"] as? String) ?? "",
                    celestialKey: (ln["celestialKey"] as? String) ?? celKey,
                    showCelestialName: (ln["showCelestialName"] as? Bool) ?? true
                )
            }
            return QuoteState(
                celestialKey: celKey,
                celestialDisplayName: display,
                celestialSymbol: symbol,
                quoteId: qid,
                lines: lines,
                queueSize: queueSize
            )
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Update if quote identity changed (open / advance / close), OR
            // if the same quote's line texts differ — the latter case fires
            // every poll while wordCycle is animating.
            if self.activeQuote != newState {
                self.activeQuote = newState
            }
        }
    }

    private func pollNavigation(_ state: inout GameState) {
        guard let json = context.evaluateScript("_nativeNavigationState()")?.toString(),
              let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }
        var nodes: [CelestialNavNodeState] = []
        nodes.reserveCapacity(arr.count)
        for d in arr {
            guard let id = d["id"] as? String else { continue }
            let complete = (d["complete"] as? Double) ?? 0
            let visible = (d["visible"] as? Bool) ?? true
            let legend = (d["legend"] as? String) ?? ""
            nodes.append(CelestialNavNodeState(
                id: id,
                completeFraction: max(0, min(complete, 1)),
                isVisible: visible,
                legendText: legend
            ))
        }
        state.celestials.navigation.nodes = nodes
    }

    private func pollTeresa(_ state: inout GameState) {
        guard let json = context.evaluateScript("_nativeTeresaState()")?.toString(),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["ready"] as? Bool) == true else { return }

        var t = state.celestials.teresa
        t.pouredAmount = (obj["pouredAmount"] as? String) ?? "0"
        t.pouredAmountRaw = (obj["pouredAmountRaw"] as? Double) ?? 0
        t.pouredAmountCap = (obj["pouredAmountCap"] as? String) ?? "1.00e24"
        t.pouredAmountCapRaw = (obj["pouredAmountCapRaw"] as? Double) ?? 1e24
        t.fillFraction = (obj["fill"] as? Double) ?? 0
        t.possibleFillFraction = (obj["possibleFill"] as? Double) ?? 0
        t.rmMultiplier = (obj["rmMultiplier"] as? String) ?? "x1.00"
        t.realityMachines = (obj["realityMachines"] as? String) ?? "0"
        // Currency.perkPoints.value is a plain JS Number, but Uncountability
        // (Glyph Alchemy resource) adds a fractional amount per second, so
        // post-unlock the JSON arrives as a Double rather than an Int. Same
        // Int/Double/NSNumber fallback chain we use in the perks page poll
        // (GameEngine.swift `pp` block); without it, the cast silently
        // returns 0 once any fractional perk-point accumulation starts.
        t.perkPoints = {
            if let v = obj["perkPoints"] as? Int { return v }
            if let v = obj["perkPoints"] as? Double { return Int(v) }
            if let v = obj["perkPoints"] as? NSNumber { return v.intValue }
            return 0
        }()
        t.hasRun = (obj["hasRun"] as? Bool) ?? false
        t.hasEPGen = (obj["hasEPGen"] as? Bool) ?? false
        t.hasShop = (obj["hasShop"] as? Bool) ?? false
        t.raisedPerkShop = (obj["raisedPerkShop"] as? Bool) ?? false
        t.isRunning = (obj["isRunning"] as? Bool) ?? false
        t.runCompleted = (obj["runCompleted"] as? Bool) ?? false
        t.bestRunAM = (obj["bestRunAM"] as? String) ?? "0"
        if let gArr = obj["bestAMSet"] as? [[String: Any]] {
            t.bestAMSet = gArr.enumerated().compactMap { (idx, d) in
                TeresaGlyphRecord(
                    id: idx,
                    type: (d["type"] as? String) ?? "",
                    symbol: (d["symbol"] as? String) ?? "?",
                    level: (d["level"] as? Int) ?? 0,
                    effectCount: (d["effectCount"] as? Int) ?? 0,
                    typeColor: (d["typeColor"] as? String) ?? "",
                    rarityColor: (d["rarityColor"] as? String) ?? "",
                    rarityPercent: (d["rarityPercent"] as? String) ?? "",
                    rarityPercentNum: (d["rarityPercentNum"] as? Double) ?? 0,
                    rarityName: (d["rarityName"] as? String) ?? "",
                    effects: (d["effects"] as? [String]) ?? []
                )
            }
        }
        t.lastRepeatedMachines = (obj["lastRepeatedMachines"] as? String) ?? ""
        t.lastRepeatedMachinesLabel = (obj["lastRepeatedMachinesLabel"] as? String) ?? ""
        t.runReward = (obj["runReward"] as? String) ?? "x1.00"
        t.runDescription = (obj["runDescription"] as? String) ?? ""

        if let uArr = obj["unlocks"] as? [[String: Any]] {
            t.unlocks = uArr.compactMap { d in
                guard let id = d["id"] as? Int,
                      let desc = d["description"] as? String else { return nil }
                let priceRaw = d["price"]
                let price: Double
                if let p = priceRaw as? Double { price = p }
                else if let p = priceRaw as? Int { price = Double(p) }
                else { price = 0 }
                return TeresaUnlockInfo(
                    id: id,
                    key: (d["key"] as? String) ?? "",
                    price: price,
                    description: desc,
                    isUnlocked: (d["isUnlocked"] as? Bool) ?? false,
                    canBeUnlocked: (d["canBeUnlocked"] as? Bool) ?? false,
                    pelleDisabled: (d["pelleDisabled"] as? Bool) ?? false
                )
            }.sorted { $0.price < $1.price }
        }

        if let pArr = obj["perkShop"] as? [[String: Any]] {
            t.perkShop = pArr.compactMap { d in
                guard let id = d["id"] as? Int else { return nil }
                return PerkShopUpgradeInfo(
                    id: id,
                    key: (d["key"] as? String) ?? "",
                    description: (d["description"] as? String) ?? "",
                    cost: (d["cost"] as? String) ?? "0",
                    effectText: (d["effectText"] as? String) ?? "",
                    bought: (d["bought"] as? Int) ?? 0,
                    capText: d["capText"] as? String,
                    isCapped: (d["isCapped"] as? Bool) ?? false,
                    isAffordable: (d["isAffordable"] as? Bool) ?? false
                )
            }
        }

        state.celestials.teresa = t
    }

    // MARK: - Effarig poll

    private func pollEffarig(_ state: inout GameState) {
        guard let json = context.evaluateScript("_nativeEffarigState()")?.toString(),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["ready"] as? Bool) == true else { return }

        var e = state.celestials.effarig
        e.relicShards = (obj["relicShards"] as? String) ?? "0"
        e.shardRarityBoostPct = (obj["shardRarityBoostPct"] as? String) ?? "0%"
        e.shardPower = (obj["shardPower"] as? String) ?? ""
        e.relicShardRarityAlwaysMax = (obj["relicShardRarityAlwaysMax"] as? Bool) ?? false
        e.shardsGained = (obj["shardsGained"] as? String) ?? "0"
        e.currentShardsRate = (obj["currentShardsRate"] as? String) ?? "0"
        e.amplification = (obj["amplification"] as? Int) ?? 0
        e.amplifiedShards = (obj["amplifiedShards"] as? String) ?? "0"
        e.amplifiedShardsRate = (obj["amplifiedShardsRate"] as? String) ?? "0"
        e.runUnlocked = (obj["runUnlocked"] as? Bool) ?? false
        e.isRunning = (obj["isRunning"] as? Bool) ?? false
        let stageRaw = (obj["currentStage"] as? Int) ?? 1
        e.currentStage = EffarigStage(rawValue: stageRaw) ?? .infinity
        e.currentStageName = (obj["currentStageName"] as? String) ?? "Infinity"
        e.glyphLevelCap = (obj["glyphLevelCap"] as? Int) ?? 100
        e.vIsFlipped = (obj["vIsFlipped"] as? Bool) ?? false
        e.runDescription = (obj["runDescription"] as? String) ?? ""

        if let arr = obj["shopUpgrades"] as? [[String: Any]] {
            e.shopUpgrades = arr.compactMap { d in
                guard let id = d["id"] as? Int,
                      let key = d["key"] as? String,
                      let desc = d["description"] as? String else { return nil }
                return EffarigShopUpgrade(
                    id: id, key: key, description: desc,
                    cost: (d["cost"] as? String) ?? "0",
                    isUnlocked: (d["isUnlocked"] as? Bool) ?? false,
                    canAfford: (d["canAfford"] as? Bool) ?? false
                )
            }.sorted { $0.id < $1.id }
        }

        if let arr = obj["runUnlocks"] as? [[String: Any]] {
            e.runUnlocks = arr.compactMap { d in
                guard let id = d["id"] as? Int,
                      let key = d["key"] as? String,
                      let label = d["label"] as? String else { return nil }
                return EffarigRunUnlock(
                    id: id, key: key, label: label,
                    description: (d["description"] as? String) ?? "",
                    descriptionLines: (d["descriptionLines"] as? [String]) ?? [],
                    isUnlocked: (d["isUnlocked"] as? Bool) ?? false
                )
            }.sorted { $0.id < $1.id }
        }

        state.celestials.effarig = e
    }

    // MARK: - Enslaved poll

    private func pollEnslaved(_ state: inout GameState) {
        guard let json = context.evaluateScript("_nativeEnslavedState()")?.toString(),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["ready"] as? Bool) == true else { return }

        var e = state.celestials.enslaved
        e.isUnlocked = (obj["isUnlocked"] as? Bool) ?? false
        e.isRunning = (obj["isRunning"] as? Bool) ?? false
        e.isCompleted = (obj["isCompleted"] as? Bool) ?? false
        e.isDoomed = (obj["isDoomed"] as? Bool) ?? false

        e.isStoringBlackHole = (obj["isStoringBlackHole"] as? Bool) ?? false
        e.canModifyGameTimeStorage = (obj["canModifyGameTimeStorage"] as? Bool) ?? false
        e.canDischarge = (obj["canDischarge"] as? Bool) ?? false
        e.hasNoCharge = (obj["hasNoCharge"] as? Bool) ?? true
        e.storedBlackHoleText = (obj["storedBlackHoleText"] as? String) ?? "0s"
        e.storedBlackHoleMs = (obj["storedBlackHoleMs"] as? Double) ?? 0
        e.currentBHStoreAmountPerMs = (obj["currentBHStoreAmountPerMs"] as? Double) ?? 0
        e.nerfedInRealityText = (obj["nerfedInRealityText"] as? String) ?? ""

        e.isStoringReal = (obj["isStoringReal"] as? Bool) ?? false
        e.autoStoreReal = (obj["autoStoreReal"] as? Bool) ?? false
        e.offlineProgressEnabled = (obj["offlineProgressEnabled"] as? Bool) ?? false
        e.canChangeStoreRealTime = (obj["canChangeStoreRealTime"] as? Bool) ?? false
        e.hasReachedCurrentCap = (obj["hasReachedCurrentCap"] as? Bool) ?? false
        e.storedRealText = (obj["storedRealText"] as? String) ?? "0s"
        e.storedRealEfficiencyPct = (obj["storedRealEfficiencyPct"] as? String) ?? "70%"
        e.storedRealCapText = (obj["storedRealCapText"] as? String) ?? "8h"

        e.isNegativeBHUnlocked = (obj["isNegativeBHUnlocked"] as? Bool) ?? false
        e.isBHInverted = (obj["isBHInverted"] as? Bool) ?? false
        e.negativeSlider = (obj["negativeSlider"] as? Double) ?? 0
        e.negativeBHDivisor = (obj["negativeBHDivisor"] as? String) ?? "1.00"
        e.sliderDisabled = (obj["sliderDisabled"] as? Bool) ?? false
        e.sliderLockText = (obj["sliderLockText"] as? String) ?? ""

        e.hasSecretStudy = (obj["hasSecretStudy"] as? Bool) ?? false
        e.feltEternity = (obj["feltEternity"] as? Bool) ?? false

        e.hasRunUnlock = (obj["hasRunUnlock"] as? Bool) ?? false
        if let arr = obj["runDescription"] as? [Any] {
            e.runDescription = arr.compactMap { $0 as? String }
        } else if let s = obj["runDescription"] as? String {
            e.runDescription = s.components(separatedBy: "\n")
        }

        if let arr = obj["unlocks"] as? [[String: Any]] {
            e.unlocks = arr.compactMap { d in
                guard let id = d["id"] as? Int else { return nil }
                return EnslavedUnlockInfo(
                    id: id,
                    description: (d["description"] as? String) ?? "",
                    priceYears: (d["priceYears"] as? String) ?? "",
                    hasBought: (d["hasBought"] as? Bool) ?? false,
                    canBuy: (d["canBuy"] as? Bool) ?? false,
                    timeToObtainText: (d["timeToObtainText"] as? String) ?? ""
                )
            }.sorted { $0.id < $1.id }
        }

        e.hasAutoPulse = (obj["hasAutoPulse"] as? Bool) ?? false
        e.canAutoPulse = (obj["canAutoPulse"] as? Bool) ?? false
        e.isAutoPulsing = (obj["isAutoPulsing"] as? Bool) ?? false
        e.autoPulseSpeedText = (obj["autoPulseSpeedText"] as? String) ?? ""

        state.celestials.enslaved = e
        pollEnslavedAmplifyState(&state)
    }

    /// Toggle Pulse Black Hole — auto-discharges 1% of stored game time every
    /// 5 ticks. Unlocked via `Ra.unlocks.autoPulseTime` (Enslaved pet lv 10).
    func toggleEnslavedAutoPulse() {
        jsAsync("player.celestials.enslaved.isAutoReleasing = !player.celestials.enslaved.isAutoReleasing")
    }

    // MARK: - V poll

    private func pollV(_ state: inout GameState) {
        guard let json = context.evaluateScript("_nativeVState()")?.toString(),
              json != "null",
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        var v = VState()
        v.isUnlocked = (obj["isUnlocked"] as? Bool) ?? false
        v.isRunning = (obj["isRunning"] as? Bool) ?? false
        v.canUnlockCelestial = (obj["canUnlockCelestial"] as? Bool) ?? false
        v.spaceTheorems = (obj["spaceTheorems"] as? Int) ?? 0
        v.ppAvailable = (obj["ppAvailable"] as? String) ?? "0"
        v.showReduction = (obj["showReduction"] as? Bool) ?? false
        v.isFlipped = (obj["isFlipped"] as? Bool) ?? false
        v.wantsFlipped = (obj["wantsFlipped"] as? Bool) ?? false
        v.runDescription = (obj["runDescription"] as? String) ?? ""
        v.hasAlchemy = (obj["hasAlchemy"] as? Bool) ?? false

        // Unlock requirements
        if let reqs = obj["requirements"] as? [[String: Any]] {
            v.unlockRequirements = reqs.compactMap { r in
                guard let id = r["id"] as? Int else { return nil }
                return VUnlockRequirement(
                    id: id,
                    name: (r["name"] as? String) ?? "",
                    current: (r["current"] as? String) ?? "",
                    goal: (r["goal"] as? String) ?? "",
                    progress: (r["progress"] as? Double) ?? 0,
                    isMet: (r["isMet"] as? Bool) ?? false
                )
            }
        }

        // Achievements
        if let achs = obj["achievements"] as? [[String: Any]] {
            v.achievements = achs.compactMap { a in
                guard let id = a["id"] as? Int else { return nil }
                let glyphSet: [TeresaGlyphRecord] = ((a["glyphSet"] as? [[String: Any]]) ?? []).enumerated().compactMap { (idx, g) in
                    TeresaGlyphRecord(
                        id: idx,
                        type: (g["type"] as? String) ?? "",
                        symbol: (g["symbol"] as? String) ?? "?",
                        level: (g["level"] as? Int) ?? 0,
                        effectCount: (g["effectCount"] as? Int) ?? 0,
                        typeColor: (g["typeColor"] as? String) ?? "",
                        rarityColor: (g["rarityColor"] as? String) ?? "",
                        rarityPercent: (g["rarityPercent"] as? String) ?? "",
                        rarityPercentNum: (g["rarityPercentNum"] as? Double) ?? 0,
                        rarityName: (g["rarityName"] as? String) ?? "",
                        effects: (g["effects"] as? [String]) ?? []
                    )
                }
                return VAchievementInfo(
                    id: id,
                    name: (a["name"] as? String) ?? "",
                    description: (a["description"] as? String) ?? "",
                    completions: (a["completions"] as? Int) ?? 0,
                    maxCompletions: (a["maxCompletions"] as? Int) ?? 0,
                    isHard: (a["isHard"] as? Bool) ?? false,
                    rewardPerCompletion: (a["rewardPerCompletion"] as? Int) ?? 1,
                    record: (a["record"] as? String) ?? "",
                    canReduce: (a["canReduce"] as? Bool) ?? false,
                    reductionCost: (a["reductionCost"] as? String) ?? "",
                    reductionMode: (a["reductionMode"] as? String) ?? "",
                    reductionValue: (a["reductionValue"] as? String) ?? "",
                    isReduced: (a["isReduced"] as? Bool) ?? false,
                    isFullyCompleted: (a["isFullyCompleted"] as? Bool) ?? false,
                    hexColor: (a["hexColor"] as? String) ?? "",
                    glyphSet: glyphSet
                )
            }
        }

        // Milestones
        if let miles = obj["milestones"] as? [[String: Any]] {
            v.milestones = miles.compactMap { m in
                guard let id = m["id"] as? Int else { return nil }
                return VMilestoneInfo(
                    id: id,
                    description: (m["description"] as? String) ?? "",
                    reward: (m["reward"] as? String) ?? "",
                    formattedEffect: (m["formattedEffect"] as? String) ?? "",
                    stRequired: (m["stRequired"] as? Int) ?? 0,
                    isReached: (m["isReached"] as? Bool) ?? false
                )
            }
        }

        v.unlockButtonDescription = (obj["unlockButtonDescription"] as? String) ?? ""
        v.unlockButtonReward = (obj["unlockButtonReward"] as? String) ?? ""

        state.celestials.v = v
    }

    // MARK: - V actions

    func unlockV() { jsAsync("_nativeUnlockV()") }

    func requestVRun() {
        if pelleDoomed { return }
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                if self.confirmationEnabled("v") {
                    DispatchQueue.main.async { self.pendingModal = .vRun }
                } else {
                    _ = self.context.evaluateScript("_nativeStartVRun()")
                }
            }
        }
    }

    func performVRun() {
        jsAsync("_nativeStartVRun()")
    }

    func reduceVGoal(_ achId: Int) { jsAsync("_nativeReduceVGoal(\(achId))") }
    func toggleVFlipped() { jsAsync("_nativeToggleVFlipped()") }

    // MARK: - Ra poll

    private func pollRa(_ state: inout GameState) {
        guard let json = context.evaluateScript("_nativeRaState()")?.toString(),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["ready"] as? Bool) == true else { return }

        var r = RaState()
        r.isUnlocked = (obj["isUnlocked"] as? Bool) ?? false
        if !r.isUnlocked {
            state.celestials.ra = r
            return
        }

        r.isRunning = (obj["isRunning"] as? Bool) ?? false
        r.petWithRemembrance = (obj["petWithRemembrance"] as? String) ?? ""
        r.showRemembrance = (obj["showRemembrance"] as? Bool) ?? false
        r.remembranceUnlocked = (obj["remembranceUnlocked"] as? Bool) ?? false
        r.remembranceMult = (obj["remembranceMult"] as? Double) ?? 5
        r.remembranceNerf = (obj["remembranceNerf"] as? Double) ?? 0.5
        r.remembranceRequiredLevel = (obj["remembranceRequiredLevel"] as? Int) ?? 20
        r.totalPetLevel = (obj["totalPetLevel"] as? Int) ?? 0
        r.maxTotalPetLevel = (obj["maxTotalPetLevel"] as? Int) ?? 100
        r.levelCap = (obj["levelCap"] as? Int) ?? 25
        r.memoriesPerChunk = (obj["memoriesPerChunk"] as? String) ?? "1.0"
        r.memoryBoostResources = (obj["memoryBoostResources"] as? String) ?? ""
        r.canStartRun = (obj["canStartRun"] as? Bool) ?? false
        r.runDescription = (obj["runDescription"] as? String) ?? ""
        r.exitAvailable = (obj["exitAvailable"] as? Bool) ?? false

        if let pArr = obj["pets"] as? [[String: Any]] {
            r.pets = pArr.compactMap { d -> RaPetInfo? in
                guard let key = d["key"] as? String,
                      let name = d["displayName"] as? String else { return nil }
                var p = RaPetInfo(
                    key: key,
                    displayName: name,
                    colorHex: (d["colorHex"] as? String) ?? "#9063de",
                    chunkGainResource: (d["chunkGainResource"] as? String) ?? "",
                    memoryGainResource: (d["memoryGainResource"] as? String) ?? ""
                )
                p.isUnlocked = (d["isUnlocked"] as? Bool) ?? false
                p.unlockRequirementText = (d["unlockRequirementText"] as? String) ?? ""
                p.level = (d["level"] as? Int) ?? 0
                p.isCapped = (d["isCapped"] as? Bool) ?? false
                p.memories = (d["memories"] as? String) ?? "0"
                p.memoriesRaw = (d["memoriesRaw"] as? Double) ?? 0
                p.memoryChunks = (d["memoryChunks"] as? String) ?? "0"
                p.chunksPerSecond = (d["chunksPerSecond"] as? String) ?? "0"
                p.memoriesPerSecond = (d["memoriesPerSecond"] as? String) ?? "0"
                p.requiredMemories = (d["requiredMemories"] as? String) ?? "0"
                p.requiredMemoriesRaw = (d["requiredMemoriesRaw"] as? Double) ?? 0
                p.progressToNextLevel = (d["progressToNextLevel"] as? Double) ?? 0
                p.timeToNextLevel = (d["timeToNextLevel"] as? String) ?? ""
                p.hasRemembrance = (d["hasRemembrance"] as? Bool) ?? false
                p.canLevelUp = (d["canLevelUp"] as? Bool) ?? false
                p.scalingUpgradeText = (d["scalingUpgradeText"] as? String) ?? ""
                p.nextUnlockText = (d["nextUnlockText"] as? String) ?? ""
                p.memoryMultiplier = (d["memoryMultiplier"] as? Double) ?? 1
                p.memoryMultiplierText = (d["memoryMultiplierText"] as? String) ?? ""
                if let u = d["memoryUpgrade"] as? [String: Any] {
                    p.memoryUpgrade = decodeRaUpgrade(u)
                }
                if let u = d["chunkUpgrade"] as? [String: Any] {
                    p.chunkUpgrade = decodeRaUpgrade(u)
                }
                if let uArr = d["unlocks"] as? [[String: Any]] {
                    p.unlocks = uArr.compactMap { ud -> RaUnlockInfo? in
                        guard let id = ud["id"] as? Int else { return nil }
                        return RaUnlockInfo(
                            id: id,
                            pet: (ud["pet"] as? String) ?? "",
                            level: (ud["level"] as? Int) ?? 0,
                            reward: (ud["reward"] as? String) ?? "",
                            iconToken: (ud["iconToken"] as? String) ?? "sf:star.fill",
                            isUnlocked: (ud["isUnlocked"] as? Bool) ?? false,
                            disabledByPelle: (ud["disabledByPelle"] as? Bool) ?? false
                        )
                    }
                }
                return p
            }
        }

        state.celestials.ra = r
    }

    private func decodeRaUpgrade(_ d: [String: Any]) -> RaPetUpgradeInfo {
        var u = RaPetUpgradeInfo()
        u.cost = (d["cost"] as? String) ?? "0"
        u.costRaw = (d["costRaw"] as? Double) ?? 0
        u.canAfford = (d["canAfford"] as? Bool) ?? false
        u.isCapped = (d["isCapped"] as? Bool) ?? false
        u.currentMult = (d["currentMult"] as? String) ?? "1.0x"
        u.nextMult = (d["nextMult"] as? String) ?? ""
        u.effectDescription = (d["effectDescription"] as? String) ?? ""
        u.timeToAfford = (d["timeToAfford"] as? String) ?? ""
        return u
    }

    // MARK: - Ra actions

    func requestRaRun() {
        if pelleDoomed { return }
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                if self.confirmationEnabled("ra") {
                    DispatchQueue.main.async { self.pendingModal = .raRun }
                } else {
                    _ = self.context.evaluateScript("_nativeStartRaRun()")
                }
            }
        }
    }
    func performRaRun() { jsAsync("_nativeStartRaRun()") }

    func raLevelUp(_ petKey: String) {
        let esc = petKey.replacingOccurrences(of: "'", with: "\\'")
        jsAsync("_nativeRaLevelUp('\(esc)')")
    }
    func raBuyMemoryUpgrade(_ petKey: String) {
        let esc = petKey.replacingOccurrences(of: "'", with: "\\'")
        jsAsync("_nativeRaBuyMemoryUpgrade('\(esc)')")
    }
    func raBuyChunkUpgrade(_ petKey: String) {
        let esc = petKey.replacingOccurrences(of: "'", with: "\\'")
        jsAsync("_nativeRaBuyChunkUpgrade('\(esc)')")
    }
    func raSelectRemembrance(_ petKey: String) {
        let esc = petKey.replacingOccurrences(of: "'", with: "\\'")
        jsAsync("_nativeRaSelectRemembrance('\(esc)')")
    }

    #if DEBUG
    func devMaxRaPet(_ petKey: String) {
        let esc = petKey.replacingOccurrences(of: "'", with: "\\'")
        jsAsync("_nativeDevMaxRaPet('\(esc)')")
    }
    #endif

    // MARK: - V debug cheats

    #if DEBUG
    func devForceVRequirements() { jsAsync("_nativeDevForceVRequirements()") }
    func devCompleteVAchievement(_ id: Int) { jsAsync("_nativeDevCompleteVAchievement(\(id))") }
    func devMaxVAchievement(_ id: Int) { jsAsync("_nativeDevMaxVAchievement(\(id))") }
    func devCompleteAllNormalVAchievements() { jsAsync("_nativeDevCompleteAllNormalVAchievements()") }
    func devCompleteAllVAchievements() { jsAsync("_nativeDevCompleteAllVAchievements()") }
    #endif

    // MARK: - Lai'tela poll

    private func pollLaitela(_ state: inout GameState) {
        guard let json = context.evaluateScript("_nativeLaitelaState()")?.toString(),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["ready"] as? Bool) == true else { return }

        var l = LaitelaState()
        l.ready = true
        l.isUnlocked = (obj["isUnlocked"] as? Bool) ?? false
        l.isDoomed = (obj["isDoomed"] as? Bool) ?? false
        l.darkMatter = (obj["darkMatter"] as? String) ?? "0"
        l.darkMatterCap = (obj["darkMatterCap"] as? String) ?? "0"
        l.darkMatterPerSecText = (obj["darkMatterPerSecText"] as? String) ?? "0"
        l.singularityUnlockTime = (obj["singularityUnlockTime"] as? String) ?? ""
        l.maxDarkMatterEver = (obj["maxDarkMatterEver"] as? String) ?? "0"
        l.darkMatterCapped = (obj["darkMatterCapped"] as? Bool) ?? false
        l.continuumUnlocked = (obj["continuumUnlocked"] as? Bool) ?? false
        l.continuumActive = (obj["continuumActive"] as? Bool) ?? false
        l.continuumDisabled = (obj["continuumDisabled"] as? Bool) ?? false
        l.continuumBonusPct = (obj["continuumBonusPct"] as? String) ?? "0%"

        if let s = obj["singularity"] as? [String: Any] {
            var sing = SingularityInfo()
            sing.singularities = (s["singularities"] as? String) ?? "0"
            sing.singularitiesRaw = (s["singularitiesRaw"] as? Double) ?? 0
            sing.darkEnergy = (s["darkEnergy"] as? String) ?? "0"
            sing.darkEnergyPerSec = (s["darkEnergyPerSec"] as? String) ?? "0"
            sing.cap = (s["cap"] as? String) ?? "200"
            sing.capRaw = (s["capRaw"] as? Double) ?? 200
            sing.capIncreases = (s["capIncreases"] as? Int) ?? 0
            sing.maxCapIncreases = (s["maxCapIncreases"] as? Int) ?? 50
            sing.canPerform = (s["canPerform"] as? Bool) ?? false
            sing.singularitiesGainedPerCondense = (s["singularitiesGainedPerCondense"] as? Int) ?? 1
            sing.formText = (s["formText"] as? String) ?? ""
            sing.waitText = (s["waitText"] as? String) ?? ""
            sing.timePerCondenseText = (s["timePerCondenseText"] as? String) ?? "∞"
            sing.timePerCondenseSec = (s["timePerCondenseSec"] as? Double) ?? 0
            sing.timeUntilCapText = (s["timeUntilCapText"] as? String) ?? ""
            sing.gainPerHourText = (s["gainPerHourText"] as? String) ?? "0"
            sing.autoGainPerHourText = (s["autoGainPerHourText"] as? String) ?? "0"
            sing.darkEnergyPerCapStep = (s["darkEnergyPerCapStep"] as? Int) ?? 10
            sing.gainPerCapStep = (s["gainPerCapStep"] as? Int) ?? 11
            sing.extraTimeAfterSingularityText = (s["extraTimeAfterSingularityText"] as? String) ?? ""
            sing.hasBulkUnlocked = (s["hasBulkUnlocked"] as? Bool) ?? false
            sing.hasAutoCondense = (s["hasAutoCondense"] as? Bool) ?? false
            sing.autoCondenseActive = (s["autoCondenseActive"] as? Bool) ?? false
            sing.autoCondenseFactor = (s["autoCondenseFactor"] as? Double) ?? 0
            sing.autoCondenseFactorText = (s["autoCondenseFactorText"] as? String) ?? ""
            sing.nextLowerStep = (s["nextLowerStep"] as? Int) ?? 0
            sing.willCondenseOnDecrease = (s["willCondenseOnDecrease"] as? Bool) ?? false
            l.singularity = sing
        }

        if let arr = obj["dimensions"] as? [[String: Any]] {
            l.dimensions = arr.compactMap { d -> DarkMatterDimensionInfo? in
                guard let tier = d["tier"] as? Int else { return nil }
                var info = DarkMatterDimensionInfo(tier: tier)
                info.isUnlocked = (d["isUnlocked"] as? Bool) ?? false
                info.amount = (d["amount"] as? String) ?? "0"
                info.interval = (d["interval"] as? String) ?? "1000ms"
                info.intervalMs = (d["intervalMs"] as? Double) ?? 1000
                info.timerPct = (d["timerPct"] as? Double) ?? 0
                info.isIntervalCapped = (d["isIntervalCapped"] as? Bool) ?? false
                info.powerDM = (d["powerDM"] as? String) ?? "x1.00"
                info.powerDE = (d["powerDE"] as? String) ?? "+0.00"
                info.dePerSec = (d["dePerSec"] as? String) ?? "0.00"
                info.dePerSecPct = (d["dePerSecPct"] as? String) ?? "0%"
                info.productionText = (d["productionText"] as? String) ?? ""
                info.intervalCost = (d["intervalCost"] as? String) ?? "0"
                info.powerDMCost = (d["powerDMCost"] as? String) ?? "0"
                info.powerDECost = (d["powerDECost"] as? String) ?? "0"
                info.canBuyInterval = (d["canBuyInterval"] as? Bool) ?? false
                info.canBuyPowerDM = (d["canBuyPowerDM"] as? Bool) ?? false
                info.canBuyPowerDE = (d["canBuyPowerDE"] as? Bool) ?? false
                info.ascensionCount = (d["ascensionCount"] as? Int) ?? 0
                info.hasAscended = (d["hasAscended"] as? Bool) ?? false
                info.nextAscensionIntervalText = (d["nextAscensionIntervalText"] as? String) ?? ""
                info.intervalPurchaseCap = (d["intervalPurchaseCap"] as? Int) ?? 10
                info.adjustedPurchaseCap = (d["adjustedPurchaseCap"] as? Int) ?? 10
                info.continuumValue = (d["continuumValue"] as? Double) ?? 0
                return info
            }.sorted { $0.tier < $1.tier }
        }

        if let a = obj["annihilation"] as? [String: Any] {
            var ann = LaitelaAnnihilationInfo()
            ann.unlocked = (a["unlocked"] as? Bool) ?? false
            ann.isVisible = (a["isVisible"] as? Bool) ?? false
            ann.canAnnihilate = (a["canAnnihilate"] as? Bool) ?? false
            ann.darkMatter = (a["darkMatter"] as? String) ?? "0"
            ann.darkMatterMult = (a["darkMatterMult"] as? String) ?? "x1.00"
            ann.darkMatterMultGain = (a["darkMatterMultGain"] as? String) ?? "+0.00"
            ann.darkMatterMultRatio = (a["darkMatterMultRatio"] as? String) ?? "x1.00"
            ann.autoUnlocked = (a["autoUnlocked"] as? Bool) ?? false
            ann.autoMultiplier = (a["autoMultiplier"] as? Double) ?? 0
            ann.requirementText = (a["requirementText"] as? String) ?? ""
            l.annihilation = ann
        }

        if let ab = obj["autobuyers"] as? [String: Any] {
            var pane = LaitelaAutobuyerPaneInfo()
            pane.isVisible = (ab["isVisible"] as? Bool) ?? false
            pane.dimension = Self.decodeAutobuyerToggle(ab["dimension"] as? [String: Any])
            pane.ascension = Self.decodeAutobuyerToggle(ab["ascension"] as? [String: Any])
            pane.singularity = Self.decodeAutobuyerToggle(ab["singularity"] as? [String: Any])
            pane.annihilation = Self.decodeAutobuyerToggle(ab["annihilation"] as? [String: Any])
            l.autobuyers = pane
        }

        if let r = obj["run"] as? [String: Any] {
            var run = LaitelaRunInfo()
            run.isRunning = (r["isRunning"] as? Bool) ?? false
            run.difficultyTier = (r["difficultyTier"] as? Int) ?? 0
            run.maxAllowedDimension = (r["maxAllowedDimension"] as? Int) ?? 8
            run.fastestCompletionSeconds = (r["fastestCompletionSeconds"] as? Double) ?? 3600
            run.fastestCompletionText = (r["fastestCompletionText"] as? String) ?? ""
            run.realityReward = (r["realityReward"] as? String) ?? "x1.00"
            run.isFullyDestabilized = (r["isFullyDestabilized"] as? Bool) ?? false
            run.tierNotCompleted = (r["tierNotCompleted"] as? Bool) ?? true
            run.runDescription = (r["runDescription"] as? String) ?? ""
            run.runEffectsLines = (r["runEffectsLines"] as? [String]) ?? []
            run.description = (r["description"] as? String) ?? ""
            run.multiplierLine = (r["multiplierLine"] as? String) ?? ""
            if let setArr = r["bestSet"] as? [[String: Any]] {
                run.bestSet = setArr.enumerated().map { (idx, g) in
                    TeresaGlyphRecord(
                        id: idx,
                        type: (g["type"] as? String) ?? "",
                        symbol: (g["symbol"] as? String) ?? "?",
                        level: (g["level"] as? Int) ?? 0,
                        effectCount: (g["effectCount"] as? Int) ?? 0,
                        typeColor: (g["typeColor"] as? String) ?? "",
                        rarityColor: (g["rarityColor"] as? String) ?? "",
                        rarityPercent: (g["rarityPercent"] as? String) ?? "",
                        rarityPercentNum: (g["rarityPercentNum"] as? Double) ?? 0,
                        rarityName: (g["rarityName"] as? String) ?? "",
                        effects: (g["effects"] as? [String]) ?? []
                    )
                }
            }
            l.run = run
        }

        if let arr = obj["nextMilestones"] as? [[String: Any]] {
            l.nextMilestones = arr.compactMap { Self.decodeSingularityMilestone($0) }
        }
        if let arr = obj["allMilestones"] as? [[String: Any]] {
            l.allMilestones = arr.compactMap { Self.decodeSingularityMilestone($0) }
        }

        state.celestials.laitela = l
    }

    private static func decodeAutobuyerToggle(_ d: [String: Any]?) -> LaitelaAutobuyerToggle {
        guard let d else { return LaitelaAutobuyerToggle() }
        var t = LaitelaAutobuyerToggle()
        t.isUnlocked = (d["isUnlocked"] as? Bool) ?? false
        t.isActive = (d["isActive"] as? Bool) ?? false
        t.label = (d["label"] as? String) ?? ""
        t.description = (d["description"] as? String) ?? ""
        return t
    }

    private static func decodeSingularityMilestone(_ d: [String: Any]) -> SingularityMilestoneInfo? {
        guard let id = d["id"] as? String else { return nil }
        var m = SingularityMilestoneInfo(id: id)
        m.name = (d["name"] as? String) ?? id
        m.description = (d["description"] as? String) ?? ""
        m.effectText = (d["effectText"] as? String) ?? ""
        m.nextEffectText = (d["nextEffectText"] as? String) ?? ""
        m.isUnique = (d["isUnique"] as? Bool) ?? false
        m.isMaxed = (d["isMaxed"] as? Bool) ?? false
        m.isUnlocked = (d["isUnlocked"] as? Bool) ?? false
        m.completions = (d["completions"] as? Int) ?? 0
        m.limit = (d["limit"] as? Int) ?? 1
        m.remainingSingularities = (d["remainingSingularities"] as? String) ?? "0"
        m.progressPct = (d["progressPct"] as? Double) ?? 0
        if let mode = d["mode"] as? String, let v = SingularityMilestoneMode(rawValue: mode) {
            m.mode = v
        }
        return m
    }

    // MARK: - Lai'tela actions

    func requestLaitelaRun() {
        if pelleDoomed { return }
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                if self.confirmationEnabled("laitela") {
                    DispatchQueue.main.async { self.pendingModal = .laitelaRun }
                } else {
                    _ = self.context.evaluateScript("_nativeStartLaitelaRun()")
                }
            }
        }
    }
    func performLaitelaRun() { jsAsync("_nativeStartLaitelaRun()") }

    func laitelaBuyInterval(tier: Int) { jsAsync("_nativeLaitelaBuyInterval(\(tier))") }
    func laitelaBuyPowerDM(tier: Int)  { jsAsync("_nativeLaitelaBuyPowerDM(\(tier))") }
    func laitelaBuyPowerDE(tier: Int)  { jsAsync("_nativeLaitelaBuyPowerDE(\(tier))") }
    func laitelaAscend(tier: Int)      { jsAsync("_nativeLaitelaAscend(\(tier))") }
    func laitelaMaxAllDMD()            { jsAsync("_nativeLaitelaMaxAllDMD()") }

    func singularityPerform()     { jsAsync("_nativeSingularityPerform()") }
    func singularityIncreaseCap() { jsAsync("_nativeSingularityIncreaseCap()") }
    func singularityDecreaseCap() { jsAsync("_nativeSingularityDecreaseCap()") }

    func laitelaAnnihilate() { jsAsync("_nativeLaitelaAnnihilate()") }
    func laitelaSetAnnihilationMultiplier(_ v: Double) {
        let safe = max(0, v.isFinite ? v : 0)
        jsAsync("_nativeLaitelaSetAnnihilationMultiplier(\(safe))")
    }

    func laitelaSetContinuum(enabled: Bool) {
        jsAsync("_nativeLaitelaSetContinuum(\(enabled ? "true" : "false"))")
    }

    func laitelaToggleAutobuyer(_ name: String, active: Bool) {
        let esc = name.replacingOccurrences(of: "'", with: "\\'")
        jsAsync("_nativeLaitelaToggleAutobuyer('\(esc)', \(active ? "true" : "false"))")
    }

    // MARK: - Lai'tela / Alchemy DEBUG cheats

    #if DEBUG
    func devMaxAllAlchemy() { jsAsync("_nativeDevMaxAllAlchemy()") }
    func devGrantSingularities(_ n: Double) {
        let arg = String(format: "%.15e", max(0, n))
        jsAsync("_nativeDevGrantSingularities(\(arg))")
    }
    func devCompleteLaitelaTier() { jsAsync("_nativeDevCompleteLaitelaTier()") }
    func devSetLaitelaDifficultyTier(_ tier: Int) {
        let clamped = max(0, min(8, tier))
        jsAsync("_nativeDevSetLaitelaDifficultyTier(\(clamped))")
    }
    func devSetDarkMatter(_ n: Double) {
        let arg = String(format: "%.15e", max(0, n))
        jsAsync("_nativeDevSetDarkMatter(\(arg))")
    }
    func devSetDarkEnergy(_ n: Double) {
        let arg = String(format: "%.15e", max(0, n))
        jsAsync("_nativeDevSetDarkEnergy(\(arg))")
    }
    func devSetSingularities(_ n: Double) {
        let arg = String(format: "%.15e", max(0, n))
        jsAsync("_nativeDevSetSingularities(\(arg))")
    }
    func devSetImaginaryMachines(_ n: Double) {
        let arg = String(format: "%.15e", max(0, n))
        jsAsync("_nativeDevSetImaginaryMachines(\(arg))")
    }
    /// Re-seed DMD `amount` fields to 1 (only for unlocked DMDs whose amount
    /// is currently 0). Recovers from the "zero-amount stuck production" bug
    /// where DMD1.amount falls to 0 and DM stops accumulating despite the
    /// dimension being unlocked.
    func devSeedDarkMatterDimensions() {
        jsAsync("_nativeDevSeedDMDs()")
    }
    #endif

    // MARK: - Pelle

    /// Tab-gated bulk-JSON poll. Mirrors the Reality Upgrades / Black Holes
    /// pattern: one `evaluateScript` returning a fully-formatted state blob,
    /// parsed once on the polling thread.
    private func pollPelle(_ state: inout GameState) {
        guard let json = context.evaluateScript("_nativePelleState()")?.toString(),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["ready"] as? Bool) == true else { return }

        if let err = obj["__err"] as? String {
            debugLog("⚠️ pollPelle eval: \(err)")
        }

        var p = state.celestials.pelle
        p.ready = true
        p.isUnlocked = (obj["isUnlocked"] as? Bool) ?? false
        p.canDoom = (obj["canDoom"] as? Bool) ?? false
        p.isDoomed = (obj["isDoomed"] as? Bool) ?? false
        p.remnantsText = (obj["remnantsText"] as? String) ?? "0"
        p.realityShardsText = (obj["realityShardsText"] as? String) ?? "0"
        p.realityShardsPerSecText = (obj["realityShardsPerSecText"] as? String) ?? "0/s"
        p.riftDrainPercentText = (obj["riftDrainPercentText"] as? String) ?? "3%"
        p.showBought = (obj["showBought"] as? Bool) ?? true
        p.glyphMaxLevel = (obj["glyphMaxLevel"] as? Int) ?? 0
        p.glyphRarityText = (obj["glyphRarityText"] as? String) ?? "0%"
        p.specialGlyphEffectText = (obj["specialGlyphEffectText"] as? String) ?? ""
        p.specialGlyphEffectUnlocked = (obj["specialGlyphEffectUnlocked"] as? Bool) ?? false

        // Pre-doom requirements list.
        if let arr = obj["preDoomRequirements"] as? [[String: Any]] {
            p.preDoomRequirements = arr.compactMap { d in
                guard let id = d["id"] as? String else { return nil }
                return PelleRequirementInfo(
                    id: id,
                    label: (d["label"] as? String) ?? "",
                    progressText: (d["progressText"] as? String) ?? "",
                    isMet: (d["isMet"] as? Bool) ?? false
                )
            }
        } else {
            p.preDoomRequirements = []
        }

        // Armageddon block.
        if let a = obj["armageddon"] as? [String: Any] {
            p.armageddon = PelleArmageddonInfo(
                canArmageddon: (a["canArmageddon"] as? Bool) ?? false,
                remnantsGainText: (a["remnantsGainText"] as? String) ?? "0",
                realityShardsRateText: (a["realityShardsRateText"] as? String) ?? "0/s",
                realityShardsRateAfterText: (a["realityShardsRateAfterText"] as? String) ?? "0/s",
                resetSummaryText: (a["resetSummaryText"] as? String) ?? ""
            )
        }

        // Collapsed flags.
        if let c = obj["collapsed"] as? [String: Any] {
            p.collapsed = PelleCollapsedFlags(
                upgrades: (c["upgrades"] as? Bool) ?? false,
                galaxies: (c["galaxies"] as? Bool) ?? false,
                rifts: (c["rifts"] as? Bool) ?? false
            )
        }

        // Strikes (Phase 3).
        if let arr = obj["strikes"] as? [[String: Any]] {
            p.strikes = arr.compactMap { d in
                guard let id = d["id"] as? Int else { return nil }
                return PelleStrikeInfo(
                    id: id,
                    name: (d["name"] as? String) ?? "",
                    hasStrike: (d["hasStrike"] as? Bool) ?? false,
                    requirementText: (d["requirementText"] as? String) ?? "",
                    penaltyText: (d["penaltyText"] as? String) ?? "",
                    rewardText: (d["rewardText"] as? String) ?? "",
                    riftId: (d["riftId"] as? String) ?? ""
                )
            }
        } else {
            p.strikes = []
        }

        // Rifts (Phase 3) — including milestones.
        if let arr = obj["rifts"] as? [[String: Any]] {
            p.rifts = arr.compactMap { d in
                guard let id = d["id"] as? String else { return nil }
                let rawMs = (d["milestones"] as? [[String: Any]]) ?? []
                let milestones: [PelleRiftMilestoneInfo] = rawMs.compactMap { md in
                    guard let mid = md["id"] as? String else { return nil }
                    return PelleRiftMilestoneInfo(
                        id: mid,
                        thresholdPct: (md["thresholdPct"] as? Double) ?? 0,
                        requirementText: (md["requirementText"] as? String) ?? "",
                        effectText: (md["effectText"] as? String) ?? "",
                        isUnlocked: (md["isUnlocked"] as? Bool) ?? false,
                        isDisabled: (md["isDisabled"] as? Bool) ?? false
                    )
                }
                let staticName = (d["name"] as? String) ?? id.capitalized
                let cycledName = (d["cycledName"] as? String) ?? staticName
                let fillName = (d["fillCurrencyName"] as? String) ?? ""
                let cycledFillName = (d["cycledFillCurrencyName"] as? String) ?? fillName
                return PelleRiftInfo(
                    id: id,
                    name: staticName,
                    cycledName: cycledName,
                    fillCurrencyName: fillName,
                    cycledFillCurrencyName: cycledFillName,
                    percentage: (d["percentage"] as? Double) ?? 0,
                    realPercentage: (d["realPercentage"] as? Double) ?? 0,
                    reducedTo: (d["reducedTo"] as? Double) ?? 0,
                    isActive: (d["isActive"] as? Bool) ?? false,
                    isMaxed: (d["isMaxed"] as? Bool) ?? false,
                    isSpendable: (d["isSpendable"] as? Bool) ?? false,
                    hexColor: (d["hexColor"] as? String) ?? "#ffffff",
                    milestones: milestones,
                    currentFillText: (d["currentFillText"] as? String) ?? "",
                    totalFillText: (d["totalFillText"] as? String) ?? "",
                    effects: (d["effects"] as? [String]) ?? []
                )
            }
        } else {
            p.rifts = []
        }

        // Upgrades shop (Phase 4). Both arrays use the shared `PelleUpgradeInfo`
        // shape; the parser is identical for rebuyables vs one-times.
        let parseUpgrade: ([String: Any]) -> PelleUpgradeInfo? = { d in
            guard let id = d["id"] as? String else { return nil }
            return PelleUpgradeInfo(
                id: id,
                name: (d["name"] as? String) ?? "",
                description: (d["description"] as? String) ?? "",
                effectText: (d["effectText"] as? String) ?? "",
                nextEffectText: (d["nextEffectText"] as? String) ?? "",
                costText: (d["costText"] as? String) ?? "",
                costCurrencyName: (d["costCurrencyName"] as? String) ?? "Reality Shards",
                rebuyable: (d["rebuyable"] as? Bool) ?? false,
                boughtAmount: (d["boughtAmount"] as? Int) ?? 0,
                maxAmount: (d["maxAmount"] as? Int) ?? 0,
                isBought: (d["isBought"] as? Bool) ?? false,
                isAffordable: (d["isAffordable"] as? Bool) ?? false,
                isAvailable: (d["isAvailable"] as? Bool) ?? true,
                requirementText: (d["requirementText"] as? String) ?? "",
                timeToAffordText: (d["timeToAffordText"] as? String) ?? ""
            )
        }
        if let arr = obj["rebuyableUpgrades"] as? [[String: Any]] {
            p.rebuyableUpgrades = arr.compactMap(parseUpgrade)
        } else {
            p.rebuyableUpgrades = []
        }
        if let arr = obj["oneTimeUpgrades"] as? [[String: Any]] {
            p.oneTimeUpgrades = arr.compactMap(parseUpgrade)
        } else {
            p.oneTimeUpgrades = []
        }

        // Galaxy Generator (Phase 5).
        if let g = obj["galaxyGenerator"] as? [String: Any] {
            var gg = PelleGalaxyGeneratorInfo()
            gg.panelVisible = (g["panelVisible"] as? Bool) ?? false
            gg.isUnlocked = (g["isUnlocked"] as? Bool) ?? false
            gg.spentGalaxies = (g["spentGalaxies"] as? Double) ?? 0
            gg.generatedGalaxies = (g["generatedGalaxies"] as? Double) ?? 0
            gg.phase = (g["phase"] as? Int) ?? 0
            gg.sacrificeActive = (g["sacrificeActive"] as? Bool) ?? false
            gg.sacrificeProgressText = (g["sacrificeProgressText"] as? String) ?? ""
            gg.galaxiesText = (g["galaxiesText"] as? String) ?? "0"
            gg.capText = (g["capText"] as? String) ?? "0"
            gg.gainPerSecText = (g["gainPerSecText"] as? String) ?? "0/s"
            gg.isCapped = (g["isCapped"] as? Bool) ?? false
            gg.capRiftCycledName = (g["capRiftCycledName"] as? String) ?? ""
            gg.phaseCompletionText = (g["phaseCompletionText"] as? String) ?? ""
            gg.timeToCapText = (g["timeToCapText"] as? String) ?? ""
            gg.generatedGalaxiesText = (g["generatedGalaxiesText"] as? String) ?? "0"
            gg.barFraction = (g["barFraction"] as? Double) ?? 0
            if let arr = g["upgrades"] as? [[String: Any]] {
                gg.upgrades = arr.compactMap { d in
                    guard let id = d["id"] as? String else { return nil }
                    return PelleGalaxyGeneratorUpgradeInfo(
                        id: id,
                        name: (d["name"] as? String) ?? "",
                        bought: (d["bought"] as? Int) ?? 0,
                        costText: (d["costText"] as? String) ?? "",
                        costCurrencyName: (d["costCurrencyName"] as? String) ?? "",
                        effectText: (d["effectText"] as? String) ?? "",
                        nextEffectText: (d["nextEffectText"] as? String) ?? "",
                        isAffordable: (d["isAffordable"] as? Bool) ?? false,
                        timeToAffordText: (d["timeToAffordText"] as? String) ?? ""
                    )
                }
            }
            p.galaxyGenerator = gg
        }

        // Remnant Gain Factors breakdown — mirrors RemnantGainFactor.vue.
        if let arr = obj["remnantGainBreakdown"] as? [[String: Any]] {
            p.remnantGainBreakdown = arr.compactMap { d in
                guard let id = d["id"] as? String else { return nil }
                return PelleRemnantFactorLine(
                    id: id,
                    label: (d["label"] as? String) ?? "",
                    value: (d["value"] as? String) ?? "",
                    isTotal: (d["isTotal"] as? Bool) ?? false
                )
            }
        } else {
            p.remnantGainBreakdown = []
        }

        // Disabled mechanics list (Phase 8). Direct port of PelleEffectsModal.vue.
        if let arr = obj["disabledMechanics"] as? [[String: Any]] {
            p.disabledMechanics = arr.compactMap { d in
                guard let id = d["id"] as? String else { return nil }
                return PelleDisabledMechanicInfo(
                    id: id,
                    label: (d["label"] as? String) ?? "",
                    statusText: (d["statusText"] as? String) ?? "",
                    unlockedByText: (d["unlockedByText"] as? String) ?? ""
                )
            }
        } else {
            p.disabledMechanics = []
        }

        state.celestials.pelle = p
    }

    /// Doom the current Reality. Called from PelleTab's "Doom Your Reality"
    /// confirmation sheet. Triggers Pelle's `initial` quote on success.
    func doomReality() { jsAsync("_nativeDoomReality()") }

    /// Trigger Armageddon while doomed. Default `gainStuff = true` (gain
    /// remnants); the JS-side initializeRun path uses `false` internally.
    func pelleArmageddon(gainStuff: Bool = true) {
        jsAsync("_nativePelleArmageddon(\(gainStuff ? "true" : "false"))")
    }

    /// Toggle a Pelle rift active. Web caps active rifts at 2 — exceeding
    /// triggers a `GameUI.notify.error` on the JS side, which surfaces as
    /// an iOS toast.
    func togglePelleRift(_ riftId: String) {
        let escaped = riftId.replacingOccurrences(of: "\"", with: "\\\"")
        jsAsync("_nativeTogglePelleRift(\"\(escaped)\")")
    }

    /// Single-purchase a Pelle upgrade (rebuyable or one-time). The id is
    /// the rebuyable's config key for rebuyables and the numeric id stringified
    /// for one-times — `_findPelleUpgrade` matches by `String(u.id)`.
    func buyPelleUpgrade(_ id: String) {
        let escaped = id.replacingOccurrences(of: "\"", with: "\\\"")
        jsAsync("_nativeBuyPelleUpgrade(\"\(escaped)\")")
    }

    /// Buy as many of a rebuyable as currently affordable.
    func buyPelleRebuyableMax(_ id: String) {
        let escaped = id.replacingOccurrences(of: "\"", with: "\\\"")
        jsAsync("_nativeBuyPelleRebuyableMax(\"\(escaped)\")")
    }

    /// Toggle the "show bought" flag in Pelle's upgrade panel.
    func togglePelleShowBought() {
        jsAsync("_nativeTogglePelleShowBought()")
    }

    /// Buy one Galaxy Generator upgrade. `id` is the iOS-side display key
    /// (`additive`, `multiplicative`, `antimatterMult`, `ipMult`, `epMult`);
    /// the JS bridge maps to web's slightly differently-cased keys.
    func buyGalaxyGenUpgrade(_ id: String) {
        let escaped = id.replacingOccurrences(of: "\"", with: "\\\"")
        jsAsync("_nativeBuyGalaxyGenUpgrade(\"\(escaped)\")")
    }

    /// Begin draining the cap rift to advance the Galaxy Generator phase.
    func startGalaxyGenSacrifice() {
        jsAsync("_nativeStartGalaxyGenSacrifice()")
    }

    /// Flip `player.celestials.pelle.galaxyGenerator.unlocked` — the in-panel
    /// "Unlock the Galaxy Generator" action. Mirrors web
    /// `PelleGalaxyGeneratorPanel.vue` `unlock()`.
    func unlockGalaxyGenerator() {
        jsAsync("_nativeUnlockGalaxyGenerator()")
    }
}
