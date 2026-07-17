//
//  GameEngine+Automator.swift
//  AntiMatter
//
//  Automator Constants editor bridge (iOS port of AutomatorDefinePage.vue +
//  AutomatorDefineSingleEntry.vue). Talks to automator-helpers.js, injected by
//  setupAutomatorHelpers() at every save-lifecycle entry point (finishStartup /
//  importSave / hardReset / slot-switch / backup-restore), same pattern as
//  setupCelestialHelpers().
//
//  Constants are fetched on demand (panel open + after each mutation) — never
//  part of per-tick pollDirect, since they only change on user action.
//

import JavaScriptCore
import Foundation

// MARK: - State types

struct AutomatorConstantInfo: Equatable, Identifiable {
    let name: String
    let value: String
    var id: String { name }
}

struct AutomatorConstantsSnapshot: Equatable {
    var constants: [AutomatorConstantInfo]
    var maxCount: Int
    var maxNameLength: Int
    var maxValueLength: Int

    static let empty = AutomatorConstantsSnapshot(
        constants: [], maxCount: 30, maxNameLength: 20, maxValueLength: 250
    )
}

extension GameEngine {

    // MARK: - JS helper injection

    /// Injects the _nativeXxxAutomatorConstant bridges from automator-helpers.js.
    /// Must run on jsQueue (callers already are) after the bundle is loaded.
    func setupAutomatorHelpers() {
        guard let url = Bundle.main.url(forResource: "automator-helpers", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("🔴 GameEngine: missing automator-helpers.js in app bundle")
            return
        }
        _ = context.evaluateScript(source)
    }

    // MARK: - On-demand fetch

    /// Loads the current constants + length limits. Completion runs on main.
    func loadAutomatorConstants(completion: @escaping (AutomatorConstantsSnapshot) -> Void) {
        jsQueue.async { [self] in
            autoreleasepool {
                let json = context.evaluateScript("_nativeListAutomatorConstants()")?.toString() ?? ""
                let snapshot = Self.parseConstantsSnapshot(json)
                DispatchQueue.main.async { completion(snapshot) }
            }
        }
    }

    private static func parseConstantsSnapshot(_ json: String) -> AutomatorConstantsSnapshot {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .empty
        }
        let rawList = (obj["constants"] as? [[String: Any]]) ?? []
        let constants = rawList.map {
            AutomatorConstantInfo(
                name: ($0["name"] as? String) ?? "",
                value: ($0["value"] as? String) ?? ""
            )
        }
        return AutomatorConstantsSnapshot(
            constants: constants,
            maxCount: (obj["maxCount"] as? NSNumber)?.intValue ?? 30,
            maxNameLength: (obj["maxNameLength"] as? NSNumber)?.intValue ?? 20,
            maxValueLength: (obj["maxValueLength"] as? NSNumber)?.intValue ?? 250
        )
    }

    // MARK: - Mutations (fire-and-forget)

    func addAutomatorConstant(name: String, value: String) {
        jsQueue.async { [self] in
            autoreleasepool {
                context.setObject(name, forKeyedSubscript: "_swiftConstName" as NSString)
                context.setObject(value, forKeyedSubscript: "_swiftConstValue" as NSString)
                context.evaluateScript("_nativeAddAutomatorConstant(_swiftConstName, _swiftConstValue)")
            }
        }
    }

    func modifyAutomatorConstant(name: String, value: String) {
        jsQueue.async { [self] in
            autoreleasepool {
                context.setObject(name, forKeyedSubscript: "_swiftConstName" as NSString)
                context.setObject(value, forKeyedSubscript: "_swiftConstValue" as NSString)
                context.evaluateScript("_nativeModifyAutomatorConstant(_swiftConstName, _swiftConstValue)")
            }
        }
    }

    func renameAutomatorConstant(old: String, new: String) {
        jsQueue.async { [self] in
            autoreleasepool {
                context.setObject(old, forKeyedSubscript: "_swiftConstOld" as NSString)
                context.setObject(new, forKeyedSubscript: "_swiftConstNew" as NSString)
                context.evaluateScript("_nativeRenameAutomatorConstant(_swiftConstOld, _swiftConstNew)")
            }
        }
    }

    func deleteAutomatorConstant(_ name: String) {
        jsQueue.async { [self] in
            autoreleasepool {
                context.setObject(name, forKeyedSubscript: "_swiftConstName" as NSString)
                context.evaluateScript("_nativeDeleteAutomatorConstant(_swiftConstName)")
            }
        }
    }

    func clearAutomatorConstants() {
        jsAsync("_nativeClearAutomatorConstants()")
    }

    func importTSConstants() {
        jsAsync("_nativeImportTSConstantsAsConstants()")
    }

    // MARK: - Validation

    /// Returns "" if valid, otherwise an error message. `oldName` is the
    /// constant's previous name ("" when adding). Completion runs on main.
    func validateAutomatorConstant(name: String, value: String, oldName: String,
                                   completion: @escaping (String) -> Void) {
        jsQueue.async { [self] in
            autoreleasepool {
                context.setObject(name, forKeyedSubscript: "_swiftConstName" as NSString)
                context.setObject(value, forKeyedSubscript: "_swiftConstValue" as NSString)
                context.setObject(oldName, forKeyedSubscript: "_swiftConstOld" as NSString)
                let error = context.evaluateScript(
                    "_nativeValidateAutomatorConstant(_swiftConstName, _swiftConstValue, _swiftConstOld)"
                )?.toString() ?? ""
                DispatchQueue.main.async { completion(error) }
            }
        }
    }
}
