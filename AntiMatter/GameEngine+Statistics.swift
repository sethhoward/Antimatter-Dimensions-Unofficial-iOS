//
//  GameEngine+Statistics.swift
//  AntiMatter
//
//  JS bridge wiring for the Statistics tab and its 4 new subtabs:
//  - statistics-helper.js (general — bulk JSON, replaces inline pollStatistics reads)
//  - multiplier-breakdown-helper.js (Multiplier Breakdown subtab)
//  - glyph-set-records-helper.js (Glyph Set Records subtab)
//  - speedrun-records-helper.js (Speedrun Records + Speedrun Milestones meta)
//
//  Same lifecycle pattern as the other helper scripts — re-injected at every
//  save-lifecycle entry point (finishStartup / importSave / hardReset / slot-
//  switch / backup-restore / startSpeedrun / adopt-cloud-save).
//

import JavaScriptCore
import Foundation

extension GameEngine {

    // MARK: - JS helpers injection

    func setupStatisticsHelpers() {
        loadHelperScript("statistics-helper")
    }

    func setupMultiplierBreakdownHelpers() {
        loadHelperScript("multiplier-breakdown-helper")
    }

    func setupGlyphSetRecordsHelpers() {
        loadHelperScript("glyph-set-records-helper")
    }

    func setupSpeedrunRecordsHelpers() {
        loadHelperScript("speedrun-records-helper")
    }

    /// Convenience that fans out all 4 statistics helpers — the existing
    /// save-lifecycle entry points call this once instead of 4 individual
    /// calls, mirroring how `setupSaveHelpers` is wired.
    func setupStatisticsAndRelatedHelpers() {
        setupStatisticsHelpers()
        setupMultiplierBreakdownHelpers()
        setupGlyphSetRecordsHelpers()
        setupSpeedrunRecordsHelpers()
    }

