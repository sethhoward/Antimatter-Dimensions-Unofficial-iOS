//
//  CloudSaveService.swift
//  AntiMatter
//
//  Phase 2 of the iCloud / multi-save / Handoff plan: iCloud sync via
//  NSUbiquitousKeyValueStore.
//
//  Safety principles (non-negotiable, per plan):
//  • Opt-in, off by default (UserDefaults-backed `syncEnabled`).
//  • Local save is always authoritative. Cloud never silently overwrites
//    local unless the user explicitly chose "Use cloud" in a conflict.
//  • Per-slot independent. A conflict on slot 0 never touches slot 1.
//  • Upload is debounced and piggybacks on GameStorage.save (via engine's
//    saveSignal) — no separate polling loop.
//  • Comparison reuses the web game's ProgressChecker logic (composite
//    stage + realTimePlayed + filename + hash) via _nativeCompareSaves in
//    save-helpers.js.
//  • `writerUUID` is a per-installation ID baked into every cloud write so
//    we can ignore our own echoed external-change notifications.
//
//  Cloud key layout (NSUbiquitousKeyValueStore):
//    cloud.save.{slot}  String — exported save (same format as clipboard)
//    cloud.meta.{slot}  String JSON: { hash, writerUUID, writtenAt,
//                                       saveFileName, realTimePlayed,
//                                       compositeProgress, stage }
//
//  UserDefaults keys:
//    cloud.syncEnabled       Bool
//    cloud.writerUUID        String (generated once)
//    cloud.lastSeenHash.{s}  String — hash of cloud blob we last pulled;
//                                     used to detect another device writing
//                                     since.
//

import Foundation
import CryptoKit
import UIKit

@Observable
@MainActor
final class CloudSaveService {

    // MARK: - Public state

    /// Whether the user has enabled iCloud sync (UserDefaults-backed).
    var syncEnabled: Bool {
        didSet {
            guard oldValue != syncEnabled else { return }
            UserDefaults.standard.set(syncEnabled, forKey: Keys.syncEnabled)
        }
    }

    /// Is iCloud infrastructure available on this device (user signed in,
    /// KVS reachable)? Purely an availability probe — doesn't mean we'll
    /// upload unless `syncEnabled` is also true.
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Timestamp of the last successful upload for the active slot. nil
    /// when none yet this session.
    var lastUploadedAt: Date?

    /// Timestamp of the last successful download/compare. nil when none.
    var lastSyncedAt: Date?

    /// Non-nil while a conflict is awaiting user resolution. Driven by the
    /// Options UI and the foreground / external-change handlers.
    var pendingConflict: CloudSaveConflict?

    /// Set while an upload is in-flight so the UI can show a spinner.
    var isUploading: Bool = false

    /// Set while a sync (download + compare) is in-flight.
    var isSyncing: Bool = false

    /// One-time "first enable" decision still pending. When non-nil, the
    /// Options UI presents a sheet asking the user how to resolve the
    /// initial state (local vs cloud both exist, or only one side exists).
    var pendingFirstEnable: FirstEnablePrompt?

    // MARK: - Dependencies

    private unowned let engine: GameEngine
    private let kvs = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    /// Stable per-installation identifier embedded in every cloud write.
    /// Lets us tell our own echoes apart from writes coming from another
    /// device (which would otherwise appear via the KVS change
    /// notification after we ourselves just wrote).
    private let writerUUID: String

    /// Human-readable device name stored in cloud meta so conflict UI can
    /// say "Your iPad wrote this version". `UIDevice.name` is gated by
    /// Apple in recent iOS, so we fall back to `model` if empty.
    private var deviceName: String {
        let n = UIDevice.current.name
        return n.isEmpty ? UIDevice.current.model : n
    }

    /// Timestamp of the most recent successful upload per slot. Used only
    /// for diagnostics; uploads fire on backgrounding and explicit actions,
    /// not on a debounced schedule.
    private var lastUploadForSlot: [Int: Date] = [:]

    // MARK: - Init

