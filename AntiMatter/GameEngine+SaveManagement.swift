//
//  GameEngine+SaveManagement.swift
//  AntiMatter
//
//  Save Management: multi-slot listing + switching + per-slot rolling
//  backups. All JS-side work goes through save-helpers.js (loaded by
//  setupSaveHelpers, called from finishStartup / importSave / hardReset in
//  GameEngine.swift).
//
//  Slot switching and backup restoration follow the same teardown/reboot
//  sequence as importSave(): stop timers, mutate state, restart timers,
//  re-cache JS refs, re-inject helpers, poll.
//

import JavaScriptCore
import Foundation
import UIKit
import CryptoKit

extension GameEngine {

    // MARK: - JS helpers injection

    /// Injects _nativeListSlots / _nativeSwitchSlot / _nativeRenameSlot /
    /// _nativeDeleteSlot / _nativeExportSlot / _nativeListBackups /
    /// _nativeRestoreBackup from save-helpers.js. Must run on jsQueue after
    /// cacheJSRefs(); matches the news/celestial helper pattern.
    ///
    /// Also registers `_nativeSaveTick` — a JS→Swift bridge that bumps
    /// `engine.saveSignal` whenever `GameStorage.save` runs (the JS side
    /// monkey-patches `GameStorage.save` inside save-helpers.js to call
    /// this). SwiftUI views observing `saveSignal` refresh without a
    /// polling timer.
    func setupSaveHelpers() {
        // Register the save-tick callback BEFORE evaluating save-helpers.js
        // so the monkey-patch's guard is idempotent — re-evaluating the file
        // on import/hardReset won't re-wrap a second time, but the native
        // callback closure refreshes to reference the current engine.
        //
        // The save tick is UI-only: it bumps `saveSignal` so SaveSlotsSection
        // and friends re-read their snapshot, and syncs `lastKnownCurrentSlot`
        // so any later cloud operation targets the right slot. Cloud uploads
        // are NOT triggered here — they only happen when the app
        // backgrounds (`uploadCurrentSlotSynchronouslyForBackground`) or on
        // explicit user actions (Sync now, first-enable, conflict resolution).
        // Local autosaves continue as before; the JS core's rolling backup
        // slots are our crash safety net and always run.
        let saveTick: @convention(block) () -> Void = { [weak self] in
            guard let self else { return }
            let slot = Int(self.context.evaluateScript("GameStorage.currentSlot")?.toInt32() ?? 0)
            DispatchQueue.main.async {
                self.saveSignal &+= 1
                self.lastKnownCurrentSlot = slot
            }
        }
        context.setObject(saveTick, forKeyedSubscript: "_nativeSaveTick" as NSString)

        guard let url = Bundle.main.url(forResource: "save-helpers", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("🔴 GameEngine: missing save-helpers.js in app bundle")
            return
        }
        _ = context.evaluateScript(source)
    }

    // MARK: - Reads (fetch on demand, not per-tick)

