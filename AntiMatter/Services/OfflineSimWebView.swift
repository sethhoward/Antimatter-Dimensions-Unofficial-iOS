//
//  OfflineSimWebView.swift
//  AntiMatter
//
//  Hidden WKWebView used as an offline-sim host. Loads the production
//  game bundle + the same Decimal patches we apply to JSContext, then
//  exposes hooks for save marshaling, sim batching, progress reporting,
//  and Speed up / Skip control.
//
//  Stage 1 (this revision): WebView lifecycle + smoke test. The smoke
//  test confirms the bundle loads, Decimal is reachable, and the same
//  workload that runs in JSContext also runs here. No real save state
//  crossing yet — that's Stage 2.
//
//  Why a hidden WebView at all: JSContext (used for live play) lacks
//  JIT on iOS. WKWebView's out-of-process WebContent service has full
//  JIT. The JIT microbench measured a 50× speedup on a Decimal-heavy
//  loop, so moving the offline sim here makes long offline catch-ups
//  tolerable without touching the rest of the game architecture.
//
//  See plans/webview-offline-simulation.md for the full plan.
//

import Foundation
import UIKit
import WebKit

/// Result of `OfflineSimWebView.boot()`. Boot can fail at any of the
/// load steps (navigation, shim eval, bundle eval, patch application);
/// the failing step name is in `failureLabel` for diagnostics.
enum OfflineSimWebViewBootResult: Equatable, Sendable {
    case ok
    case failure(label: String, message: String?)

    var isOK: Bool {
        if case .ok = self { return true }
        return false
    }
}