    init(engine: GameEngine) {
        self.engine = engine

        self.syncEnabled = defaults.bool(forKey: Keys.syncEnabled)

        if let existing = defaults.string(forKey: Keys.writerUUID) {
            self.writerUUID = existing
        } else {
            let new = UUID().uuidString
            defaults.set(new, forKey: Keys.writerUUID)
            self.writerUUID = new
        }

        // Subscribe to external change notifications — another device
        // pushed to the same iCloud KVS. Handler inspects changed keys and
        // surfaces a conflict if any of them pertain to a slot whose
        // writerUUID differs from ours.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs
        )

        // Ask KVS to pull whatever the server has for this app's container.
        // Synchronous — just enqueues a fetch; results arrive via the
        // external-change notification.
        kvs.synchronize()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Enable / disable

    /// Caller flips the toggle. If both local and cloud have data we ask
    /// the user how to resolve; otherwise we auto-route (upload if only
    /// local exists, download if only cloud, no-op if neither).
    func requestEnableSync(completion: @escaping (Bool) -> Void) {
        guard isAvailable else {
            completion(false)
            engine.enqueueToast(type: "error", text: String(localized: "iCloud isn't available — sign in to iCloud in Settings to enable sync."))
            return
        }

        kvs.synchronize()

        let slot = engine.currentCloudSlotId
        // "Local exists" = the active slot isn't still at the default
        // (10 antimatter, 0 realities/eternities/infinities). Cheap heuristic
        // that avoids deeper state inspection.
        let localExists = engine.antimatter != "10" ||
                          engine.currentIP != "0" ||
                          engine.eternityUnlocked ||
                          engine.infinityUnlocked
        let cloudBlob = kvs.string(forKey: Keys.save(slot))
        let cloudExists = !(cloudBlob?.isEmpty ?? true)

        switch (localExists, cloudExists) {
        case (true, true):
            // Both sides have data — ask the user.
            let cloudMeta = readMeta(slot: slot)
            pendingFirstEnable = FirstEnablePrompt(
                slotId: slot,
                cloudMeta: cloudMeta,
                onResolve: { [weak self] choice in
                    self?.resolveFirstEnable(choice, completion: completion)
                }
            )
        case (true, false):
            // Only local — push it.
            syncEnabled = true
            uploadSlotNow(slot)
            completion(true)
        case (false, true):
            // Only cloud — pull it. Surface as a conflict so the user
            // confirms the overwrite.
            syncEnabled = true
            compareAndSurface(slot: slot, source: .manualSync)
            completion(true)
        case (false, false):
            syncEnabled = true
            completion(true)
        }
    }

    func disableSync() {
        syncEnabled = false
        pendingConflict = nil
        pendingFirstEnable = nil
    }

    private func resolveFirstEnable(_ choice: FirstEnableChoice, completion: @escaping (Bool) -> Void) {
        guard let prompt = pendingFirstEnable else {
            completion(false)
            return
        }
        pendingFirstEnable = nil

        switch choice {
        case .cancel:
            completion(false)
        case .uploadLocal:
            syncEnabled = true
            uploadSlotNow(prompt.slotId)
            completion(true)
        case .downloadCloud:
            syncEnabled = true
            // Treat it like a conflict resolution: user already chose "use cloud".
            applyCloudToLocal(slot: prompt.slotId)
            completion(true)
        }
    }

    // MARK: - Upload (background + explicit only)

