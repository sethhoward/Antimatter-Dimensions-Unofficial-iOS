//
//  GameEngine+Speedrun.swift
//  AntiMatter
//
//  Speedrun Mode: JS bridge injection, per-tick state polling, and the
//  destructive `startSpeedrun` lifecycle (mirrors `hardReset`'s 7-step dance).
//
//  All JS-side work goes through speedrun-helpers.js (loaded by
//  setupSpeedrunHelpers, called from finishStartup / importSave / hardReset /
//  slot-switch / backup-restore — the same 7 save-lifecycle entry points as
//  the other helper scripts).
//

import JavaScriptCore
import Foundation
import UIKit

extension GameEngine {

    // MARK: - JS helpers injection

    /// Injects the speedrun helpers (`_nativeSpeedrunQuick`,
    /// `_nativeSpeedrunHistoryState`, `_nativeSpeedrunPrepare`, etc.) from
    /// `speedrun-helpers.js`. Idempotent. Must run on jsQueue after
    /// `cacheJSRefs`. Re-injected after any teardown/reboot path so the
    /// helpers always reference the current `player`.
    func setupSpeedrunHelpers() {
        guard let url = Bundle.main.url(forResource: "speedrun-helpers", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("🔴 GameEngine: missing speedrun-helpers.js in app bundle")
            return
        }
        _ = context.evaluateScript(source)
    }

    // MARK: - Quick state (per-tick)

