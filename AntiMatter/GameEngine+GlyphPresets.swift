//
//  GameEngine+GlyphPresets.swift
//  AntiMatter
//
//  Glyph Presets — port of GlyphSetSavePanel.vue. Storage lives at
//  `player.reality.glyphs.sets` (already populated on every save by web
//  migrations.js). All JS-side work goes through glyph-loadout-helpers.js
//  (loaded by setupGlyphPresetHelpers, called from the same lifecycle hooks
//  as save-helpers / news-helpers / celestial-helpers).
//

import JavaScriptCore
import Foundation

extension GameEngine {

    // MARK: - JS helpers injection

    /// Injects `_nativeListGlyphPresets` / `_nativeSetGlyphMatchToggle` /
    /// `_nativeSaveGlyphPreset` / `_nativeDeleteGlyphPreset` /
    /// `_nativeRenameGlyphPreset` / `_nativePreviewLoadGlyphPreset` /
    /// `_nativeLoadGlyphPreset`. Must run on jsQueue after `cacheJSRefs()`;
    /// matches the news/celestial/save helper pattern.
    func setupGlyphPresetHelpers() {
        guard let url = Bundle.main.url(forResource: "glyph-loadout-helpers", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("🔴 GameEngine: missing glyph-loadout-helpers.js in app bundle")
            return
        }
        _ = context.evaluateScript(source)
    }

    // MARK: - Reads (fetch on demand, not per-tick)