/// One-shot orchestrator. Use:
///   let sim = OfflineSimWebView()
///   guard (await sim.boot()).isOK else { /* fallback */ return }
///   guard await sim.importSave(saveString) else { /* fallback */ return }
///   let ticksRun = await sim.runOfflineSim(elapsedSeconds: …)
///   guard let postSave = await sim.exportSave() else { /* fallback */ return }
///   sim.tearDown()
///
/// Single-use design: instantiate per sim, tear down after. The cold-
/// start cost (~200–500ms bundle load) is paid once per instance and
/// dwarfed by the sim itself for any non-trivial offline gap. Warm-
/// keeping is over-optimisation for the 99% case (1–2 sims per session).
@MainActor
final class OfflineSimWebView: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView?
    private var navigationContinuation: CheckedContinuation<Void, Never>?
    /// Set to true if the WKWebView's WebContent process terminates
    /// mid-sim (OOM, JIT bug, watchdog kill). All subsequent eval
    /// attempts return false fast so the orchestrator can fall back
    /// to JSContext without spinning trying to use a dead context.
    private var webContentCrashed: Bool = false
    /// Stage-3d: per-batch progress callback. Set by `runOfflineSim` and
    /// invoked from `userContentController(_:didReceive:)` whenever the
    /// batch loop posts a `{remaining, total}` message. Always invoked on
    /// the main actor.
    private var progressCallback: ((_ remaining: Int, _ total: Int) -> Void)?
    /// Name of the WKScriptMessageHandler registered for batch progress.
    private static let progressHandlerName = "offlineSimProgress"
    /// Captured `GameUI.notify.*` calls fired during the sim. The WebView's
    /// stubbed `_nativeNotify` posts each `{type, text}` here instead of
    /// dropping it on the floor like the original no-op stub did. Drained by
    /// the orchestrator after the post-sim save is applied to JSContext, so
    /// the user sees green "Automatically unlocked: X" toasts (etc.) the same
    /// way they would from a real-time unlock.
    private(set) var capturedNotifications: [(type: String, text: String)] = []
    /// Name of the WKScriptMessageHandler registered for notification capture.
    private static let notifyHandlerName = "offlineSimNotify"

    /// Boot: instantiate the WebView, load bundle + shims + Decimal
    /// patches, return whether it's ready for sim work.
    func boot() async -> OfflineSimWebViewBootResult {
        guard let shims = loadResource("browser-shims"),
              let bundle = loadResource("game-core-bundle") else {
            return .failure(label: "resource-load", message: "missing browser-shims or game-core-bundle")
        }

        let config = WKWebViewConfiguration()
        // Register our progress message handler before the WebView spins
        // up so the JS side can call `webkit.messageHandlers.X.postMessage`
        // immediately after the bundle loads. We're @MainActor, conform to
        // WKScriptMessageHandler, and tearDown removes us — no retain
        // cycle in practice.
        config.userContentController.add(self, name: Self.progressHandlerName)
        config.userContentController.add(self, name: Self.notifyHandlerName)

        // 1×1 tiny frame instead of `.zero`. iOS QoS-throttles the
        // WebContent process when WKWebView appears "idle" / "off-screen"
        // — `.zero` frame + not-in-hierarchy = idle from iOS's POV, and
        // ~5 seconds in we see GPUProcessProxy::gpuProcessExited
        // (reason=IdleExit) followed by a sustained ~5× slowdown on JS
        // execution. Making the WebView a visible-but-tiny element of
        // the active window keeps the WebContent process on a foreground
        // QoS tier.
        let wv = WKWebView(frame: CGRect(x: -1, y: -1, width: 1, height: 1), configuration: config)
        wv.navigationDelegate = self
        wv.isHidden = false   // hidden = true would also de-prioritise
        wv.alpha = 0.01       // visually invisible, but still "rendering"
        if let window = Self.activeKeyWindow() {
            window.addSubview(wv)
        }
        self.webView = wv

        // Load an empty document; user scripts intentionally NOT used —
        // sequential evaluateJavaScript gives us per-step error visibility.
        // The baseURL must be non-nil and have a real-looking origin —
        // WKWebView refuses localStorage/sessionStorage on opaque origins
        // ("The operation is insecure"), and the bundle's
        // `GameStorage.import` writes to localStorage during post-load.
        // The URL doesn't need to resolve to anything; WKWebView won't
        // make network requests for it (no <link>/<script src> in the
        // HTML), it just uses the URL to derive the page's origin.
        let baseURL = URL(string: "https://offlinesim.local/")
        await withCheckedContinuation { cont in
            self.navigationContinuation = cont
            wv.loadHTMLString("<html><body></body></html>", baseURL: baseURL)
        }

        // Step 1: native callback stubs + DOM safety net.
        // Native callbacks: browser-shims and the bundle reference these.
        // DOM patch: the bundle's postLoadStuff reads
        // `document.getElementById("background-animations").style.…` and
        // similar, expecting browser-shims's stub document to return a
        // fake element. In WKWebView we have a real-but-empty document,
        // so getElementById returns null. We monkey-patch
        // getElementById / querySelector / querySelectorAll to fall back
        // to a stub when the lookup misses, mirroring what
        // browser-shims's stub document does. This is layered on top of
        // the real DOM, so any element that DOES exist still works
        // normally.
        if !(await safeEval(label: "stubs", source: """
            window._nativeLog = function() {};
            // Capture notifications instead of swallowing them — the
            // orchestrator replays these as real toasts after the sim's save
            // is applied back to JSContext.
            window._nativeNotify = function(type, text) {
                try {
                    if (window.webkit && window.webkit.messageHandlers
                        && window.webkit.messageHandlers.\(Self.notifyHandlerName)) {
                        window.webkit.messageHandlers.\(Self.notifyHandlerName).postMessage({
                            type: String(type || ""),
                            text: String(text || "")
                        });
                    }
                } catch (e) {}
            };
            window._nativeMessage = function() {};
            window._nativeEvent = function() {};

            (function() {
                var stubElement = function() {
                    return {
                        style: {},
                        classList: { add: function(){}, remove: function(){}, contains: function(){ return false; }, toggle: function(){} },
                        appendChild: function(){}, removeChild: function(){},
                        addEventListener: function(){}, removeEventListener: function(){},
                        setAttribute: function(){}, getAttribute: function(){ return null; },
                        innerHTML: "", textContent: "",
                        focus: function(){}, blur: function(){}, click: function(){}
                    };
                };
                var origGEBI = document.getElementById.bind(document);
                document.getElementById = function(id) {
                    var real = origGEBI(id);
                    return real || stubElement();
                };
                var origQS = document.querySelector.bind(document);
                document.querySelector = function(sel) {
                    var real = origQS(sel);
                    return real || stubElement();
                };
                var origQSA = document.querySelectorAll.bind(document);
                document.querySelectorAll = function(sel) {
                    var real = origQSA(sel);
                    return real && real.length > 0 ? real : [];
                };
            })();
        """)) {
            return .failure(label: "stubs", message: nil)
        }

        // Step 2: shims with WKWebView-incompatible blocks stripped.
        // The bundle expects process / NotImplementedError / GlobalErrorHandler
        // / window-aliasing, all of which the shim provides; it also tries to
        // overwrite globals that WKWebView owns (location, document, navigator,
        // etc.) — those throw, so we strip them.
        let safeShims = OfflineSimWebView.stripWKWebViewIncompatibleShims(shims)
        if !(await safeEval(label: "browser-shims", source: safeShims)) {
            return .failure(label: "browser-shims", message: nil)
        }

        // Step 3: the bundle. After this, globalThis.Decimal + everything else
        // exported by core-entry.js's mergeIntoGlobal is available.
        if !(await safeEval(label: "bundle", source: bundle)) {
            return .failure(label: "bundle", message: nil)
        }

        // Step 4: probe — confirm Decimal exists. If not, the cause is
        // already in debugLog from safeEval's diagnostic wrapper.
        let probe = (try? await wv.evaluateJavaScript("typeof Decimal")) as? String
        guard probe == "function" else {
            return .failure(label: "decimal-probe",
                            message: "typeof Decimal = \(probe ?? "nil")")
        }

        // Step 5: apply the same Decimal patches JSContext gets. This is
        // what makes the bench (and any future real sim) apples-to-apples.
        if !(await safeEval(label: "_patchDecimalPerf",
                            source: "if (typeof _patchDecimalPerf === 'function') _patchDecimalPerf();")) {
            return .failure(label: "_patchDecimalPerf", message: nil)
        }
        if !(await safeEval(label: "timesEffectsOf",
                            source: GameEngine.timesEffectsOfPatchSource)) {
            return .failure(label: "timesEffectsOf", message: nil)
        }

        // Step 6: run init(). The bundle expects to be initialized before
        // any save manipulation — init() calls SteamRuntime.initialize()
        // (so its `isActive` getter doesn't throw later in
        // Achievements.updateSteamStatus, which is called at the tail of
        // GameStorage.import), plus Speedrun, Tabs, EventHub setup, etc.
        // We disable offline simulation first (Swift drives sim; the JS
        // side must not run its own simulateTime during init's load), and
        // immediately stop the auto game-loop interval afterwards.
        if !(await safeEval(label: "init", source: """
            GameStorage.offlineEnabled = false;
            init();
            try { GameIntervals.stop(); } catch (e) {}
        """)) {
            return .failure(label: "init", message: nil)
        }

        // Step 7: install a slim profiler so the batch loop can attribute
        // ms to specific subsystems. Diagnostic-only — used to track down
        // the post-batch-25 cliff (where ms/tick jumps ~7×). Wraps just
        // the major subsystems; doesn't replicate the full JSContext
        // profiler's sub-probes. Gated on a UserDefaults flag so the
        // wrappers' overhead doesn't bleed into production sims.
        if UserDefaults.standard.bool(forKey: "offlineSimDebugProfiler") {
            if !(await safeEval(label: "install profiler", source: profilerInjectionSource)) {
                return .failure(label: "install profiler", message: nil)
            }
            profilerInstalled = true
        }

        return .ok
    }

    /// Whether the diagnostic profiler is currently installed in the
    /// WebView (driven by UserDefaults at boot time). Read by the batch
    /// loop to decide whether to spend a per-batch JSON read on prof
    /// state.
    private var profilerInstalled: Bool = false

    /// JS source for a slim profiler wrapping the subsystems most likely
    /// to drive a tick-time cliff. Per-tick accumulators on
    /// `gameLoop._prof`; reset with `gameLoop._profReset()`. Wrap is a
    /// no-op when `_profEnabled` is false.
    private let profilerInjectionSource = """
    gameLoop._profEnabled = true;
    gameLoop._prof = {
        ticks: 0, total: 0,
        adTick: 0, idTick: 0, tdTick: 0,
        replicanti: 0, autobuyers: 0,
        autoDim: 0, autoOther: 0,
        challenges: 0, ipGen: 0, prestigeGen: 0,
        autoprestige: 0, blackHoles: 0,
        // Stage-3d-debug: candidates for the hidden ~40ms cliff.
        achievements: 0, tabNotifs: 0, prestigeRates: 0,
        statsRec: 0, eventHub: 0
    };
    gameLoop._profReset = function() {
        var p = gameLoop._prof;
        for (var k in p) p[k] = 0;
    };
    (function() {
        var P = gameLoop._prof;
        var E = function() { return gameLoop._profEnabled; };

        function profWrap(obj, key, profKey) {
            var orig = obj[key];
            if (typeof orig !== 'function') return;
            obj[key] = function() {
                if (!E()) return orig.apply(this, arguments);
                var t0 = Date.now();
                var r = orig.apply(this, arguments);
                P[profKey] += Date.now() - t0;
                return r;
            };
        }

        var _prevGameLoop = gameLoop;
        gameLoop = function(passDiff, options) {
            if (!E()) return _prevGameLoop(passDiff, options);
            P.ticks++;
            var t0 = Date.now();
            _prevGameLoop(passDiff, options);
            P.total += Date.now() - t0;
        };
        gameLoop._profEnabled = _prevGameLoop._profEnabled;
        gameLoop._prof = _prevGameLoop._prof;
        gameLoop._profReset = _prevGameLoop._profReset;
        P = gameLoop._prof;

        if (typeof AntimatterDimensions !== 'undefined') profWrap(AntimatterDimensions, 'tick', 'adTick');
        if (typeof InfinityDimensions !== 'undefined')   profWrap(InfinityDimensions, 'tick', 'idTick');
        if (typeof TimeDimensions !== 'undefined')        profWrap(TimeDimensions, 'tick', 'tdTick');

        // Autobuyers — break out dimension autobuyers vs others so we
        // can see if the cliff is "Big Crunch / sacrifice fires more".
        if (typeof Autobuyers !== 'undefined' && Autobuyers.all) {
            var origAutoTick = Autobuyers.tick;
            Autobuyers.tick = function() {
                if (!E()) return origAutoTick.call(this);
                var dimT = 0, otherT = 0;
                if (!player.auto.autobuyersOn) return;
                var t0all = Date.now();
                var all = Autobuyers.all;
                for (var ai = 0; ai < all.length; ai++) {
                    var ab = all[ai];
                    if (!ab.canTick) continue;
                    var t0 = Date.now();
                    ab.tick();
                    var elapsed = Date.now() - t0;
                    if (typeof ab.tier === 'number') dimT += elapsed;
                    else otherT += elapsed;
                }
                P.autobuyers += Date.now() - t0all;
                P.autoDim += dimT;
                P.autoOther += otherT;
            };
        }

        if (typeof replicantiLoop === 'function') {
            var _origRepl = replicantiLoop;
            replicantiLoop = function(diff) {
                if (!E()) return _origRepl(diff);
                var t0 = Date.now();
                var r = _origRepl(diff);
                P.replicanti += Date.now() - t0;
                return r;
            };
        }
        if (typeof updateNormalAndInfinityChallenges === 'function') {
            var _origChal = updateNormalAndInfinityChallenges;
            updateNormalAndInfinityChallenges = function(d) {
                if (!E()) return _origChal(d);
                var t0 = Date.now();
                var r = _origChal(d);
                P.challenges += Date.now() - t0;
                return r;
            };
        }
        if (typeof preProductionGenerateIP === 'function') {
            var _origIP = preProductionGenerateIP;
            preProductionGenerateIP = function(d) {
                if (!E()) return _origIP(d);
                var t0 = Date.now();
                var r = _origIP(d);
                P.ipGen += Date.now() - t0;
                return r;
            };
        }
        if (typeof passivePrestigeGen === 'function') {
            var _origPrestige = passivePrestigeGen;
            passivePrestigeGen = function() {
                if (!E()) return _origPrestige();
                var t0 = Date.now();
                var r = _origPrestige();
                P.prestigeGen += Date.now() - t0;
                return r;
            };
        }
        if (typeof applyAutoprestige === 'function') {
            var _origAP = applyAutoprestige;
            applyAutoprestige = function(d) {
                if (!E()) return _origAP(d);
                var t0 = Date.now();
                var r = _origAP(d);
                P.autoprestige += Date.now() - t0;
                return r;
            };
        }
        if (typeof BlackHoles !== 'undefined' && BlackHoles
            && typeof BlackHoles.updatePhases === 'function') {
            profWrap(BlackHoles, 'updatePhases', 'blackHoles');
        }

        // Achievements — `Achievements.tryUnlockN()` (where N is a row
        // number) runs per tick. If progressively more achievements
        // become eligible mid-sim, this could ramp.
        if (typeof Achievements !== 'undefined') {
            ['tryUnlockInfinityChallenges', 'tryUnlockEternityChallenges',
             'tryUnlockReality', 'tryUnlockEternity', 'tryUnlockBigCrunch',
             'tryUnlockDimensionBoosts', 'tryUnlockGalaxies', 'tryUnlockTickspeed',
             'tryUnlockNormalAchievementRow1', 'tryUnlockNormalAchievementRow2',
             'tryUnlockNormalAchievementRow3', 'tryUnlockNormalAchievementRow4',
             'tryUnlockNormalAchievementRow5', 'tryUnlockNormalAchievementRow6'
            ].forEach(function(k) {
                if (typeof Achievements[k] === 'function') profWrap(Achievements, k, 'achievements');
            });
        }

        // Tab notifications — TabNotification.X.tryTrigger() runs at
        // many sites per tick. the design notes says "minimal cost when
        // already-triggered" but un-triggered ones evaluate Decimal
        // compares fully. Wrap each entry's tryTrigger if accessible.
        if (typeof TabNotification !== 'undefined') {
            for (var k in TabNotification) {
                var entry = TabNotification[k];
                if (entry && typeof entry.tryTrigger === 'function') {
                    (function(e) {
                        var orig = e.tryTrigger;
                        e.tryTrigger = function() {
                            if (!E()) return orig.apply(this, arguments);
                            var t0 = Date.now();
                            var r = orig.apply(this, arguments);
                            P.tabNotifs += Date.now() - t0;
                            return r;
                        };
                    })(entry);
                }
            }
        }

        // updatePrestigeRates — throttled to every 4th tick per the design notes
        // but worth wrapping to confirm it's not part of the cliff.
        if (typeof updatePrestigeRates === 'function') {
            var _origUPR = updatePrestigeRates;
            updatePrestigeRates = function() {
                if (!E()) return _origUPR.apply(this, arguments);
                var t0 = Date.now();
                var r = _origUPR.apply(this, arguments);
                P.prestigeRates += Date.now() - t0;
                return r;
            };
        }

        // EventHub.dispatch — TICK + various per-tick events fire here.
        if (typeof EventHub !== 'undefined' && EventHub.logic
            && typeof EventHub.logic.dispatch === 'function') {
            var _origDispatch = EventHub.logic.dispatch;
            EventHub.logic.dispatch = function() {
                if (!E()) return _origDispatch.apply(this, arguments);
                var t0 = Date.now();
                var r = _origDispatch.apply(this, arguments);
                P.eventHub += Date.now() - t0;
                return r;
            };
        }
    })();
    """


    /// Stage-2: load a save string into the WebView's `player`. Mirrors
    /// the JSContext import flow: deserialize → validate → import →
    /// stop the auto game loop so the caller can drive ticks manually.
    /// Returns false on validation failure or unknown error (logged).
    func importSave(_ saveString: String) async -> Bool {
        guard webView != nil else { return false }
        let escaped = saveString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let script = """
            // Validate first; refuse anything checkPlayerObject doesn't like.
            var save = GameSaveSerializer.deserialize(`\(escaped)`);
            if (!save || GameStorage.checkPlayerObject(save) !== '') {
                return { ok: false, reason: 'invalid' };
            }
            // Match the JSContext import flow: skip JS-side offline sim,
            // import, then stop the auto game loop. The caller drives ticks.
            GameStorage.offlineEnabled = false;
            // Suppress the "Game imported" toast that GameStorage.import
            // unconditionally fires — the user didn't import anything, this
            // is our own offline-sim plumbing and surfacing it as a toast
            // would double up with the JSContext-side import.
            var __origNotify = window._nativeNotify;
            window._nativeNotify = function(t, x) {
                if (x !== "Game imported" && typeof __origNotify === "function") {
                    __origNotify(t, x);
                }
            };
            try {
                GameStorage.import(`\(escaped)`);
            } finally {
                window._nativeNotify = __origNotify;
            }
            try { GameIntervals.stop(); } catch (e) { /* ignore */ }
            return { ok: true };
        """
        guard let wv = webView else { return false }
        let wrapped = """
        (function() {
            try {
        \(script)
            } catch (e) {
                return { ok: false, reason: 'threw',
                         message: String((e && e.message) || e),
                         stack: e && e.stack ? String(e.stack) : null };
            }
        })()
        """
        do {
            let raw = try await wv.evaluateJavaScript(wrapped)
            guard let dict = raw as? [String: Any], dict["ok"] as? Bool == true else {
                let reason = (raw as? [String: Any])?["reason"] as? String ?? "unknown"
                let msg = (raw as? [String: Any])?["message"] as? String ?? ""
                debugLog("OfflineSimWebView: importSave failed (\(reason)): \(msg)")
                return false
            }
            return true
        } catch {
            debugLog("OfflineSimWebView: importSave eval error: \(error.localizedDescription)")
            return false
        }
    }

    /// Stage-2: serialize the WebView's current `player` to a save
    /// string. Uses GameSaveSerializer directly — no slot machinery
    /// (the WebView only ever holds one player). Returns nil on any
    /// failure.
    func exportSave() async -> String? {
        guard let wv = webView else { return nil }
        // Mirror exportModifiedSave's Speedrun.setSegmented(true) toggle
        // for byte-parity with the active-slot clipboard export path.
        let script = """
        (function() {
            try {
                if (typeof GameSaveSerializer === 'undefined' || !GameSaveSerializer.serialize) return null;
                if (typeof Speedrun !== 'undefined' && typeof Speedrun.setSegmented === 'function') {
                    var wasSegmented = player.speedrun && player.speedrun.isSegmented;
                    try { Speedrun.setSegmented(true); } catch (e) {}
                    var out = GameSaveSerializer.serialize(player);
                    try { Speedrun.setSegmented(!!wasSegmented); } catch (e) {}
                    return out;
                }
                return GameSaveSerializer.serialize(player);
            } catch (e) {
                return null;
            }
        })()
        """
        do {
            let raw = try await wv.evaluateJavaScript(script)
            return raw as? String
        } catch {
            debugLog("OfflineSimWebView: exportSave eval error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Stage-3: full offline sim. Uses the same setup script the
    /// JSContext path uses (`GameEngine.offlineSimSetupSource`), so
    /// currency awards, tick caps, BH path, and `_offlineSim` state
    /// match exactly. Runs the batched tick loop until `_offlineSim
    /// .remaining` reaches zero, posting `{remaining, total}` to the
    /// progress callback after each batch. Returns total tick count
    /// run, or -1 on error.
    func runOfflineSim(
        elapsedSeconds: Double,
        progressCallback: ((_ remaining: Int, _ total: Int) -> Void)? = nil
    ) async -> Int {
        guard let wv = webView else { return -1 }
        self.progressCallback = progressCallback

        // Phase 1: run the setup script (computes tick count, awards
        // currencies, sets up _offlineSim, etc.). Returns the tick count.
        let setupSource = GameEngine.offlineSimSetupSource(
            elapsedSeconds: elapsedSeconds
        )
        let raw = try? await wv.evaluateJavaScript(setupSource)
        guard let tickCount = (raw as? NSNumber)?.intValue, tickCount >= 0 else {
            debugLog("OfflineSimWebView: setup returned non-numeric \(String(describing: raw))")
            self.progressCallback = nil
            return -1
        }

        if tickCount == 0 {
            self.progressCallback = nil
            return 0
        }

        // Initial progress emission (before first batch) so the UI knows
        // the real total. The setup script's _offlineSim.total is the
        // post-clamp tick count; the placeholder the orchestrator showed
        // pre-boot may differ.
        progressCallback?(tickCount, tickCount)

        // Phase 2: fast path — run all ticks synchronously.
        if tickCount <= 50 {
            let ok = await safeEval(label: "fast-path sim", source: """
                var sim = _offlineSim;
                for (var i = sim.remaining; i > 0; i--) sim.loopFn(i);
                sim.remaining = 0;
            """)
            self.progressCallback = nil
            return ok ? tickCount : -1
        }

        // Phase 3: slow path — batch loop with per-batch yields. Each
        // batch runs ticks for ~60ms then posts a progress message back
        // (consumed in userContentController(_:didReceive:)). Speed up /
        // Skip mutate _offlineSim.remaining + total directly via
        // separate evaluateJavaScript calls — the loop reads the live
        // values each iteration, so changes are picked up within one
        // batch (~60ms).
        var lastRemaining = tickCount
        var batchIndex = 0
        var minTicksPerBatch = Int.max
        var maxTicksPerBatch = 0
        let simStart = Date()
        var lastBatchEnd = simStart
        while true {
            if webContentCrashed {
                debugLog("OfflineSimWebView: WebContent crashed mid-sim at batch #\(batchIndex), \(lastRemaining) ticks left — failing")
                self.progressCallback = nil
                return -1
            }
            let batchRaw = try? await wv.evaluateJavaScript("""
            (function() {
                var sim = _offlineSim;
                var t0 = Date.now();
                while (sim.remaining > 0) {
                    sim.loopFn(sim.remaining);
                    sim.remaining--;
                    if (Date.now() - t0 >= 60) break;
                }
                // Post progress to Swift. The handler is registered as
                // `offlineSimProgress` in boot(); the body is a plain
                // dict and reaches userContentController(_:didReceive:)
                // on the main actor.
                if (window.webkit && window.webkit.messageHandlers
                    && window.webkit.messageHandlers.\(Self.progressHandlerName)) {
                    window.webkit.messageHandlers.\(Self.progressHandlerName).postMessage({
                        remaining: sim.remaining,
                        total: sim.total
                    });
                }
                return sim.remaining;
            })()
            """)
            guard let remaining = (batchRaw as? NSNumber)?.intValue, remaining >= 0 else {
                debugLog("OfflineSimWebView: batch returned non-numeric \(String(describing: batchRaw))")
                self.progressCallback = nil
                return -1
            }
            // Per-batch timing + subsystem profiling. After each batch
            // read gameLoop._prof and reset; emit a breakdown when the
            // batch is "interesting" (early, cliff-suspect, sampled).
            let now = Date()
            let batchMs = now.timeIntervalSince(lastBatchEnd) * 1000
            let ticksThisBatch = lastRemaining - remaining
            lastRemaining = remaining
            lastBatchEnd = now
            batchIndex += 1
            if ticksThisBatch > 0 {
                minTicksPerBatch = min(minTicksPerBatch, ticksThisBatch)
                maxTicksPerBatch = max(maxTicksPerBatch, ticksThisBatch)

                // Pull the prof snapshot + reset only when the profiler
                // is installed (gated on UserDefaults). Avoids the
                // per-batch JSON read overhead in production runs.
                var profRaw: String? = nil
                if profilerInstalled {
                    profRaw = (try? await wv.evaluateJavaScript("""
                        (function() {
                            var p = gameLoop._prof;
                            var s = JSON.stringify(p);
                            gameLoop._profReset();
                            return s;
                        })()
                    """)) as? String
                }

                let isInteresting = profilerInstalled
                                 && (batchIndex <= 5
                                     || batchIndex % 10 == 0
                                     || remaining == 0)
                if isInteresting {
                    let msPerTick = batchMs / Double(ticksThisBatch)
                    var breakdown = ""
                    if let profRaw,
                       let data = profRaw.data(using: .utf8),
                       let prof = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        func msFor(_ key: String) -> Double {
                            (prof[key] as? NSNumber)?.doubleValue ?? 0
                        }
                        let total = msFor("total")
                        // Sum what we attributed. EventHub overlaps with
                        // sub-events (subsystems may dispatch from inside
                        // their wrapped section), so we don't include it
                        // in `attributed` to avoid double-counting.
                        let attributed =
                            msFor("adTick") + msFor("idTick") + msFor("tdTick") +
                            msFor("autobuyers") + msFor("replicanti") +
                            msFor("blackHoles") + msFor("ipGen") +
                            msFor("prestigeGen") + msFor("autoprestige") +
                            msFor("challenges") + msFor("achievements") +
                            msFor("tabNotifs") + msFor("prestigeRates")
                        let other = max(0, total - attributed)
                        breakdown = String(
                            format: " | total:%.0f other:%.0f | AD:%.0f ID:%.0f TD:%.0f auto:%.0f(d:%.0f o:%.0f) repl:%.0f BH:%.0f IP:%.0f preP:%.0f autoP:%.0f chal:%.0f ach:%.0f tabN:%.0f preRate:%.0f evtHub:%.0f",
                            total, other,
                            msFor("adTick"), msFor("idTick"), msFor("tdTick"),
                            msFor("autobuyers"), msFor("autoDim"), msFor("autoOther"),
                            msFor("replicanti"), msFor("blackHoles"),
                            msFor("ipGen"), msFor("prestigeGen"), msFor("autoprestige"),
                            msFor("challenges"), msFor("achievements"),
                            msFor("tabNotifs"), msFor("prestigeRates"),
                            msFor("eventHub")
                        )
                    }
                    debugLog(String(
                        format: "OFFLINE SIM (WV) batch #%d: %d ticks in %.0fms (%.3f ms/tick), %d left%@",
                        batchIndex, ticksThisBatch, batchMs, msPerTick, remaining, breakdown
                    ))
                }
            }
            if remaining == 0 { break }
            // Yield to the run loop (matches the 1ms sleepTime web's
            // Async.run uses + lets the WebView's WebContent process
            // breathe between batches).
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        // Summary so we can see the spread.
        let totalSimMs = Date().timeIntervalSince(simStart) * 1000
        let avgMsPerTick = totalSimMs / Double(tickCount)
        debugLog(String(
            format: "OFFLINE SIM (WV) summary: %d batches, %d ticks in %.0fms (avg %.3f ms/tick), batch range %d-%d ticks",
            batchIndex, tickCount, totalSimMs, avgMsPerTick,
            minTicksPerBatch == Int.max ? 0 : minTicksPerBatch,
            maxTicksPerBatch
        ))

        // Final emission so the bar lands on 100% before the apply step.
        let finalTotal = (try? await wv.evaluateJavaScript(
            "(_offlineSim && _offlineSim.total) || 0"
        )) as? NSNumber
        if let total = finalTotal?.intValue {
            progressCallback?(0, total)
        }
        self.progressCallback = nil
        return tickCount
    }

    /// Stage-3d: Speed up — halve `_offlineSim.remaining` (min 500),
    /// shrinking `_offlineSim.total` so the progress-bar fraction stays
    /// honest. Mirrors `GameEngine.offlineSimSpeedUp` for JSContext.
    /// Safe to call mid-sim; the batch loop reads the new values within
    /// one batch (~60ms).
    func speedUp() async {
        _ = await safeEval(label: "speedUp", source: """
            if (typeof _offlineSim !== 'undefined') {
                var newRemaining = Math.max(Math.floor(_offlineSim.remaining / 2), 500);
                _offlineSim.total -= (_offlineSim.remaining - newRemaining);
                _offlineSim.remaining = newRemaining;
            }
        """)
    }

    #if DEBUG
    /// DEBUG: simulate a WebContent process crash to test the
    /// crash-recovery / JSContext-fallback path. Forces the next
    /// safeEval / batch iteration to fail without an actual crash.
    func simulateCrashForTest() {
        webContentCrashed = true
        debugLog("OfflineSimWebView: simulated WebContent crash (DEBUG)")
    }
    #endif

    /// Stage-3d: Skip — jump `_offlineSim.remaining` to 10. Same idea
    /// as `speedUp` but more aggressive.
    func skip() async {
        _ = await safeEval(label: "skip", source: """
            if (typeof _offlineSim !== 'undefined' && _offlineSim.remaining > 10) {
                _offlineSim.total -= (_offlineSim.remaining - 10);
                _offlineSim.remaining = 10;
            }
        """)
    }

    // MARK: WKScriptMessageHandler

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // WebKit delivers script messages on the main thread, so it's safe
        // to assume main-actor isolation here — required to read the
        // (main-actor-isolated) `message.name` / `message.body`.
        MainActor.assumeIsolated {
            switch message.name {
            case Self.progressHandlerName:
                guard let dict = message.body as? [String: Any] else { return }
                let remaining = (dict["remaining"] as? NSNumber)?.intValue ?? -1
                let total = (dict["total"] as? NSNumber)?.intValue ?? -1
                guard remaining >= 0, total > 0 else { return }
                self.progressCallback?(remaining, total)
            case Self.notifyHandlerName:
                guard let dict = message.body as? [String: Any] else { return }
                let type = (dict["type"] as? String) ?? "info"
                let text = (dict["text"] as? String) ?? ""
                guard !text.isEmpty else { return }
                self.capturedNotifications.append((type: type, text: text))
            default:
                return
            }
        }
    }

    /// Release the WebView. Call after the sim (and any post-processing
    /// that needs WebView state) is complete. Not strictly necessary —
    /// the WebView will release on deinit — but explicit teardown keeps
    /// the WebContent process churn predictable AND removes our
    /// WKScriptMessageHandler registration so we don't leak strong refs
    /// between sims.
    func tearDown() {
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.progressHandlerName
        )
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.notifyHandlerName
        )
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        progressCallback = nil
    }

    /// Find the active foreground window so we can attach the hidden
    /// WebView to it. Searches `connectedScenes` for a foreground-active
    /// `UIWindowScene` and returns its key window.
    private static func activeKeyWindow() -> UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            if ws.activationState == .foregroundActive || ws.activationState == .foregroundInactive {
                if let key = ws.windows.first(where: { $0.isKeyWindow }) {
                    return key
                }
                if let any = ws.windows.first {
                    return any
                }
            }
        }
        return nil
    }

    // MARK: WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.navigationContinuation?.resume()
            self.navigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            debugLog("OfflineSimWebView: navigation failed: \(error.localizedDescription)")
            self.navigationContinuation?.resume()
            self.navigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            debugLog("OfflineSimWebView: provisional navigation failed: \(error.localizedDescription)")
            self.navigationContinuation?.resume()
            self.navigationContinuation = nil
        }
    }

    /// WebContent process crash. Mark the instance dead so any pending
    /// safeEval / runOfflineSim batch returns false immediately — the
    /// next iteration will see `webContentCrashed` and bail. The
    /// orchestrator's failure path takes over from there, falling back
    /// to JSContext.
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor in
            debugLog("OfflineSimWebView: WebContent process terminated (crash / OOM / watchdog) — failing the sim, JSContext fallback should engage")
            self.webContentCrashed = true
            // Resolve any pending navigation continuation so a stuck
            // boot doesn't hang waiting for a didFinish that will never
            // arrive.
            self.navigationContinuation?.resume()
            self.navigationContinuation = nil
        }
    }

    // MARK: helpers

    /// Wraps `source` in a try/catch IIFE so a real JS exception comes
    /// back as a structured object (default WKWebView error description
    /// is the unhelpful "A JavaScript exception occurred"). Returns true
    /// on success. Tolerates `WKError.javaScriptResultTypeIsUnsupported`,
    /// which fires when the script's last expression is a non-bridgeable
    /// value (function, undefined) — that's success, not failure.
    private func safeEval(label: String, source: String) async -> Bool {
        if webContentCrashed { return false }
        guard let wv = webView else { return false }
        let wrapped = """
        (function() {
            try {
        \(source)
            } catch (e) {
                return { __wvError: true,
                         message: String((e && e.message) || e),
                         stack: e && e.stack ? String(e.stack) : null };
            }
        })()
        """
        do {
            let raw = try await wv.evaluateJavaScript(wrapped)
            if let dict = raw as? [String: Any], dict["__wvError"] as? Bool == true {
                let msg = dict["message"] as? String ?? "<no message>"
                let stack = dict["stack"] as? String ?? ""
                debugLog("OfflineSimWebView: eval threw at '\(label)': \(msg)\n\(stack)")
                return false
            }
            return true
        } catch {
            let ns = error as NSError
            if ns.domain == WKError.errorDomain
                && ns.code == WKError.Code.javaScriptResultTypeIsUnsupported.rawValue {
                return true
            }
            debugLog("OfflineSimWebView: eval failed at '\(label)': \(error.localizedDescription)")
            return false
        }
    }

    /// Strip top-level `globalThis.X = ...;` assignments from the shim
    /// source whose target globals are owned by WKWebView (read-only or
    /// validated accessors). The bundle uses WKWebView's native versions
    /// instead — they're more capable than the JSContext stubs anyway.
    /// Same logic as `JITWebViewBench.stripWKWebViewIncompatibleShims`,
    /// hoisted here so both call sites stay in sync. (When we sweep both
    /// classes into a shared utility in a later stage this static will
    /// move with them.)
    static func stripWKWebViewIncompatibleShims(_ source: String) -> String {
        let names = [
            "document", "navigator", "performance", "HTMLElement",
            "DocumentTouch", "requestAnimationFrame", "cancelAnimationFrame",
            "fetch", "console", "TextEncoder", "TextDecoder", "location",
            "btoa", "atob"
        ]
        var lines = source.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if names.first(where: { trimmed.hasPrefix("globalThis.\($0) ") || trimmed.hasPrefix("globalThis.\($0)=") }) != nil {
                let startIdx = i
                if trimmed.hasSuffix(";") && !trimmed.contains("{") {
                    lines[i] = "// [OfflineSim stripped] " + lines[i]
                    i += 1
                    continue
                }
                var depth = 0
                var endIdx = startIdx
                for j in startIdx..<lines.count {
                    for ch in lines[j] {
                        if ch == "{" { depth += 1 }
                        if ch == "}" { depth -= 1 }
                    }
                    if depth == 0 && j > startIdx {
                        endIdx = j
                        break
                    }
                }
                for j in startIdx...endIdx {
                    lines[j] = "// [OfflineSim stripped] " + lines[j]
                }
                i = endIdx + 1
                continue
            }
            i += 1
        }
        return lines.joined(separator: "\n")
    }

    private func loadResource(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let src = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return src
    }
}
