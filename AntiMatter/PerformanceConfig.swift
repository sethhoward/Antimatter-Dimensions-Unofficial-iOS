///
///  PerformanceConfig.swift
///  AntiMatter
///
///  Central place for all performance-related tuning constants.
///  Adjust these to change throttling behavior, timer precision, and QoS.
///

import UIKit

enum PerformanceConfig {

    // MARK: - Display Link (UI refresh)

    /// Default UI refresh rate when no persisted value exists.
    static let defaultFPS: Int = 30

    // MARK: - Idle throttling
    //
    // Each idle step triggers after `idleTimeout` seconds of no interaction.
    // Step 0 = first throttle, step 1 = next, etc. The last step is the floor.
    // On any touch, resets back to full FPS immediately.

    /// Seconds of no interaction before stepping down one level.
    static let idleTimeoutPhone: CFTimeInterval = 60.0

    /// Seconds of no interaction before stepping down one level.
    static let idleTimeoutPad: CFTimeInterval = 120.0

    /// FPS steps when idle (iPhone). Each triggers after another `idleTimeoutPhone`.
    /// Example: 0–60s = full, 60s = 20, 120s = 15, 180s+ = 10.
    static let idleStepsPhone: [Int] = [20, 15, 10]

    /// FPS steps when idle (iPad). Each triggers after another `idleTimeoutPad`.
    /// Example: 0–120s = full, 120s = 20, 240s+ = 15.
    static let idleStepsPad: [Int] = [20, 15, 10, 5]

    // MARK: - Autosave

    /// How often the JS-side autosave timer fires `GameStorage.save(true)`,
    /// in milliseconds. The JS game's own default is 30s
    /// (`player.options.autosaveInterval`); we override at every spot we
    /// (re)start the timer so saves are infrequent enough to keep cloud
    /// uploads + iCloud KVS pressure low without putting the player at risk
    /// of losing meaningful progress.
    static let autosaveIntervalMs: Int = 60_000

    // MARK: - Thermal throttling

    /// Cap FPS when device reaches `.serious` or `.critical` thermal state.
    static let thermalCapFPS: Int = 15

    // MARK: - JS queue

    /// Timer leeway in milliseconds for setInterval/setTimeout (iPhone).
    /// Higher values let the OS coalesce timer fires for power/thermal savings.
    static let timerLeewayPhone: Int = 8

    /// Timer leeway in milliseconds for setInterval/setTimeout (iPad).
    /// Zero for precise timing (better thermal headroom on iPad).
    static let timerLeewayPad: Int = 0

    /// QoS for the JS background queue — `.userInitiated` on both iPhone and iPad.
    ///
    /// `.userInitiated` lets the OS schedule work on efficiency cores and
    /// clock the CPU down when the simulation isn't latency-critical. The JS
    /// game loop runs at 30Hz (33ms per tick) which leaves plenty of
    /// headroom above the QoS scheduling overhead — `.userInteractive`'s
    /// lower latency buys nothing in practice and locks us onto performance
    /// cores, spiking thermals on iPad too (not just iPhone). Empirically
    /// iPhone saw ~10% thermal reduction with the downgrade; iPad sees a
    /// similar win (less fan / hotter-chassis on M-series tablets that run
    /// this app for hours).
    static let jsQueueQoSPhone: DispatchQoS = .userInitiated
    static let jsQueueQoSPad: DispatchQoS = .userInitiated

    // MARK: - Convenience

    /// Idle timeout for the current device.
    static var idleTimeout: CFTimeInterval {
        UIDevice.current.userInterfaceIdiom == .phone ? idleTimeoutPhone : idleTimeoutPad
    }

    /// Idle FPS steps for the current device.
    static var idleSteps: [Int] {
        UIDevice.current.userInterfaceIdiom == .phone ? idleStepsPhone : idleStepsPad
    }

    /// Timer leeway for the current device (milliseconds).
    static var timerLeeway: Int {
        UIDevice.current.userInterfaceIdiom == .phone ? timerLeewayPhone : timerLeewayPad
    }

    /// JS queue QoS for the current device.
    static var jsQueueQoS: DispatchQoS {
        UIDevice.current.userInterfaceIdiom == .phone ? jsQueueQoSPhone : jsQueueQoSPad
    }
}
