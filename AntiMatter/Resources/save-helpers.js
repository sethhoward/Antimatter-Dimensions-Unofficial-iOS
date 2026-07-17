// save-helpers.js
//
// JS-side support for the iOS Save Management UI (slots + backups).
// Injected by GameEngine+SaveManagement.setupSaveHelpers(). Called from
// finishStartup / importSave / hardReset, the same lifecycle points as
// setupNewsHelpers / setupCelestialHelpers.
//
// All functions defensively guard against missing symbols so they degrade
// safely on older saves or before cacheJSRefs() has run. Return values are
// always JSON strings (or simple status strings) so the Swift side only has
// to JSONSerialization.parse once per call.

(function () {
    "use strict";

    // ---- Helpers -------------------------------------------------------

    // Return the slot's player-object regardless of whether it's the active
    // slot (live `player` reference) or a dormant slot (snapshot). After
    // loadPlayerObject() runs, GameStorage.saves[currentSlot] is already a
    // reference to `player` (storage.js:464), so this just reads directly.
    function slotPlayer(id) {
        if (typeof GameStorage === "undefined") return undefined;
        return GameStorage.saves && GameStorage.saves[id];
    }

    // Safe format helpers — format() / formatInt() / TimeSpan may not exist
    // yet during early startup, and a slot's antimatter may be a plain number
    // or a break_infinity Decimal. We accept both.
    function safeFormat(v) {
        if (v === undefined || v === null) return "0";
        try {
            if (typeof format === "function") return format(v, 2);
        } catch (e) { /* fallthrough */ }
        if (typeof v === "number") return String(v);
        if (v && typeof v.mantissa === "number" && typeof v.exponent === "number") {
            return v.mantissa.toFixed(2) + "e" + v.exponent;
        }
        return String(v);
    }

    function safeFormatInt(n) {
        if (n === undefined || n === null) return "0";
        try {
            if (typeof formatInt === "function") return formatInt(n);
        } catch (e) { /* fallthrough */ }
        return String(n | 0);
    }

    // Format a millisecond duration into a short human-readable string.
    // Prefer the game's TimeSpan class for locale parity; fall back to our
    // own trivial formatter if it isn't available.
    function safeFormatDuration(ms) {
        if (!isFinite(ms) || ms < 0) return "0s";
        try {
            if (typeof TimeSpan !== "undefined" && TimeSpan.fromMilliseconds) {
                return TimeSpan.fromMilliseconds(ms).toStringShort(false);
            }
        } catch (e) { /* fallthrough */ }
        var s = Math.floor(ms / 1000);
        if (s < 60) return s + "s";
        var m = Math.floor(s / 60); s = s % 60;
        if (m < 60) return m + "m " + s + "s";
        var h = Math.floor(m / 60); m = m % 60;
        if (h < 24) return h + "h " + m + "m";
        var d = Math.floor(h / 24); h = h % 24;
        return d + "d " + h + "h";
    }

    // Derive a friendly stage label. Uses ProgressChecker if it's available
    // (it is — exported via core-entry.js through progress-checker.js). Falls
    // back to a coarse guess from `save.realities`/`save.infinitied` so the
    // slot card still shows something meaningful early in startup.
    function stageLabel(save) {
        if (!save) return "Empty";
        try {
            if (typeof ProgressChecker !== "undefined" && ProgressChecker.getProgressStage) {
                var stage = ProgressChecker.getProgressStage(save);
                if (stage && stage.name) return stage.name;
            }
        } catch (e) { /* fallthrough */ }
        try {
            if (save.celestials && save.celestials.pelle && save.celestials.pelle.doomed) return "Doomed";
            if (save.realities && Number(save.realities) > 0) return "Reality";
            if (save.eternities && Number(save.eternities) > 0) return "Eternity";
            if (save.infinitied && Number(save.infinitied) > 0) return "Infinity";
        } catch (e) { /* fallthrough */ }
        return "Antimatter";
    }

    function slotSummary(id, save) {
        if (!save) {
            return {
                id: id,
                isEmpty: true,
                isActive: (typeof GameStorage !== "undefined") && GameStorage.currentSlot === id,
                saveFileName: "",
                antimatter: "0",
                realities: "0",
                eternities: "0",
                infinitied: "0",
                realTimePlayed: "0s",
                lastUpdate: 0,
                stage: "Empty"
            };
        }
        var realTimePlayed = 0;
        if (save.records && typeof save.records.realTimePlayed === "number") {
            realTimePlayed = save.records.realTimePlayed;
        }
        var am = (save.antimatter !== undefined) ? save.antimatter : save.money;
        return {
            id: id,
            isEmpty: false,
            isActive: (typeof GameStorage !== "undefined") && GameStorage.currentSlot === id,
            saveFileName: (save.options && save.options.saveFileName) ? save.options.saveFileName : "",
            antimatter: safeFormat(am),
            realities: safeFormatInt(save.realities || 0),
            eternities: safeFormatInt(save.eternities || 0),
            infinitied: safeFormatInt(save.infinitied || 0),
            realTimePlayed: safeFormatDuration(realTimePlayed),
            lastUpdate: Number(save.lastUpdate || 0),
            stage: stageLabel(save)
        };
    }

    // ---- Slot listing / switching -------------------------------------

    globalThis._nativeListSlots = function () {
        if (typeof GameStorage === "undefined" || !GameStorage.saves) {
            return JSON.stringify({ current: 0, slots: [] });
        }
        var slots = [];
        for (var i = 0; i < 3; i++) {
            slots.push(slotSummary(i, slotPlayer(i)));
        }
        return JSON.stringify({ current: GameStorage.currentSlot, slots: slots });
    };

    globalThis._nativeSwitchSlot = function (id) {
        if (typeof GameStorage === "undefined") return "no-storage";
        if (id < 0 || id > 2) return "invalid-id";
        if (GameStorage.currentSlot === id) return "already-active";
        try {
            // Prevent JS-side offline simulation — Swift handles offline
            // progress separately via runOfflineSimulation. Without this,
            // loadSlot -> loadPlayerObject -> simulateTime blocks jsQueue
            // inline for however many offline ticks the save has queued.
            // Matches importSave / _nativeRestoreBackup.
            GameStorage.offlineEnabled = false;
            GameStorage.loadSlot(id);
            // Fast-forward `player.backupTimer` past any existing
            // lastBackupTimes for this slot. Without this, switching to
            // an empty slot (or a slot with old backup metadata) leaves
            // `timeSinceLast = player.backupTimer (0) - oldHigh` hugely
            // negative, and `tryOnlineBackups` never fires its
            // `interval - timeSinceLast <= 800` condition — online
            // backups silently stop working for the new game. Mirrors
            // the web's `import()` path which calls this for the same
            // reason.
            if (typeof GameStorage.resetBackupTimer === "function") {
                GameStorage.resetBackupTimer();
            }
            return "ok";
        } catch (e) {
            if (typeof _nativeLog === "function") _nativeLog("[save-helpers] switchSlot error: " + e);
            return "error";
        }
    };

    globalThis._nativeRenameSlot = function (id, name) {
        if (typeof GameStorage === "undefined" || !GameStorage.saves) return "no-storage";
        if (id < 0 || id > 2) return "invalid-id";
        var save = GameStorage.saves[id];
        if (!save) return "empty-slot";
        if (!save.options) save.options = {};
        save.options.saveFileName = String(name || "").slice(0, 60);
        try { GameStorage.save(true); } catch (e) { /* ignore */ }
        return "ok";
    };

    globalThis._nativeDeleteSlot = function (id) {
        if (typeof GameStorage === "undefined" || !GameStorage.saves) return "no-storage";
        if (id < 0 || id > 2) return "invalid-id";
        if (GameStorage.currentSlot === id) return "active-slot";
        GameStorage.saves[id] = undefined;
        try { GameStorage.save(true); } catch (e) { /* ignore */ }
        return "ok";
    };

    globalThis._nativeExportSlot = function (id) {
        if (typeof GameStorage === "undefined" || !GameStorage.saves) return "";
        if (id < 0 || id > 2) return "";
        var save = GameStorage.saves[id];
        if (!save) return "";
        try {
            if (typeof GameSaveSerializer === "undefined" || !GameSaveSerializer.serialize) return "";
            // Match exportModifiedSave (storage.js:405) for the active slot so a
            // slot-export matches the clipboard export precisely.
            if (id === GameStorage.currentSlot && typeof Speedrun !== "undefined" && typeof Speedrun.setSegmented === "function") {
                var wasSegmented = save.speedrun && save.speedrun.isSegmented;
                try { Speedrun.setSegmented(true); } catch (e) { /* ignore */ }
                var out = GameSaveSerializer.serialize(save);
                try { Speedrun.setSegmented(!!wasSegmented); } catch (e) { /* ignore */ }
                return out;
            }
            return GameSaveSerializer.serialize(save);
        } catch (e) {
            if (typeof _nativeLog === "function") _nativeLog("[save-helpers] exportSlot error: " + e);
            return "";
        }
    };

    // ---- Backups -------------------------------------------------------

    function backupTypeLabel(type) {
        // Matches BACKUP_SLOT_TYPE in storage.js: 0=online, 1=offline, 2=reserve.
        if (type === 0) return "online";
        if (type === 1) return "offline";
        return "reserve";
    }

    function backupIntervalLabel(info) {
        if (info && typeof info.intervalStr === "function") {
            try { return info.intervalStr(); } catch (e) { /* fallthrough */ }
        }
        return "";
    }

    globalThis._nativeListBackups = function (slotId) {
        if (typeof GameStorage === "undefined" || !GameStorage.saves) {
            return JSON.stringify({ slotId: slotId, backups: [] });
        }
        if (slotId < 0 || slotId > 2) {
            return JSON.stringify({ slotId: slotId, backups: [] });
        }
        if (typeof AutoBackupSlots === "undefined") {
            return JSON.stringify({ slotId: slotId, backups: [] });
        }

        // Backup timestamps are stored per-slot in a parallel key. Reading the
        // active slot's times is straightforward; reading a non-active slot's
        // times is a direct localStorage read.
        var times = {};
        try {
            var timeKey = GameStorage.backupTimeKey(slotId);
            var timeRaw = localStorage.getItem(timeKey);
            if (timeRaw && GameSaveSerializer && GameSaveSerializer.deserialize) {
                var parsed = GameSaveSerializer.deserialize(timeRaw);
                if (parsed && typeof parsed === "object") times = parsed;
            }
        } catch (e) { /* ignore */ }

        var backups = [];
        for (var i = 0; i < AutoBackupSlots.length; i++) {
            var info = AutoBackupSlots[i];
            var dataKey = GameStorage.backupDataKey(slotId, info.id);
            var raw = null;
            try { raw = localStorage.getItem(dataKey); } catch (e) { raw = null; }

            var save = null;
            if (raw && GameSaveSerializer && GameSaveSerializer.deserialize) {
                try { save = GameSaveSerializer.deserialize(raw); } catch (e) { save = null; }
            }

            var summary = slotSummary(slotId, save);
            var meta = times[info.id] || {};

            backups.push({
                backupId: info.id,
                type: backupTypeLabel(info.type),
                intervalLabel: backupIntervalLabel(info),
                isEmpty: summary.isEmpty,
                antimatter: summary.antimatter,
                realities: summary.realities,
                eternities: summary.eternities,
                realTimePlayed: summary.realTimePlayed,
                stage: summary.stage,
                date: Number(meta.date || 0)
            });
        }
        return JSON.stringify({ slotId: slotId, backups: backups });
    };

    // ---- Cloud comparison -------------------------------------------
    //
    // Mirrors web's Cloud.compareSaves + ProgressChecker.compareSaveProgress
    // (src/core/storage/cloud-saving.js:104, progress-checker.js:41).
    // Inlined here because ProgressChecker isn't exported to globalThis —
    // only GameDatabase.progressStages is — and the algorithm itself is
    // trivial once you have the stages. Keeps us from adding a new export
    // to core-entry.js (which would require rebuilding the bundle).

    function getCompositeProgress(save) {
        if (!save) return 0;
        if (typeof GameDatabase === "undefined" || !GameDatabase.progressStages) return 0;
        var stages = GameDatabase.progressStages;
        for (var i = stages.length - 1; i >= 0; i--) {
            try {
                if (stages[i].hasReached(save)) {
                    var sub = 0;
                    try { sub = stages[i].subProgressValue(save); } catch (e) { sub = 0; }
                    if (!isFinite(sub)) sub = 0;
                    sub = Math.max(0, Math.min(1, sub));
                    return stages[i].id + sub;
                }
            } catch (e) { /* ignore, try earlier stage */ }
        }
        return 0;
    }

    // Extract the small subset of save metadata we show in the conflict
    // sheet. We intentionally don't try to format Decimal here (no point
    // dragging break_infinity formatting into a one-off read) — Swift side
    // can render raw numbers or defer.
    function saveMetadata(save) {
        if (!save) return null;
        var rtp = (save.records && typeof save.records.realTimePlayed === "number")
            ? save.records.realTimePlayed : 0;
        return {
            isEmpty: false,
            antimatter: safeFormat(save.antimatter || save.money),
            realities: safeFormatInt(save.realities || 0),
            eternities: safeFormatInt(save.eternities || 0),
            infinitied: safeFormatInt(save.infinitied || save.infinities || 0),
            realTimePlayed: safeFormatDuration(rtp),
            realTimePlayedRaw: rtp,
            saveFileName: (save.options && save.options.saveFileName) ? save.options.saveFileName : "",
            lastUpdate: Number(save.lastUpdate || 0),
            compositeProgress: getCompositeProgress(save),
            stage: stageLabel(save)
        };
    }

    // Compare a cloud save blob (Base64/magic-wrapped string, same format as
    // clipboard export) against a local slot's player object. Returns the
    // 4-field comparison plus metadata for both sides so Swift can render the
    // conflict sheet without additional reads.
    //
    // `cloudHash` is optional — pass the SHA-256 (or any stable hash) of the
    // cloud blob as-last-seen-by-this-device and we'll set hashMismatch when
    // it changed since then. This detects the "another device wrote to the
    // cloud after we last pulled" case.
    globalThis._nativeCompareSaves = function (localSlotId, cloudSaveStr, cloudHash, lastSeenHash) {
        if (typeof GameStorage === "undefined") {
            return JSON.stringify({ error: "no-storage" });
        }
        if (localSlotId < 0 || localSlotId > 2) {
            return JSON.stringify({ error: "invalid-slot" });
        }

        var cloudPlayer = null;
        if (typeof cloudSaveStr === "string" && cloudSaveStr.length > 0) {
            try {
                if (typeof GameSaveSerializer !== "undefined" && GameSaveSerializer.deserialize) {
                    cloudPlayer = GameSaveSerializer.deserialize(cloudSaveStr);
                }
            } catch (e) { cloudPlayer = null; }

            if (cloudPlayer && typeof GameStorage.checkPlayerObject === "function") {
                var err = GameStorage.checkPlayerObject(cloudPlayer);
                if (err !== "") cloudPlayer = null;
            }
        }

        var localPlayer = slotPlayer(localSlotId);

        var localMeta = saveMetadata(localPlayer);
        var cloudMeta = saveMetadata(cloudPlayer);

        // farther: -1 cloud farther, +1 local farther, 0 similar (threshold 0.05)
        var farther = 0;
        if (cloudPlayer && localPlayer) {
            var diff = getCompositeProgress(cloudPlayer) - getCompositeProgress(localPlayer);
            if (diff > 0.05) farther = -1;
            else if (diff < -0.05) farther = 1;
        } else if (cloudPlayer && !localPlayer) {
            farther = -1;
        } else if (!cloudPlayer && localPlayer) {
            farther = 1;
        }

        // older: -1 cloud older, +1 local older, 0 when either is missing
        var older = 0;
        if (cloudPlayer && localPlayer) {
            var cloudRTP = (cloudPlayer.records && cloudPlayer.records.realTimePlayed) || 0;
            var localRTP = (localPlayer.records && localPlayer.records.realTimePlayed) || 0;
            older = (cloudRTP >= localRTP) ? -1 : 1;
        }

        var differentName = false;
        if (cloudPlayer && localPlayer) {
            var cloudName = (cloudPlayer.options && cloudPlayer.options.saveFileName) || "";
            var localName = (localPlayer.options && localPlayer.options.saveFileName) || "";
            differentName = cloudName !== localName;
        }

        // hashMismatch: did the cloud blob change since we last pulled it?
        var hashMismatch = false;
        if (cloudHash && lastSeenHash && cloudHash !== lastSeenHash) {
            hashMismatch = true;
        }

        return JSON.stringify({
            farther: farther,
            older: older,
            differentName: differentName,
            hashMismatch: hashMismatch,
            local: localMeta,
            cloud: cloudMeta
        });
    };

    // Hook GameStorage.save so every save path (autosave, manual save,
    // importSave, hardReset, loadSlot, backup restore) fires a single JS→Swift
    // tick via _nativeSaveTick. SaveSlotsSection observes engine.saveSignal
    // and refreshes its snapshot on change — replaces the per-second polling
    // timer. Idempotent: re-injecting save-helpers.js on import/hardReset
    // won't double-wrap because of the _nativeSaveHooked guard.
    if (typeof GameStorage !== "undefined" &&
        typeof GameStorage.save === "function" &&
        !GameStorage._nativeSaveHooked) {
        var _origGameStorageSave = GameStorage.save.bind(GameStorage);
        GameStorage.save = function () {
            var result = _origGameStorageSave.apply(GameStorage, arguments);
            if (typeof _nativeSaveTick === "function") {
                try { _nativeSaveTick(); } catch (e) { /* swallow */ }
            }
            return result;
        };
        GameStorage._nativeSaveHooked = true;
    }

    // Restore a backup into the ACTIVE slot. Callers (Swift) are expected to
    // switch to `slotId` first if it differs from the current slot. We mirror
    // the web flow from BackupSavesTab.vue → GameStorage.loadFromBackup +
    // loadPlayerObject + save.
    globalThis._nativeRestoreBackup = function (slotId, backupId) {
        if (typeof GameStorage === "undefined") return "no-storage";
        if (slotId !== GameStorage.currentSlot) return "not-active-slot";
        if (typeof AutoBackupSlots === "undefined") return "no-backups";
        var info = null;
        for (var i = 0; i < AutoBackupSlots.length; i++) {
            if (AutoBackupSlots[i].id === backupId) { info = AutoBackupSlots[i]; break; }
        }
        if (!info) return "invalid-backup";
        var restored = null;
        try { restored = GameStorage.loadFromBackup(backupId); } catch (e) { restored = null; }
        if (!restored) return "empty-backup";
        if (typeof GameStorage.checkPlayerObject === "function") {
            var err = GameStorage.checkPlayerObject(restored);
            if (err !== "") return "invalid-save";
        }
        try {
            // Prevent JS-side offline simulation — Swift handles offline
            // progress separately. Matches importSave's behaviour.
            GameStorage.offlineEnabled = false;
            GameStorage.loadPlayerObject(restored);
            // See _nativeSwitchSlot for full rationale. A restored backup
            // typically has a much smaller `player.backupTimer` than the
            // saved lastBackupTimes (since the backup was taken earlier
            // in the timeline). Fast-forward so online backups for the
            // restored state fire normally.
            if (typeof GameStorage.resetBackupTimer === "function") {
                GameStorage.resetBackupTimer();
            }
            GameStorage.save(true);
            return "ok";
        } catch (e) {
            if (typeof _nativeLog === "function") _nativeLog("[save-helpers] restoreBackup error: " + e);
            return "error";
        }
    };

})();