    /// Fetch a fresh snapshot of all 7 preset slots + global toggles + active
    /// slot / inventory headroom. Dispatches completion on main. Call when
    /// the sheet appears and after any mutating action.
    func loadGlyphPresets(completion: @escaping (GlyphPresetsSnapshot) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let json = self.context.evaluateScript("_nativeListGlyphPresets()")?.toString() ?? "{}"
                let snap = Self.parsePresetsSnapshot(json: json)
                DispatchQueue.main.async { completion(snap) }
            }
        }
    }

    // MARK: - Mutations

    /// Flip one of the three global matching toggles
    /// (`player.options.ignoreGlyphEffects/Level/Rarity`). The kind string
    /// matches the JS helper's switch: "effects" / "level" / "rarity".
    func setGlyphMatchToggle(_ kind: String, on: Bool, completion: @escaping () -> Void = {}) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                _ = self.context.evaluateScript("_nativeSetGlyphMatchToggle(\"\(kind)\", \(on ? "true" : "false"))")
                DispatchQueue.main.async { completion() }
            }
        }
    }

    /// Capture the currently-equipped glyphs into the given slot. Mirrors
    /// `saveGlyphSet`: refuses if the slot is non-empty or if nothing is
    /// equipped (the user must Delete first to overwrite — matches web).
    func saveGlyphPreset(_ id: Int, completion: @escaping (Bool) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let result = self.context.evaluateScript("_nativeSaveGlyphPreset(\(id))")?.toString() ?? "error"
                DispatchQueue.main.async {
                    switch result {
                    case "ok":
                        self.enqueueToast(type: "info", text: String(localized: "Preset \(id + 1) saved"))
                        completion(true)
                    case "no-equipped":
                        self.enqueueToast(type: "error", text: String(localized: "Equip glyphs first"))
                        completion(false)
                    case "slot-occupied":
                        self.enqueueToast(type: "error", text: String(localized: "Delete the existing preset first"))
                        completion(false)
                    default:
                        self.enqueueToast(type: "error", text: String(localized: "Could not save preset"))
                        completion(false)
                    }
                }
            }
        }
    }

    /// Empty the given slot. Web parity — also clears `name` would be too
    /// aggressive; we follow web and only clear `glyphs` so a re-save can
    /// reuse the name.
    func deleteGlyphPreset(_ id: Int, completion: @escaping (Bool) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let result = self.context.evaluateScript("_nativeDeleteGlyphPreset(\(id))")?.toString() ?? "error"
                let ok = (result == "ok")
                DispatchQueue.main.async {
                    if ok {
                        self.enqueueToast(type: "info", text: String(localized: "Preset \(id + 1) deleted"))
                    } else if result == "empty" {
                        // No toast — UI prevents this from reaching here.
                    } else {
                        self.enqueueToast(type: "error", text: String(localized: "Could not delete preset"))
                    }
                    completion(ok)
                }
            }
        }
    }

    /// Rename a slot. Web caps at 20 chars JS-side; we still trim on the
    /// Swift side so the in-flight TextField value doesn't visually jitter.
    func renameGlyphPreset(_ id: Int, name: String, completion: @escaping () -> Void = {}) {
        let trimmed = String(name.prefix(20))
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                _ = self.context.evaluateScript("_nativeRenameGlyphPreset(\(id), \"\(escaped)\")")
                DispatchQueue.main.async { completion() }
            }
        }
    }

    /// Dry-run preview: returns what the matcher *would* do, without
    /// mutating state. Used to populate the diff view before the user
    /// commits. Completion receives either the result or an error case.
    func previewLoadGlyphPreset(_ id: Int, completion: @escaping (Result<GlyphLoadResult, GlyphPresetLoadError>) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let json = self.context.evaluateScript("_nativePreviewLoadGlyphPreset(\(id))")?.toString() ?? "{}"
                let parsed = Self.parseLoadResult(json: json, presetId: id)
                DispatchQueue.main.async { completion(parsed) }
            }
        }
    }

    /// Apply the preset. Mutates `Glyphs.active` via the JS-side matcher.
    /// `lastLoadResult` is updated on the main thread so persistent badges
    /// can render. Mid-Reality callers must invoke `resetRealityForPresetLoad`
    /// FIRST — this method does not reset the Reality itself.
    func loadGlyphPreset(_ id: Int, completion: @escaping (Result<GlyphLoadResult, GlyphPresetLoadError>) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let json = self.context.evaluateScript("_nativeLoadGlyphPreset(\(id))")?.toString() ?? "{}"
                let parsed = Self.parseLoadResult(json: json, presetId: id)
                DispatchQueue.main.async {
                    if case .success(let result) = parsed {
                        self.lastLoadResult = result
                        let line: String
                        if result.requiresPreview {
                            line = String(localized: "Loaded '\(result.presetName.isEmpty ? "Preset \(id + 1)" : result.presetName)' — \(result.summary)")
                        } else {
                            line = String(localized: "Loaded '\(result.presetName.isEmpty ? "Preset \(id + 1)" : result.presetName)'")
                        }
                        self.enqueueToast(type: "info", text: line)
                    }
                    completion(parsed)
                }
            }
        }
    }

    // MARK: - Clearing badges

    /// Clear persistent badges for the given equipped slot. Called when
    /// the user manually changes a slot (drag, sacrifice, unequip).
    func clearGlyphPresetBadge(forActiveSlot index: Int) {
        guard let result = lastLoadResult else { return }
        guard index >= 0, index < result.slots.count else { return }
        // Drop the matching entry; if the result becomes all-exact we can
        // just clear the whole thing.
        var newSlots = result.slots
        newSlots[index] = GlyphLoadSlotMatch(
            savedGlyph: newSlots[index].savedGlyph,
            willEquipGlyph: newSlots[index].willEquipGlyph,
            matchKind: .exact
        )
        let needsBadges = newSlots.contains(where: { $0.matchKind.requiresPreview })
        if needsBadges {
            lastLoadResult = GlyphLoadResult(
                presetId: result.presetId,
                presetName: result.presetName,
                slots: newSlots,
                exactCount: result.exactCount,
                fuzzyCount: result.fuzzyCount,
                partialCount: result.partialCount,
                alreadyCount: result.alreadyCount,
                missingCount: result.missingCount
            )
        } else {
            lastLoadResult = nil
        }
    }

    // MARK: - Parsing

    fileprivate static func parsePresetsSnapshot(json: String) -> GlyphPresetsSnapshot {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .empty
        }
        let toggles = obj["toggles"] as? [String: Any] ?? [:]
        let rawSets = obj["sets"] as? [[String: Any]] ?? []
        let sets: [GlyphLoadoutSlot] = (0..<7).map { idx in
            guard idx < rawSets.count else {
                return GlyphLoadoutSlot(id: idx, name: "", autoName: "", glyphs: [])
            }
            let d = rawSets[idx]
            let id = (d["id"] as? Int) ?? idx
            let name = (d["name"] as? String) ?? ""
            let autoName = (d["autoName"] as? String) ?? ""
            let glyphs = (d["glyphs"] as? [[String: Any]] ?? []).compactMap(parsePresetGlyph)
            return GlyphLoadoutSlot(id: id, name: name, autoName: autoName, glyphs: glyphs)
        }
        return GlyphPresetsSnapshot(
            sets: sets,
            ignoreEffects: (toggles["effects"] as? Bool) ?? false,
            ignoreLevel: (toggles["level"] as? Bool) ?? false,
            ignoreRarity: (toggles["rarity"] as? Bool) ?? false,
            hasEquipped: (obj["hasEquipped"] as? Bool) ?? false,
            activeSlotCount: (obj["activeSlotCount"] as? Int) ?? 0,
            freeInventorySlots: (obj["freeInventorySlots"] as? Int) ?? 0
        )
    }

    fileprivate nonisolated static func parsePresetGlyph(_ d: [String: Any]) -> GlyphPresetGlyph? {
        guard let type = d["type"] as? String else { return nil }
        let id: Int = {
            if let n = d["id"] as? Int { return n }
            if let dbl = d["id"] as? Double { return Int(dbl) }
            return 0
        }()
        let level: Int = {
            if let n = d["level"] as? Int { return n }
            if let dbl = d["level"] as? Double { return Int(dbl) }
            return 0
        }()
        let effects: Int = {
            if let n = d["effects"] as? Int { return n }
            if let dbl = d["effects"] as? Double { return Int(dbl) }
            return 0
        }()
        let effectCount: Int = {
            if let n = d["effectCount"] as? Int { return n }
            if let dbl = d["effectCount"] as? Double { return Int(dbl) }
            return 0
        }()
        return GlyphPresetGlyph(
            id: id,
            type: type,
            symbol: (d["symbol"] as? String) ?? "?",
            level: level,
            strength: (d["strength"] as? Double) ?? 1.0,
            effects: effects,
            effectCount: effectCount,
            typeColor: (d["typeColor"] as? String) ?? "#888",
            rarityColor: (d["rarityColor"] as? String) ?? "#888"
        )
    }

    fileprivate static func parseLoadResult(json: String, presetId: Int) -> Result<GlyphLoadResult, GlyphPresetLoadError> {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.unknown)
        }
        if let err = obj["error"] as? String {
            switch err {
            case "empty": return .failure(.empty)
            case "too-many-glyphs":
                let required = (obj["required"] as? Int) ?? 0
                let available = (obj["available"] as? Int) ?? 0
                return .failure(.tooManyGlyphs(required: required, available: available))
            default: return .failure(.unknown)
            }
        }
        let rawSlots = obj["slots"] as? [[String: Any]] ?? []
        let slots: [GlyphLoadSlotMatch] = rawSlots.map { d in
            let saved = (d["savedGlyph"] as? [String: Any]).flatMap(parsePresetGlyph)
            let will = (d["willEquipGlyph"] as? [String: Any]).flatMap(parsePresetGlyph)
            let kindRaw = (d["matchKind"] as? String) ?? "missing"
            let kind = GlyphMatchKind(rawValue: kindRaw) ?? .missing
            return GlyphLoadSlotMatch(savedGlyph: saved, willEquipGlyph: will, matchKind: kind)
        }
        return .success(GlyphLoadResult(
            presetId: presetId,
            presetName: (obj["name"] as? String) ?? "",
            slots: slots,
            exactCount: (obj["exactCount"] as? Int) ?? 0,
            fuzzyCount: (obj["fuzzyCount"] as? Int) ?? 0,
            partialCount: (obj["partialCount"] as? Int) ?? 0,
            alreadyCount: (obj["alreadyCount"] as? Int) ?? 0,
            missingCount: (obj["missingCount"] as? Int) ?? 0
        ))
    }
}