    /// Synchronous upload path used by the scenePhase background handler —
    /// the primary cloud push trigger. Runs inline: synchronously exports
    /// the active slot via `jsQueue.sync`, writes both KVS keys, pins the
    /// last-seen hash, and calls `synchronize()` to hint iCloud to flush.
    /// KVS `set()` is local-only (backed by a plist in the container) so
    /// it's fast; iCloud takes care of actually syncing to the server once
    /// the app has backgrounded. Total time budget: well under iOS's ~5-
    /// second pre-suspension window.
    ///
    /// Called AFTER `engine.save()` in the background handler — by then
    /// `player.lastUpdate` has been refreshed and the save reflects the
    /// user's last actions.
    ///
    /// We deliberately don't also push on every autosave tick. The JS core
    /// keeps rolling local backups (8 per slot) which are our real crash
    /// safety net. Cloud is authoritative only in the "resumed on another
    /// device" path, which is exactly what backgrounding signals. On crash
    /// recovery, the cold-start swap compares playtime between local and
    /// cloud and adopts whichever has more — see
    /// `GameEngine.maybeAdoptNewerCloudSaveAtStartup`.
    func uploadCurrentSlotSynchronouslyForBackground() {
        guard syncEnabled, isAvailable else { return }
        let slot = engine.currentCloudSlotId

        guard let blob = engine.exportSlotRawSync(slot), !blob.isEmpty else { return }

        let hash = Self.sha256(blob)

        // Skip the write if we already pushed this exact blob — happens
        // when the user backgrounds immediately after a debounced upload
        // just fired. Avoids a redundant round-trip through iCloud.
        if defaults.string(forKey: Keys.lastSeenHash(slot)) == hash {
            return
        }

        let meta = CloudMetaEnvelope(
            hash: hash,
            writerUUID: writerUUID,
            writtenAt: Date().timeIntervalSince1970,
            deviceName: deviceName,
            saveFileName: "",
            realTimePlayed: 0,
            compositeProgress: 0,
            stage: ""
        )

        kvs.set(blob, forKey: Keys.save(slot))
        if let metaJSON = try? JSONEncoder().encode(meta),
           let metaString = String(data: metaJSON, encoding: .utf8) {
            kvs.set(metaString, forKey: Keys.meta(slot))
        }
        kvs.synchronize()

        defaults.set(hash, forKey: Keys.lastSeenHash(slot))
        lastUploadForSlot[slot] = Date()
        lastUploadedAt = Date()
    }

    /// Async upload used by the first-enable flow, manual "Sync now" /
    /// conflict resolution, and auto-resolution paths that land on
    /// `.uploadLocal`. Runs off the main thread via `exportSlotRaw`'s
    /// jsQueue.async; safe to call at any time — we're not in a
    /// suspension-sensitive window here.
    func uploadSlotNow(_ slot: Int) {
        guard syncEnabled, isAvailable else { return }
        isUploading = true

        engine.exportSlotRaw(slot) { [weak self] blob in
            guard let self else { return }
            guard let blob, !blob.isEmpty else {
                self.isUploading = false
                return
            }

            let hash = Self.sha256(blob)
            let meta = CloudMetaEnvelope(
                hash: hash,
                writerUUID: self.writerUUID,
                writtenAt: Date().timeIntervalSince1970,
                deviceName: self.deviceName,
                saveFileName: "",
                realTimePlayed: 0,
                compositeProgress: 0,
                stage: ""
            )

            // Best-effort: re-read the freshly-exported blob for metadata
            // so the conflict UI has something to show. Defer the actual
            // metadata enrichment — we can always enrich later without
            // breaking the cloud format.
            self.engine.loadSaveSlots { [weak self] snapshot in
                guard let self else { return }
                let enriched = Self.enrichMeta(meta, from: snapshot, slot: slot)
                self.writeUpload(blob: blob, meta: enriched, slot: slot)
            }
        }
    }

    private func writeUpload(blob: String, meta: CloudMetaEnvelope, slot: Int) {
        guard let metaJSON = try? JSONEncoder().encode(meta),
              let metaString = String(data: metaJSON, encoding: .utf8) else {
            isUploading = false
            return
        }

        kvs.set(blob, forKey: Keys.save(slot))
        kvs.set(metaString, forKey: Keys.meta(slot))
        kvs.synchronize()

        // Remember our own hash so an incoming external-change
        // notification with the same hash is recognized as an echo.
        defaults.set(meta.hash, forKey: Keys.lastSeenHash(slot))

        lastUploadForSlot[slot] = Date()
        lastUploadedAt = Date()
        isUploading = false
    }

    // MARK: - Download / compare / conflict

    /// Manual "Sync now" — pulls current cloud state, shows conflict sheet
    /// if the cloud is ahead or diverges from our last-seen hash.
    func syncNow() {
        guard syncEnabled, isAvailable else { return }
        kvs.synchronize()
        compareAndSurface(slot: engine.currentCloudSlotId, source: .manualSync)
    }

    /// Called on app foreground. Pulls iCloud state and surfaces a
    /// conflict only if the cloud save is materially different.
    func handleForegroundReturn() {
        guard syncEnabled, isAvailable else { return }
        kvs.synchronize()
        compareAndSurface(slot: engine.currentCloudSlotId, source: .foreground)
    }