    /// Polls the lightweight per-tick state. Cheap — single JSON eval +
    /// JSONSerialization parse. Called from `pollDirect()`'s always-on block.
    /// Updates `engine.speedrunQuick` on main.
    func pollSpeedrunQuick() {
        let json = context.evaluateScript("_nativeSpeedrunQuick()")?.toString() ?? ""
        let parsed = Self.parseSpeedrunQuick(json: json)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.speedrunQuick != parsed { self.speedrunQuick = parsed }
        }
    }

    private static func parseSpeedrunQuick(json: String) -> SpeedrunQuickState {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SpeedrunQuickState()
        }
        var s = SpeedrunQuickState()
        s.isUnlocked            = (obj["isUnlocked"] as? Bool) ?? false
        s.isActive              = (obj["isActive"] as? Bool) ?? false
        s.hasStarted            = (obj["hasStarted"] as? Bool) ?? false
        s.canShowOptionsEntry   = (obj["canShowOptionsEntry"] as? Bool) ?? false
        s.fullGameCompletions   = (obj["fullGameCompletions"] as? Int) ?? 0
        s.name                  = (obj["name"] as? String) ?? ""
        s.elapsedMs             = (obj["elapsedMs"] as? Double) ?? 0
        s.mostRecentId          = (obj["mostRecentId"] as? Int) ?? 0
        s.mostRecentMs          = (obj["mostRecentMs"] as? Double) ?? 0
        s.mostRecentName        = (obj["mostRecentName"] as? String) ?? ""
        return s
    }

    // MARK: - History (on-demand)

    /// Fetches the full per-milestone history. Dispatches on main.
    /// Used by the Statistics tab's Speedrun section.
    func loadSpeedrunHistory(completion: @escaping (SpeedrunHistoryState) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let json = self.context.evaluateScript("_nativeSpeedrunHistoryState()")?.toString() ?? ""
                let state = Self.parseSpeedrunHistory(json: json)
                DispatchQueue.main.async { completion(state) }
            }
        }
    }

    private static func parseSpeedrunHistory(json: String) -> SpeedrunHistoryState {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SpeedrunHistoryState()
        }
        var s = SpeedrunHistoryState()
        s.ready             = (obj["ready"] as? Bool) ?? false
        s.isActive          = (obj["isActive"] as? Bool) ?? false
        s.hasStarted        = (obj["hasStarted"] as? Bool) ?? false
        s.isSegmented       = (obj["isSegmented"] as? Bool) ?? false
        s.usedSTD           = (obj["usedSTD"] as? Bool) ?? false
        s.name              = (obj["name"] as? String) ?? ""
        s.startDate         = (obj["startDate"] as? Double) ?? 0
        s.offlineTimeUsedMs = (obj["offlineTimeUsedMs"] as? Double) ?? 0
        s.realTimePlayedMs  = (obj["realTimePlayedMs"] as? Double) ?? 0
        if let arr = obj["milestones"] as? [[String: Any]] {
            s.milestones = arr.compactMap { row in
                guard let id = row["id"] as? Int, let name = row["name"] as? String else { return nil }
                let ms = (row["timeMs"] as? Double) ?? 0
                return SpeedrunMilestoneInfo(id: id, name: name, timeMs: ms)
            }
        }
        return s
    }

    // MARK: - Actions

    /// Normalises the raw user-entered name via `Speedrun.generateName` —
    /// strips whitespace, generates "AD Player #NNNNNN" when empty, truncates
    /// > 40 chars. Sync; cheap (a single JS call).
    func generateSpeedrunName(_ raw: String) -> String {
        // Escape the user string for safe JS embedding.
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let script = "_nativeSpeedrunGenerateName(\"\(escaped)\")"
        var result: String = ""
        // Sync because this is called from the modal Confirm tap — modal stays
        // up until we return.
        jsQueue.sync { [weak self] in
            guard let self else { return }
            autoreleasepool {
                result = self.context.evaluateScript(script)?.toString() ?? ""
            }
        }
        return result
    }

    /// Starts a Speedrun. HARD-RESETS the save. Mirrors `hardReset`'s exact
    /// 7-step teardown/reboot dance so cached JSValue refs get rebuilt
    /// against the fresh `player`.
    ///
    /// - Parameters:
    ///   - name: pre-normalised via `generateSpeedrunName(_:)`.
    ///   - sidebarState: used to navigate to Antimatter Dimensions on success.
    ///   - completion: dispatched on main with success/failure.
    func startSpeedrun(name: String, sidebarState: SidebarState,
                       completion: @escaping (Bool) -> Void) {
        // Eager main-thread cleanup — same pattern as hardReset so the
        // sidebar's progression tabs collapse instantly when the user
        // confirms, instead of waiting for the next poll.
        DispatchQueue.main.async { [self] in
            self.resetUnlockFlags()
            sidebarState.selectSubtab(.antimatterDimensions, in: .dimensions, engine: self)
        }

        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        jsQueue.async { [self] in
            autoreleasepool {
                // 1. Stop timers.
                self.stopAllGameTimersJS()
                // 2. Hard-reset via Speedrun.prepareSave (which itself
                //    calls NG.restartWithCarryover + GameStorage.save).
                let okVal = self.context.evaluateScript("_nativeSpeedrunPrepare(\"\(escaped)\")")
                let ok = (okVal?.toBool() ?? false)
                if !ok {
                    // Failure path — restart timers so the live game keeps
                    // ticking, then bail.
                    self.restartAllGameTimersJS()
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                // 3. Backup-timer hygiene — mirrors hardReset.
                self.context.evaluateScript("""
                    if (typeof GameStorage !== 'undefined') {
                        if (typeof GameStorage.loadBackupTimes === 'function') GameStorage.loadBackupTimes();
                        if (typeof GameStorage.resetBackupTimer === 'function') GameStorage.resetBackupTimer();
                    }
                """)
                // 4. Clear stale cold-start lastUpdate (Speedrun.prepareSave's
                //    save() writes the new player.lastUpdate). The next
                //    save tick syncs am_lastUpdate fresh.
                UserDefaults.standard.removeObject(forKey: "am_lastUpdate")
                // 5. Restart timers.
                self.restartAllGameTimersJS()
                self.context.evaluateScript("player.options.hibernationCatchup = false;")
                // 6. Re-cache refs + re-inject helpers (every single one — same
                //    7-site invariant as hardReset / importSave).
                self.cacheJSRefs()
                self.setupNewsHelpers()
                self.setupCelestialHelpers()
                self.setupGameEndHelpers()
                self.setupAutomatorHelpers()
                self.setupSaveHelpers()
                self.setupGlyphPresetHelpers()
                self.setupSpeedrunHelpers()
                self.setupStatisticsAndRelatedHelpers()
                // 7. Poll fresh state.
                self.pollDirect()
                DispatchQueue.main.async {
                    // Re-zero unlock flags LAST on main — see hardReset for
                    // the explanation. A pre-reset CADisplayLink poll's
                    // commit closure could otherwise re-assert progression
                    // tab visibility after Speedrun.prepareSave wiped it.
                    self.resetUnlockFlags()
                    sidebarState.selectSubtab(.antimatterDimensions, in: .dimensions, engine: self)
                    self.enqueueToast(type: "info",
                                      text: String(localized: "Speedrun started"))
                    completion(true)
                }
            }
        }
    }
}