    fileprivate func loadHelperScript(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("🔴 GameEngine: missing \(name).js in app bundle")
            return
        }
        _ = context.evaluateScript(source)
    }

    // MARK: - Subtab visibility flags (per-tick)

    /// Polls the 4 visibility flags that gate the new subtabs.
    /// Cheap — single JS eval + 4 bool reads, used to drive `Subtab.isAvailable`.
    /// Called from `pollDirect()` always-on block.
    func pollStatisticsVisibilityFlags() {
        let json = context.evaluateScript("_nativeStatisticsVisibilityFlags()")?.toString() ?? "{}"
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let mb = (obj["multiplierBreakdown"] as? Bool) ?? false
        let gs = (obj["glyphSetRecords"] as? Bool) ?? false
        let sm = (obj["speedrunMilestones"] as? Bool) ?? false
        let sr = (obj["speedrunRecords"] as? Bool) ?? false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.multiplierBreakdownVisible != mb { self.multiplierBreakdownVisible = mb }
            if self.glyphSetRecordsVisible    != gs { self.glyphSetRecordsVisible    = gs }
            if self.speedrunMilestonesVisible != sm { self.speedrunMilestonesVisible = sm }
            if self.speedrunRecordsVisible    != sr { self.speedrunRecordsVisible    = sr }
        }
    }

    // MARK: - Statistics general (per-tick, parsed bulk JSON)

    func pollStatisticsGeneral(_ state: inout GameState) {
        let json = context.evaluateScript("_nativeStatisticsGeneral()")?.toString() ?? "{}"
        state.statistics = Self.parseStatisticsGeneral(json: json)
    }

    private static func parseStatisticsGeneral(json: String) -> StatisticsState {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .empty
        }
        let matterScaleRaw = (obj["matterScale"] as? [Any]) ?? []
        var matterScale = matterScaleRaw.compactMap { $0 as? String }
        if matterScale.isEmpty { matterScale = ["There is no antimatter yet."] }
        return StatisticsState(
            totalAntimatter: (obj["totalAntimatter"] as? String) ?? "0",
            realTimePlayed: (obj["realTimePlayed"] as? String) ?? "0 seconds",
            saveCreatedTime: (obj["saveCreatedTime"] as? Double) ?? (Date().timeIntervalSince1970 * 1000),
            saveAge: (obj["saveAge"] as? String) ?? "0 seconds",
            matterScale: matterScale,
            totalNews: (obj["totalNews"] as? Int) ?? 0,
            uniqueNews: (obj["uniqueNews"] as? Int) ?? 0,
            secretAchievementCount: (obj["secretAchievementCount"] as? Int) ?? 0,
            paperclips: (obj["paperclips"] as? Int) ?? 0,
            fullGameCompletions: (obj["fullGameCompletions"] as? Int) ?? 0,
            fullTimePlayed: obj["fullTimePlayed"] as? String,
            isDoomed: (obj["isDoomed"] as? Bool) ?? false,
            realTimeDoomed: obj["realTimeDoomed"] as? String,
            infinityUnlocked: (obj["infinityUnlocked"] as? Bool) ?? false,
            infinityCount: obj["infinityCount"] as? String,
            bankedInfinities: obj["bankedInfinities"] as? String,
            bestInfinityTime: obj["bestInfinityTime"] as? String,
            thisInfinityTime: obj["thisInfinityTime"] as? String,
            thisInfinityRealTime: obj["thisInfinityRealTime"] as? String,
            bestIPPerMin: obj["bestIPPerMin"] as? String,
            projectedBankedOnEternity: obj["projectedBankedOnEternity"] as? String,
            projectedBankedRatePerMin: obj["projectedBankedRatePerMin"] as? String,
            eternityUnlocked: (obj["eternityUnlocked"] as? Bool) ?? false,
            eternityCount: obj["eternityCount"] as? String,
            bestEternityTime: obj["bestEternityTime"] as? String,
            thisEternityTime: obj["thisEternityTime"] as? String,
            thisEternityRealTime: obj["thisEternityRealTime"] as? String,
            bestEPPerMin: obj["bestEPPerMin"] as? String,
            realityUnlocked: (obj["realityUnlocked"] as? Bool) ?? false,
            realityCount: obj["realityCount"] as? String,
            bestRealityTime: obj["bestRealityTime"] as? String,
            bestRealityRealTime: obj["bestRealityRealTime"] as? String,
            thisRealityTime: obj["thisRealityTime"] as? String,
            thisRealityRealTime: obj["thisRealityRealTime"] as? String,
            totalTimePlayedGameTime: obj["totalTimePlayedGameTime"] as? String,
            bestRMPerMin: obj["bestRMPerMin"] as? String,
            bestGlyphRarity: obj["bestGlyphRarity"] as? String
        )
    }

    // MARK: - Multiplier Breakdown

    /// Fetches the resource picker list + current resource selection.
    /// On demand — called when the subtab opens and after persist-pref taps.
    func loadMultiplierBreakdownTopOptions(completion: @escaping (MultiplierBreakdownState) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let json = self.context.evaluateScript("_nativeMultiplierBreakdownTopOptions()")?.toString() ?? "{}"
                let (options, currId, showAlt, replace) = Self.parseMBTopOptions(json: json)
                // Fetch the resource for the current id.
                let resourceKey = options.first(where: { $0.id == currId })?.key
                    ?? options.first?.key
                    ?? "AM"
                let resJson = self.context.evaluateScript("_nativeMultiplierBreakdownResource('\(resourceKey)_total')")?.toString() ?? "{}"
                let resource = Self.parseMBResource(json: resJson)
                let state = MultiplierBreakdownState(
                    availableResources: options,
                    currentResourceId: currId,
                    replacePowers: replace,
                    showAltGroup: showAlt,
                    resource: resource
                )
                DispatchQueue.main.async { completion(state) }
            }
        }
    }

    /// Fetches just the resource tree for a specific key. Used for on-tap
    /// drill-down and for refreshing the current resource on per-tick polling.
    func loadMultiplierBreakdownResource(key: String, completion: @escaping (MultiplierBreakdownResource?) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let safeKey = key.replacingOccurrences(of: "'", with: "")
                let json = self.context.evaluateScript("_nativeMultiplierBreakdownResource('\(safeKey)')")?.toString() ?? "{}"
                let resource = Self.parseMBResource(json: json)
                DispatchQueue.main.async { completion(resource) }
            }
        }
    }

    /// Persists one of the 3 multiplier-tab options to player.options.multiplierTab.
    func setMultiplierBreakdownPref(field: String, value: Any) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let jsValue: String
                if let b = value as? Bool { jsValue = b ? "true" : "false" }
                else if let i = value as? Int { jsValue = String(i) }
                else { jsValue = "null" }
                _ = self.context.evaluateScript(
                    "_nativeMultiplierBreakdownSet('\(field)', \(jsValue))"
                )
            }
        }
    }

    private static func parseMBTopOptions(json: String) -> ([MultiplierBreakdownResourceOption], Int, Bool, Bool) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], 0, false, false)
        }
        var options: [MultiplierBreakdownResourceOption] = []
        if let arr = obj["resources"] as? [[String: Any]] {
            for item in arr {
                options.append(MultiplierBreakdownResourceOption(
                    id: (item["id"] as? Int) ?? 0,
                    key: (item["key"] as? String) ?? "",
                    label: (item["label"] as? String) ?? "",
                    isActive: (item["isActive"] as? Bool) ?? false
                ))
            }
        }
        return (
            options.filter { $0.isActive },
            (obj["currentResourceId"] as? Int) ?? 0,
            (obj["showAltGroup"] as? Bool) ?? false,
            (obj["replacePowers"] as? Bool) ?? false
        )
    }

    private static func parseMBResource(json: String) -> MultiplierBreakdownResource? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var entries: [MultiplierBreakdownEntryNode] = []
        if let arr = obj["entries"] as? [[String: Any]] {
            for item in arr {
                entries.append(MultiplierBreakdownEntryNode(
                    key: (item["key"] as? String) ?? "",
                    name: (item["name"] as? String) ?? "",
                    displayString: (item["displayString"] as? String) ?? "",
                    percent: (item["percent"] as? Double) ?? 0,
                    isNerf: (item["isNerf"] as? Bool) ?? false,
                    isVisible: (item["isVisible"] as? Bool) ?? false,
                    hasChildren: (item["hasChildren"] as? Bool) ?? false,
                    iconText: (item["iconText"] as? String) ?? "",
                    iconSFSymbol: (item["iconSFSymbol"] as? String) ?? "",
                    iconColor: (item["iconColor"] as? String) ?? "#cccccc",
                    iconTextColor: (item["iconTextColor"] as? String) ?? "white"
                ))
            }
        }
        return MultiplierBreakdownResource(
            key: (obj["key"] as? String) ?? "",
            name: (obj["name"] as? String) ?? "",
            totalString: (obj["totalString"] as? String) ?? "",
            isEmpty: (obj["isEmpty"] as? Bool) ?? false,
            disabledText: (obj["disabledText"] as? String) ?? "",
            isDilated: (obj["isDilated"] as? Bool) ?? false,
            dilationString: obj["dilationString"] as? String,
            inNC12Notice: (obj["inNC12Notice"] as? Bool) ?? false,
            isADTotal: (obj["isADTotal"] as? Bool) ?? false,
            hasAltGroup: (obj["hasAltGroup"] as? Bool) ?? false,
            allowPowerToggle: (obj["allowPowerToggle"] as? Bool) ?? false,
            hasSeenPowers: (obj["hasSeenPowers"] as? Bool) ?? false,
            entries: entries
        )
    }

    // MARK: - Glyph Set Records

    func loadGlyphSetRecords(completion: @escaping (GlyphSetRecordsState) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let json = self.context.evaluateScript("_nativeGlyphSetRecords()")?.toString() ?? "{}"
                let state = Self.parseGlyphSetRecords(json: json)
                DispatchQueue.main.async { completion(state) }
            }
        }
    }

    private static func parseGlyphSetRecords(json: String) -> GlyphSetRecordsState {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["records"] as? [[String: Any]] else {
            return .empty
        }
        var records: [GlyphSetRecord] = []
        for item in arr {
            guard let visible = item["visible"] as? Bool, visible else { continue }
            let label = (item["label"] as? String) ?? ""
            let value = (item["value"] as? String) ?? ""
            var glyphs: [GlyphPresetGlyph] = []
            if let glyphArr = item["glyphs"] as? [[String: Any]] {
                for g in glyphArr {
                    glyphs.append(GlyphPresetGlyph(
                        id: (g["id"] as? Int) ?? 0,
                        type: (g["type"] as? String) ?? "power",
                        symbol: (g["symbol"] as? String) ?? "?",
                        level: (g["level"] as? Int) ?? 0,
                        strength: (g["strength"] as? Double) ?? 0,
                        effects: (g["effects"] as? Int) ?? 0,
                        effectCount: (g["effectCount"] as? Int) ?? 0,
                        typeColor: (g["typeColor"] as? String) ?? "#888888",
                        rarityColor: (g["rarityColor"] as? String) ?? "#888888"
                    ))
                }
            }
            records.append(GlyphSetRecord(label: label, value: value, glyphs: glyphs))
        }
        return GlyphSetRecordsState(records: records)
    }

    // MARK: - Speedrun Records

    func loadSpeedrunRecords(completion: @escaping (SpeedrunRecordsState) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let json = self.context.evaluateScript("_nativePreviousSpeedruns()")?.toString() ?? "{}"
                let state = Self.parseSpeedrunRecords(json: json)
                DispatchQueue.main.async { completion(state) }
            }
        }
    }

    private static func parseSpeedrunRecords(json: String) -> SpeedrunRecordsState {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["runs"] as? [[String: Any]] else {
            return .empty
        }
        var runs: [SpeedrunPreviousRun] = []
        for r in arr {
            var milestones: [SpeedrunPreviousMilestone] = []
            if let mArr = r["milestones"] as? [[String: Any]] {
                for m in mArr {
                    milestones.append(SpeedrunPreviousMilestone(
                        id: (m["id"] as? Int) ?? 0,
                        name: (m["name"] as? String) ?? "",
                        timeMs: (m["timeMs"] as? Double) ?? 0
                    ))
                }
            }
            runs.append(SpeedrunPreviousRun(
                id: (r["id"] as? String) ?? "",
                name: (r["name"] as? String) ?? "",
                isSegmented: (r["isSegmented"] as? Bool) ?? false,
                totalTimeMs: (r["totalTimeMs"] as? Double) ?? 0,
                dateFinishedMs: (r["dateFinishedMs"] as? Double) ?? 0,
                milestones: milestones
            ))
        }
        return SpeedrunRecordsState(runs: runs)
    }

    // MARK: - Speedrun Milestones meta

    /// Surfaces displayAllMilestones + start time + hasStarted, used by the
    /// new SpeedrunMilestonesTab. On-demand only.
    func loadSpeedrunMilestonesMeta(completion: @escaping (Bool, String, Bool) -> Void) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let json = self.context.evaluateScript("_nativeSpeedrunMilestonesMeta()")?.toString() ?? "{}"
                let displayAll: Bool
                let startStr: String
                let hasStarted: Bool
                if let data = json.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    displayAll = (obj["displayAll"] as? Bool) ?? false
                    startStr = (obj["startTimeStr"] as? String) ?? ""
                    hasStarted = (obj["hasStarted"] as? Bool) ?? false
                } else {
                    displayAll = false; startStr = ""; hasStarted = false
                }
                DispatchQueue.main.async { completion(displayAll, startStr, hasStarted) }
            }
        }
    }

    func setSpeedrunDisplayAllMilestones(_ value: Bool) {
        jsQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                _ = self.context.evaluateScript(
                    "_nativeSpeedrunSetDisplayAll(\(value ? "true" : "false"))"
                )
            }
        }
    }
}