    /// Runs a local-vs-cloud compare and either auto-resolves or, in the
    /// pathological case, surfaces `pendingConflict` for user resolution.
    ///
    /// Auto-resolution policy (the "playtime wins" model):
    /// • `realTimePlayed` only ever increases within a slot; it's the
    ///   canonical measure of "which save represents more gameplay."
    /// • Whichever side has strictly more playtime wins automatically —
    ///   either silently upload local, or silently download cloud.
    /// • Equal playtime (rare; identical device/time) → upload local so
    ///   cloud matches.
    /// • We ONLY prompt when playtime and progress disagree: cloud has
    ///   more playtime but strictly less progression (or vice versa).
    ///   That combination indicates something weird — a hard reset or
    ///   sync corruption — and it's exactly the case where silently
    ///   picking either side could destroy progress.
    ///
    /// De-dup: if we're already presenting a conflict for the same cloud
    /// hash, the second call is a no-op. Prevents the "sheet pops up
    /// twice" glitch when enable-flow + foreground + external-change all
    /// fire for the same cloud state.
    private func compareAndSurface(slot: Int, source: ConflictSource) {
        isSyncing = true
        kvs.synchronize()

        let cloudBlob = kvs.string(forKey: Keys.save(slot)) ?? ""
        let cloudHash = cloudBlob.isEmpty ? nil : Self.sha256(cloudBlob)
        let lastSeenHash = defaults.string(forKey: Keys.lastSeenHash(slot))
        let cloudMeta = readMeta(slot: slot)

        // De-dup: already showing a conflict for this exact cloud blob.
        if let pending = pendingConflict, pending.slotId == slot,
           pending.cloudHash == (cloudHash ?? "") {
            isSyncing = false
            return
        }

        // If cloud is empty there's nothing to conflict on — upload local
        // if we've got it.
        if cloudBlob.isEmpty {
            isSyncing = false
            lastSyncedAt = Date()
            uploadSlotNow(slot)
            return
        }

        // Echo / already-reconciled detection. If the cloud hash matches
        // the last-seen hash we stored on this device, this cloud state
        // is already reflected locally — whether WE wrote it (echo of
        // our own upload) or it came in from another device and we
        // adopted it (cold-start swap, prior conflict resolution).
        // Nothing to do.
        //
        // We intentionally don't gate this on `writerUUID == ours` — the
        // hash match by itself is sufficient evidence that local is in
        // sync with cloud for this blob.
        if let cloudHash, let lastSeen = lastSeenHash, lastSeen == cloudHash {
            isSyncing = false
            lastSyncedAt = Date()
            return
        }

        engine.compareSlotAgainstCloud(
            slotId: slot,
            cloudSaveString: cloudBlob,
            cloudHash: cloudHash ?? "",
            lastSeenHash: lastSeenHash ?? ""
        ) { [weak self] result in
            guard let self else { return }
            self.isSyncing = false
            self.lastSyncedAt = Date()

            guard let result else { return }

            // Re-check de-dup after the async hop: another compare may
            // have landed first and surfaced the same conflict.
            if let pending = self.pendingConflict, pending.slotId == slot,
               pending.cloudHash == (cloudHash ?? "") {
                return
            }

            let resolution = self.autoResolution(for: result)
            switch resolution {
            case .uploadLocal:
                self.uploadSlotNow(slot)

            case .downloadCloud:
                // Cloud strictly ahead and progression agrees — apply
                // silently but toast so the user knows what happened.
                // Pin the last-seen hash first so the resulting saves
                // don't immediately re-trigger a mismatch.
                self.defaults.set(cloudHash ?? "", forKey: Keys.lastSeenHash(slot))
                self.engine.enqueueToast(type: "info", text: String(localized: "Loaded newer save from iCloud"))
                self.applyCloudToLocal(slot: slot, blob: cloudBlob)

            case .prompt:
                self.pendingConflict = CloudSaveConflict(
                    slotId: slot,
                    source: source,
                    comparison: result,
                    cloudHash: cloudHash ?? "",
                    cloudMetaWriter: cloudMeta?.deviceName,
                    cloudBlob: cloudBlob
                )
            }
        }
    }