    /// Fetches a fresh snapshot of all 3 save slots. Dispatches completion on
    /// the main thread. Call on view appear and after any mutating action.
    func loadSaveSlots(completion: @escaping (SaveSlotsSnapshot) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let json = self.context.evaluateScript("_nativeListSlots()")?.toString() ?? "{}"
                let snapshot = Self.parseSlotsSnapshot(json: json)
                DispatchQueue.main.async { completion(snapshot) }
            }
        }
    }

    /// Fetches the 8 rolling backups for the given slot. Backups are stored
    /// per-slot in localStorage; non-active slots can be read safely.
    func loadBackups(for slotId: Int, completion: @escaping (SaveBackupsSnapshot) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let json = self.context.evaluateScript("_nativeListBackups(\(slotId))")?.toString() ?? "{}"
                let snapshot = Self.parseBackupsSnapshot(json: json, slotId: slotId)
                DispatchQueue.main.async { completion(snapshot) }
            }
        }
    }

    // MARK: - Actions

    /// Switch to a different slot. Mirrors the importSave() teardown/reboot
    /// sequence so any cached JSValue refs (dimensions, challenges, etc.) get
    /// rebuilt against the newly-loaded `player`.
    func switchSaveSlot(_ slotId: Int, completion: @escaping (Bool) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                // Stop timers before mutating player
                self.stopAllGameTimersJS()

                let result = self.context.evaluateScript("_nativeSwitchSlot(\(slotId))")?.toString() ?? "error"
                let ok = (result == "ok" || result == "already-active")

                if ok {
                    // Restart timers (matches importSave post-load)
                    self.restartAllGameTimersJS()
                    self.context.evaluateScript("player.options.hibernationCatchup = false;")
                    // Update persisted lastUpdate for cold-start offline detection
                    let lastUpdate = self.context.evaluateScript("player.lastUpdate")?.toDouble() ?? 0
                    if lastUpdate > 0 { UserDefaults.standard.set(lastUpdate, forKey: "am_lastUpdate") }
                    self.cacheJSRefs()
                    self.setupNewsHelpers()
                    self.setupCelestialHelpers()
                    self.setupGameEndHelpers()
                    self.setupAutomatorHelpers()
                    self.setupSaveHelpers()
                    self.setupGlyphPresetHelpers()
                    self.setupSpeedrunHelpers()
                    self.setupStatisticsAndRelatedHelpers()
                    self.pollDirect()
                } else {
                    // Failure path — restart timers so the live game keeps
                    // ticking. Also stops any GameIntervals that a partial
                    // _nativeSwitchSlot left running.
                    self.restartAllGameTimersJS()
                }

                DispatchQueue.main.async {
                    if ok {
                        // Reset unlock flags AFTER pollDirect's commit so this
                        // runs LAST on main — matches hardReset /
                        // startSpeedrun. The sticky-true block also self-skips
                        // via `unlockFlagsGen`, but ordering this last keeps
                        // the code consistent.
                        self.resetUnlockFlags()
                        self.enqueueToast(type: "info", text: String(localized: "Loaded Slot \(slotId + 1)"))
                    } else if result == "invalid-id" {
                        self.enqueueToast(type: "error", text: String(localized: "Invalid slot"))
                    } else {
                        self.enqueueToast(type: "error", text: String(localized: "Could not switch slot"))
                    }
                    completion(ok)
                }
            }
        }
    }

    /// Rename a slot's saveFileName. Works for active or dormant slots; empty
    /// slots are rejected (nothing to name).
    func renameSaveSlot(_ slotId: Int, name: String, completion: @escaping (Bool) -> Void) {
        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let result = self.context.evaluateScript("_nativeRenameSlot(\(slotId), \"\(escaped)\")")?.toString() ?? "error"
                let ok = (result == "ok")
                DispatchQueue.main.async {
                    if !ok, result == "empty-slot" {
                        self.enqueueToast(type: "error", text: String(localized: "Slot is empty"))
                    } else if !ok {
                        self.enqueueToast(type: "error", text: String(localized: "Could not rename slot"))
                    }
                    completion(ok)
                }
            }
        }
    }

    /// Delete a dormant slot. The active slot cannot be deleted — the user
    /// must switch away first (guarded both in JS and in the UI).
    func deleteSaveSlot(_ slotId: Int, completion: @escaping (Bool) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let result = self.context.evaluateScript("_nativeDeleteSlot(\(slotId))")?.toString() ?? "error"
                let ok = (result == "ok")
                DispatchQueue.main.async {
                    if result == "active-slot" {
                        self.enqueueToast(type: "error", text: String(localized: "Switch to another slot first"))
                    } else if !ok {
                        self.enqueueToast(type: "error", text: String(localized: "Could not delete slot"))
                    } else {
                        self.enqueueToast(type: "info", text: String(localized: "Slot \(slotId + 1) deleted"))
                    }
                    completion(ok)
                }
            }
        }
    }

    /// Serialize the given slot and copy to the system pasteboard. Mirrors
    /// `exportSave()` but scoped to an arbitrary slot — for the active slot
    /// the JS helper applies the same Speedrun.setSegmented(true) tweak as
    /// `exportModifiedSave`.
    func exportSaveSlot(_ slotId: Int) {
        exportSlotRaw(slotId) { [weak self] serialized in
            guard let self else { return }
            if let serialized, !serialized.isEmpty {
                UIPasteboard.general.string = serialized
                self.enqueueToast(type: "info", text: String(localized: "Slot \(slotId + 1) exported"))
            } else {
                self.enqueueToast(type: "error", text: String(localized: "Slot is empty"))
            }
        }
    }

    /// Like `exportSaveSlot` but returns the raw serialized save string via
    /// completion instead of writing to the pasteboard. Used by
    /// `CloudSaveService` for uploads.
    func exportSlotRaw(_ slotId: Int, completion: @escaping (String?) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let serialized = self.context.evaluateScript("_nativeExportSlot(\(slotId))")?.toString() ?? ""
                DispatchQueue.main.async {
                    completion(serialized.isEmpty ? nil : serialized)
                }
            }
        }
    }

    /// Synchronous slot export — used by the app-backgrounding path where
    /// we need the serialized blob before iOS suspends the process and
    /// can't wait on an async completion. Uses `jsQueue.sync` (matches
    /// `engine.save()`'s pattern). Returns nil if the slot is empty.
    func exportSlotRawSync(_ slotId: Int) -> String? {
        var result: String?
        jsQueue.sync { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let serialized = self.context.evaluateScript("_nativeExportSlot(\(slotId))")?.toString() ?? ""
                if !serialized.isEmpty { result = serialized }
            }
        }
        return result
    }

    /// Read the currently-active slot index from `GameStorage.currentSlot`.
    /// Dispatches to jsQueue and returns on main. CloudSaveService reads
    /// `engine.currentCloudSlotId` which returns a cached value that poll
    /// updates — see `lastKnownCurrentSlot` on GameEngine.
    var currentCloudSlotId: Int {
        lastKnownCurrentSlot
    }

    /// Compare a local slot against a candidate cloud save blob. Wraps the
    /// `_nativeCompareSaves` JS helper; runs on jsQueue, returns on main.
    /// Completion receives nil if the JS side reports an error.
    func compareSlotAgainstCloud(slotId: Int,
                                 cloudSaveString: String,
                                 cloudHash: String,
                                 lastSeenHash: String,
                                 completion: @escaping (CloudSaveComparison?) -> Void) {
        let escapedSave = cloudSaveString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let escapedHash = cloudHash
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedLastSeen = lastSeenHash
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                // Bail silently if save-helpers.js hasn't been injected yet.
                // This happens when a KVS external-change notification fires
                // between offline-simulation batches but before
                // `finishStartup()` has run `setupSaveHelpers()`. The next
                // trigger (scenePhase change, manual Sync now, or a fresh
                // external change) will re-run the compare when helpers
                // exist.
                let helpersReady = self.context
                    .evaluateScript("typeof _nativeCompareSaves === 'function'")?
                    .toBool() ?? false
                guard helpersReady else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                let script = """
                    _nativeCompareSaves(\(slotId), `\(escapedSave)`, "\(escapedHash)", "\(escapedLastSeen)")
                """
                let json = self.context.evaluateScript(script)?.toString() ?? ""
                let parsed = Self.parseCompareResult(json: json)
                DispatchQueue.main.async { completion(parsed) }
            }
        }
    }

    /// Cold-start cloud swap. Called from `start()` on jsQueue BEFORE
    /// running the offline simulation.
    ///
    /// Decision rule: "whichever save has more playtime wins."
    /// `realTimePlayed` only ever increases within a slot, so it's the
    /// canonical arbiter — robust against clock drift, robust against the
    /// crash-recovery case where a device died before pushing (local has
    /// MORE playtime than cloud, local should win) AND the
    /// resumed-on-other-device case (cloud has more playtime, cloud wins).
    ///
    /// When cloud wins we import the cloud blob now so offline progress
    /// is computed against the right baseline, rather than simulating
    /// against stale local and overwriting seconds later.
    ///
    /// Returns the (possibly updated) lastUpdate and whether we swapped.
    /// MUST be called on jsQueue; blocks briefly on KVS reads and a JS
    /// import, so keep it narrow.
    func maybeAdoptNewerCloudSaveAtStartup(localLastUpdateMs: Double) -> (Double, Bool) {
        // Gate on sync-enabled + iCloud availability, checked directly
        // from UserDefaults / FileManager so we don't need to touch the
        // (main-actor) cloud service from the JS queue.
        let syncEnabled = UserDefaults.standard.bool(forKey: "cloud.syncEnabled")
        guard syncEnabled else { return (localLastUpdateMs, false) }
        guard FileManager.default.ubiquityIdentityToken != nil else { return (localLastUpdateMs, false) }

        let kvs = NSUbiquitousKeyValueStore.default
        kvs.synchronize()

        let slotId = Int(context.evaluateScript("GameStorage.currentSlot")?.toInt32() ?? 0)
        let key = "cloud.save.\(slotId)"
        guard let cloudBlob = kvs.string(forKey: key), !cloudBlob.isEmpty else {
            return (localLastUpdateMs, false)
        }

        // Deserialize just enough to read the cloud save's realTimePlayed
        // and lastUpdate. Cheap — we avoid the full import unless we're
        // actually going to use the cloud save.
        let escaped = cloudBlob
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let probeJSON = context.evaluateScript("""
            (function() {
                try {
                    var parsed = GameSaveSerializer.deserialize(`\(escaped)`);
                    if (!parsed) return '{}';
                    var rtp = (parsed.records && parsed.records.realTimePlayed) || 0;
                    return JSON.stringify({
                        realTimePlayed: Number(rtp),
                        lastUpdate: Number(parsed.lastUpdate || 0)
                    });
                } catch (e) { return '{}'; }
            })()
        """)?.toString() ?? "{}"

        guard let probeData = probeJSON.data(using: .utf8),
              let probe = try? JSONSerialization.jsonObject(with: probeData) as? [String: Any],
              let cloudRTP = probe["realTimePlayed"] as? Double,
              let cloudLastUpdate = probe["lastUpdate"] as? Double,
              cloudRTP > 0 else {
            return (localLastUpdateMs, false)
        }

        // Local's realTimePlayed — the currently-loaded player's. JS
        // init() just finished so this is the on-disk slot's state.
        let localRTP = context
            .evaluateScript("(player.records && player.records.realTimePlayed) || 0")?
            .toDouble() ?? 0

        // Playtime-wins: only swap if cloud has strictly more playtime.
        // 1-second threshold so autosave-level drift doesn't flip the
        // result on every launch.
        guard cloudRTP > localRTP + 1000 else {
            return (localLastUpdateMs, false)
        }

        debugLog("COLD START: cloud playtime \(Int(cloudRTP))ms > local \(Int(localRTP))ms — adopting cloud save")

        // Cloud wins — import it. We're mid-startup so timers haven't
        // been started yet; we just need the player object swapped in.
        // Matches the core of importSave's JS logic but skips the timer
        // teardown/reboot (nothing to tear down).
        let importResult = context.evaluateScript("""
            (function() {
                try {
                    var parsed = GameSaveSerializer.deserialize(`\(escaped)`);
                    if (!parsed) return 'invalid';
                    if (typeof GameStorage.checkPlayerObject === 'function') {
                        var err = GameStorage.checkPlayerObject(parsed);
                        if (err !== '') return 'invalid';
                    }
                    // Don't run JS-side offline sim during import — Swift
                    // handles offline sim after this returns.
                    GameStorage.offlineEnabled = false;
                    GameStorage.import(`\(escaped)`);
                    return 'ok';
                } catch (e) { return 'error'; }
            })()
        """)?.toString() ?? "error"

        guard importResult == "ok" else {
            debugLog("COLD START: cloud swap aborted — import returned \(importResult)")
            return (localLastUpdateMs, false)
        }

        // Pin the last-seen hash so the subsequent foreground cloud check
        // recognizes this as the canonical cloud state and doesn't
        // surface a spurious conflict.
        let hash = sha256String(cloudBlob)
        UserDefaults.standard.set(hash, forKey: "cloud.lastSeenHash.\(slotId)")

        // Update am_lastUpdate to the cloud save's timestamp so the
        // offline-gap recompute in start() uses the right baseline.
        UserDefaults.standard.set(cloudLastUpdate, forKey: "am_lastUpdate")

        return (cloudLastUpdate, true)
    }

    private func sha256String(_ s: String) -> String {
        // Matches CloudSaveService.sha256 so both sides compute the same
        // hash for the same blob.
        let data = Data(s.utf8)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Write a save blob directly into a dormant (non-active) slot. Uses
    /// `GameStorage.overwriteSlot`. No timer teardown/reboot needed because
    /// we're not touching the active player.
    func overwriteDormantSlot(slotId: Int, saveString: String, completion: @escaping (Bool) -> Void) {
        let escaped = saveString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        jsQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            autoreleasepool {
                // Deserialize + validate before touching saves[]. If the
                // blob is malformed we refuse rather than trash the slot.
                let result = self.context.evaluateScript("""
                    (function() {
                        if (typeof GameSaveSerializer === 'undefined') return 'no-serializer';
                        var parsed = GameSaveSerializer.deserialize(`\(escaped)`);
                        if (!parsed) return 'invalid-format';
                        if (typeof GameStorage.checkPlayerObject === 'function') {
                            var err = GameStorage.checkPlayerObject(parsed);
                            if (err !== '') return 'invalid-save';
                        }
                        GameStorage.overwriteSlot(\(slotId), parsed);
                        return 'ok';
                    })()
                """)?.toString() ?? "error"

                DispatchQueue.main.async { completion(result == "ok") }
            }
        }
    }

    /// Restore a backup into the active slot. The UI forces a switch to the
    /// target slot first, so by the time we're here `slotId` should match
    /// `GameStorage.currentSlot`. Teardown/reboot matches importSave().
    func restoreBackup(slotId: Int, backupId: Int, completion: @escaping (Bool) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                self.stopAllGameTimersJS()
                let result = self.context.evaluateScript("_nativeRestoreBackup(\(slotId), \(backupId))")?.toString() ?? "error"
                let ok = (result == "ok")
                if ok {
                    self.restartAllGameTimersJS()
                    self.context.evaluateScript("player.options.hibernationCatchup = false;")
                    let lastUpdate = self.context.evaluateScript("player.lastUpdate")?.toDouble() ?? 0
                    if lastUpdate > 0 { UserDefaults.standard.set(lastUpdate, forKey: "am_lastUpdate") }
                    self.cacheJSRefs()
                    self.setupNewsHelpers()
                    self.setupCelestialHelpers()
                    self.setupGameEndHelpers()
                    self.setupAutomatorHelpers()
                    self.setupSaveHelpers()
                    self.setupGlyphPresetHelpers()
                    self.setupSpeedrunHelpers()
                    self.setupStatisticsAndRelatedHelpers()
                    self.pollDirect()
                } else {
                    // Timers were stopped but we didn't reload — restart so the
                    // user's live game keeps ticking even if the restore failed.
                    // Also stops any GameIntervals that _nativeRestoreBackup
                    // started via loadPlayerObject before throwing.
                    self.restartAllGameTimersJS()
                }

                DispatchQueue.main.async {
                    if ok {
                        // Reset unlock flags AFTER pollDirect's commit so this
                        // runs LAST on main — matches hardReset /
                        // startSpeedrun. The sticky-true block also self-skips
                        // via `unlockFlagsGen`, but ordering this last keeps
                        // the code consistent.
                        self.resetUnlockFlags()
                    }
                    switch result {
                    case "ok":
                        self.enqueueToast(type: "info", text: String(localized: "Backup restored"))
                    case "not-active-slot":
                        self.enqueueToast(type: "error", text: String(localized: "Switch to that slot first"))
                    case "empty-backup":
                        self.enqueueToast(type: "error", text: String(localized: "Backup is empty"))
                    case "invalid-save":
                        self.enqueueToast(type: "error", text: String(localized: "Backup is corrupted"))
                    default:
                        self.enqueueToast(type: "error", text: String(localized: "Could not restore backup"))
                    }
                    completion(ok)
                }
            }
        }
    }

    // MARK: - Parsing

    private static func parseSlotsSnapshot(json: String) -> SaveSlotsSnapshot {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .empty
        }
        let current = (obj["current"] as? Int) ?? 0
        let rawSlots = (obj["slots"] as? [[String: Any]]) ?? []
        let slots: [SaveSlotInfo] = rawSlots.compactMap { d in
            guard let id = d["id"] as? Int else { return nil }
            return SaveSlotInfo(
                id: id,
                isEmpty: (d["isEmpty"] as? Bool) ?? true,
                isActive: (d["isActive"] as? Bool) ?? false,
                saveFileName: (d["saveFileName"] as? String) ?? "",
                antimatter: (d["antimatter"] as? String) ?? "0",
                realities: (d["realities"] as? String) ?? "0",
                eternities: (d["eternities"] as? String) ?? "0",
                infinitied: (d["infinitied"] as? String) ?? "0",
                realTimePlayed: (d["realTimePlayed"] as? String) ?? "0s",
                lastUpdate: (d["lastUpdate"] as? Double) ?? 0,
                stage: (d["stage"] as? String) ?? "Empty"
            )
        }
        return SaveSlotsSnapshot(current: current, slots: slots)
    }

    fileprivate static func parseCompareResult(json: String) -> CloudSaveComparison? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if obj["error"] != nil { return nil }

        func parseSide(_ d: [String: Any]?) -> CloudSideMeta? {
            guard let d else { return nil }
            return CloudSideMeta(
                antimatter: (d["antimatter"] as? String) ?? "0",
                realities: (d["realities"] as? String) ?? "0",
                eternities: (d["eternities"] as? String) ?? "0",
                infinitied: (d["infinitied"] as? String) ?? "0",
                realTimePlayed: (d["realTimePlayed"] as? String) ?? "0s",
                saveFileName: (d["saveFileName"] as? String) ?? "",
                lastUpdate: (d["lastUpdate"] as? Double) ?? 0,
                stage: (d["stage"] as? String) ?? ""
            )
        }

        return CloudSaveComparison(
            farther: (obj["farther"] as? Int) ?? 0,
            older: (obj["older"] as? Int) ?? 0,
            differentName: (obj["differentName"] as? Bool) ?? false,
            hashMismatch: (obj["hashMismatch"] as? Bool) ?? false,
            local: parseSide(obj["local"] as? [String: Any]),
            cloud: parseSide(obj["cloud"] as? [String: Any])
        )
    }

    private static func parseBackupsSnapshot(json: String, slotId: Int) -> SaveBackupsSnapshot {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .empty(slotId: slotId)
        }
        let rawBackups = (obj["backups"] as? [[String: Any]]) ?? []
        let backups: [SaveBackupInfo] = rawBackups.compactMap { d in
            guard let backupId = d["backupId"] as? Int else { return nil }
            return SaveBackupInfo(
                backupId: backupId,
                type: (d["type"] as? String) ?? "online",
                intervalLabel: (d["intervalLabel"] as? String) ?? "",
                isEmpty: (d["isEmpty"] as? Bool) ?? true,
                antimatter: (d["antimatter"] as? String) ?? "0",
                realities: (d["realities"] as? String) ?? "0",
                eternities: (d["eternities"] as? String) ?? "0",
                realTimePlayed: (d["realTimePlayed"] as? String) ?? "0s",
                stage: (d["stage"] as? String) ?? "Empty",
                date: (d["date"] as? Double) ?? 0
            )
        }
        return SaveBackupsSnapshot(slotId: slotId, backups: backups)
    }
}