    /// Decide what to do with a compare result using the "playtime wins"
    /// policy. See `compareAndSurface` for rationale.
    ///
    /// `older` from ProgressChecker: -1 cloud has >= realTimePlayed, +1
    /// local has more, 0 when either side is missing.
    ///
    /// `farther` from ProgressChecker: -1 cloud ahead in composite
    /// progress, +1 local ahead, 0 similar (within 0.05 threshold), -1
    /// also used for cloud-only (local missing) and +1 for local-only.
    private func autoResolution(for r: CloudSaveComparison) -> AutoResolution {
        // One-sided existence — `older` is 0 because one side is nil.
        // Drive off `farther` directly: -1 means cloud-only, +1 means
        // local-only.
        if r.local == nil && r.cloud != nil { return .downloadCloud }
        if r.cloud == nil && r.local != nil { return .uploadLocal }

        switch (r.older, r.farther) {
        // Local has strictly more playtime. Local is the canonical
        // version — progress may have caught up since last cloud push.
        case (1, _):
            return .uploadLocal

        // Cloud has >= playtime AND cloud is ahead or tied in progress.
        // Standard "another device kept playing" case. Apply cloud.
        case (-1, -1), (-1, 0):
            return .downloadCloud

        // Cloud has more playtime BUT local is strictly farther in
        // progress. Pathological — more time played yet less progression
        // suggests something reset on the cloud side. Let the user decide.
        case (-1, 1):
            return .prompt

        // Both zero with both sides present → identical playtime, similar
        // progress. Upload local so cloud matches. Same for any other
        // unexpected combination.
        default:
            return .uploadLocal
        }
    }

    private enum AutoResolution {
        case uploadLocal
        case downloadCloud
        case prompt
    }

    /// User picked "Keep local" in the conflict sheet.
    func resolveConflictKeepLocal() {
        guard let conflict = pendingConflict else { return }
        pendingConflict = nil
        uploadSlotNow(conflict.slotId)
    }

    /// User picked "Use cloud" in the conflict sheet.
    func resolveConflictUseCloud() {
        guard let conflict = pendingConflict else { return }
        pendingConflict = nil
        applyCloudToLocal(slot: conflict.slotId, blob: conflict.cloudBlob)
    }

    func dismissConflict() {
        pendingConflict = nil
    }

    // MARK: - Private: apply cloud → local

    /// Pulls the cloud save for `slot` and hands it to GameEngine to
    /// import (uses the existing importSave path, which stops timers →
    /// deserializes → checkPlayerObject → loadPlayerObject → restarts
    /// timers → caches refs → polls). Same path clipboard import uses.
    private func applyCloudToLocal(slot: Int, blob providedBlob: String? = nil) {
        let blob = providedBlob ?? (kvs.string(forKey: Keys.save(slot)) ?? "")
        guard !blob.isEmpty else {
            engine.enqueueToast(type: "error", text: String(localized: "Cloud slot is empty"))
            return
        }

        // Pin the last-seen hash to the cloud blob we just downloaded so
        // subsequent writes from this device don't detect a spurious
        // mismatch.
        defaults.set(Self.sha256(blob), forKey: Keys.lastSeenHash(slot))

        if slot == engine.currentCloudSlotId {
            // Active slot — go through the existing importSave pipeline
            // so timers, refs, and polling are handled identically to the
            // clipboard-import path.
            engine.importSave(blob)
        } else {
            // Dormant slot — write into saves[slot] directly without
            // touching the active player.
            engine.overwriteDormantSlot(slotId: slot, saveString: blob) { _ in }
        }
    }

    // MARK: - External change handler

    @objc nonisolated private func handleExternalChange(_ notification: Notification) {
        // Extract the Sendable [String] keys before hopping to the main
        // actor — `Notification` / `userInfo` are non-Sendable and can't
        // cross into the @Sendable Task closure.
        let info = notification.userInfo
        let keys = (info?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.syncEnabled else { return }

            // Figure out which slots changed. Only react to save-key
            // changes; meta-only changes are bookkeeping.
            var changedSlots = Set<Int>()
            for key in keys {
                for slot in 0..<3 {
                    if key == Keys.save(slot) {
                        changedSlots.insert(slot)
                    }
                }
            }
            guard !changedSlots.isEmpty else { return }

            // Only surface a conflict for the ACTIVE slot. Changes to
            // dormant slots are interesting but the user isn't playing
            // them; store them silently and the next time they switch
            // there, they'll see the updated state.
            if changedSlots.contains(self.engine.currentCloudSlotId) {
                self.compareAndSurface(slot: self.engine.currentCloudSlotId, source: .externalChange)
            }
        }
    }

    // MARK: - Helpers

    private func readMeta(slot: Int) -> CloudMetaEnvelope? {
        guard let str = kvs.string(forKey: Keys.meta(slot)),
              let data = str.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CloudMetaEnvelope.self, from: data)
    }

    /// SHA-256 of the save string, used by the cloud-sync conflict
    /// detector and (post-Stage-5) by the offline-sim apply path to
    /// pin the last-seen hash after a sim. Internal so call sites
    /// outside this file (notably `GameEngine.applyOfflineSimSave`)
    /// can reuse the same hash function the rest of the cloud
    /// pipeline uses.
    nonisolated static func sha256(_ s: String) -> String {
        let data = Data(s.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func enrichMeta(_ base: CloudMetaEnvelope,
                                    from snapshot: SaveSlotsSnapshot,
                                    slot: Int) -> CloudMetaEnvelope {
        guard let info = snapshot.slots.first(where: { $0.id == slot }) else {
            return base
        }
        return CloudMetaEnvelope(
            hash: base.hash,
            writerUUID: base.writerUUID,
            writtenAt: base.writtenAt,
            deviceName: base.deviceName,
            saveFileName: info.saveFileName,
            realTimePlayed: info.lastUpdate,  // stored as ms; caller can reformat
            compositeProgress: 0,              // filled by JS on next compare
            stage: info.stage
        )
    }

    // MARK: - Keys / types

    private enum Keys {
        static let syncEnabled = "cloud.syncEnabled"
        static let writerUUID = "cloud.writerUUID"
        static func save(_ slot: Int) -> String { "cloud.save.\(slot)" }
        static func meta(_ slot: Int) -> String { "cloud.meta.\(slot)" }
        static func lastSeenHash(_ slot: Int) -> String { "cloud.lastSeenHash.\(slot)" }
    }
}

// MARK: - Models

struct CloudMetaEnvelope: Codable, Equatable {
    let hash: String
    let writerUUID: String
    let writtenAt: TimeInterval   // seconds since 1970
    let deviceName: String
    let saveFileName: String
    let realTimePlayed: Double
    let compositeProgress: Double
    let stage: String
}

/// Raw comparison result coming back from `_nativeCompareSaves`. Mirrors
/// the web's `Cloud.compareSaves` return shape plus metadata for both sides.
struct CloudSaveComparison: Equatable {
    /// -1: cloud is materially ahead. +1: local is ahead. 0: similar.
    let farther: Int
    /// -1: cloud has more realTimePlayed (older?). +1: local does. 0: one missing.
    let older: Int
    let differentName: Bool
    /// True when the cloud blob's hash differs from the one we last pulled —
    /// another device wrote since.
    let hashMismatch: Bool
    let local: CloudSideMeta?
    let cloud: CloudSideMeta?
}

struct CloudSideMeta: Equatable {
    let antimatter: String
    let realities: String
    let eternities: String
    let infinitied: String
    let realTimePlayed: String
    let saveFileName: String
    let lastUpdate: Double
    let stage: String
}

/// Active conflict awaiting user resolution.
struct CloudSaveConflict: Equatable, Identifiable {
    let id = UUID()
    let slotId: Int
    let source: ConflictSource
    let comparison: CloudSaveComparison
    let cloudHash: String
    let cloudMetaWriter: String?
    let cloudBlob: String
}

enum ConflictSource: Equatable {
    case foreground
    case externalChange
    case manualSync
}

struct FirstEnablePrompt: Equatable, Identifiable {
    let id = UUID()
    let slotId: Int
    let cloudMeta: CloudMetaEnvelope?
    let onResolve: @MainActor (FirstEnableChoice) -> Void

    static func == (lhs: FirstEnablePrompt, rhs: FirstEnablePrompt) -> Bool {
        lhs.id == rhs.id
    }
}

enum FirstEnableChoice {
    case uploadLocal
    case downloadCloud
    case cancel
}
