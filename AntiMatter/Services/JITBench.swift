//
//  JITBench.swift
//  AntiMatter
//
//  Microbenchmark harness comparing JSContext (no JIT on iOS app
//  processes) against WKWebView (JIT in the out-of-process WebContent
//  service). Goal: validate whether moving offline simulation into a
//  hidden WKWebView is worth the architectural complexity.
//  Decision criteria: ≥3× → green-light a real implementation,
//  <2× → abandon.
//
//  Triggered manually via Debug tab; not used by the live game path.
//

#if DEBUG
import Foundation
import WebKit

struct JITBenchResult: Equatable, Sendable {
    let iterations: Int
    let jsContextMs: Double
    let webViewMs: Double
    let jsContextChecksum: String
    let webViewChecksum: String
    let webViewError: String?

    var speedup: Double {
        guard webViewMs > 0, jsContextMs > 0 else { return 0 }
        return jsContextMs / webViewMs
    }

    var checksumsMatch: Bool {
        !jsContextChecksum.isEmpty && jsContextChecksum == webViewChecksum
    }

    var verdict: String {
        if let err = webViewError { return "WebView failed: \(err)" }
        if !checksumsMatch { return "Checksum mismatch — invalid result" }
        let s = speedup
        if s >= 3.0 { return "JIT confirmed; full plan green-lit" }
        if s >= 2.0 { return "Marginal; judgment call" }
        if s > 0 { return "JIT closed; abandon" }
        return "Inconclusive"
    }

    var formattedReport: String {
        let iterStr = NumberFormatter.localizedString(from: NSNumber(value: iterations), number: .decimal)
        var lines: [String] = []
        lines.append("JIT Bench: \(iterStr) Decimal multiply+add+compare iterations")
        lines.append(String(format: "  JSContext: %.0f ms (%.2f µs/iter)",
                            jsContextMs, jsContextMs * 1000.0 / Double(iterations)))
        if let err = webViewError {
            lines.append("  WKWebView: failed (\(err))")
        } else {
            lines.append(String(format: "  WKWebView: %.0f ms (%.2f µs/iter)",
                                webViewMs, webViewMs * 1000.0 / Double(iterations)))
            lines.append(String(format: "  Speedup:   %.2f× — %@", speedup, verdict))
            if !checksumsMatch {
                lines.append("  ⚠️ Checksum mismatch:")
                lines.append("     JSContext: \(jsContextChecksum)")
                lines.append("     WKWebView: \(webViewChecksum)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Spins up a hidden WKWebView, loads the production game-core-bundle.js
/// + browser-shims.js + the same Decimal patches the live JSContext gets,
/// then runs the JIT bench workload. Single-shot — release the instance
/// after `run()` returns.
@MainActor
final class JITWebViewBench: NSObject, WKNavigationDelegate {
    let iterations: Int
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Never>?

    init(iterations: Int) {
        self.iterations = iterations
        super.init()
    }

    func run() async -> (elapsedMs: Double, checksum: String)? {
        guard let shims = loadResource("browser-shims"),
              let bundle = loadResource("game-core-bundle"),
              let bench  = loadResource("jit-bench") else {
            debugLog("JIT BENCH: missing one of browser-shims/game-core-bundle/jit-bench")
            return nil
        }

        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        self.webView = wv

        // Wait for the empty document to finish loading. We do all script
        // evaluation post-didFinish via evaluateJavaScript so we can
        // serialize the order and surface any per-script error.
        await withCheckedContinuation { cont in
            self.continuation = cont
            wv.loadHTMLString("<html><body></body></html>", baseURL: nil)
        }

        // Step 1: native-callback stubs. browser-shims will reference
        // these (its console hijack calls _nativeLog).
        guard await safeEval(wv, label: "stubs", source: """
            window._nativeLog = function() {};
            window._nativeNotify = function() {};
            window._nativeMessage = function() {};
            window._nativeEvent = function() {};
        """) else {
            tearDown(); return nil
        }

        // Step 2: browser-shims. The bundle expects `globalThis.window ===
        // globalThis`, but in WKWebView `window` is non-writable, so the
        // shim's `globalThis.window = globalThis` silently no-ops. We
        // make-believe by aliasing: any reference to `window.X` will
        // already resolve to the real Window, so the bundle's `window.X = …`
        // assignments work the same way `globalThis.X = …` would in
        // JSContext (because in WebView, window === globalThis already).
        //
        // Strip WKWebView-incompatible blocks from the shim source. WKWebView
        // owns these globals as real read-only or controlled accessors, so
        // assigning over them throws (e.g. `globalThis.location = {...}`
        // throws "Invalid URL" because Location.href validates URL strings).
        // None of these are needed in the WebView — it has native versions.
        let safeShims = stripWKWebViewIncompatibleShims(shims)
        guard await safeEval(wv, label: "browser-shims", source: safeShims) else {
            tearDown(); return nil
        }

        // Step 3: the bundle. This defines `globalThis.Decimal` (and
        // everything else) via core-entry.js's mergeIntoGlobal pattern.
        guard await safeEval(wv, label: "bundle", source: bundle) else {
            tearDown(); return nil
        }

        // Step 4: probe — confirm Decimal is reachable. If not, the
        // bundle's mergeIntoGlobal may have skipped it because something
        // pre-shadowed it. We need to know *that* before running the bench.
        let probe = (try? await wv.evaluateJavaScript(
            "({decimalGlobal: typeof Decimal, decimalOnGlobalThis: typeof globalThis.Decimal, decimalOnWindow: typeof window.Decimal, asyncDefined: typeof window.Async})"
        )) as? [String: Any]
        if let probe {
            debugLog("JIT BENCH probe: \(probe)")
        }
        if (probe?["decimalGlobal"] as? String) == "undefined" {
            debugLog("JIT BENCH: Decimal not defined after bundle load — diagnosing")
            tearDown(); return nil
        }

        // Step 5: apply the same Decimal patches JSContext gets.
        guard await safeEval(wv, label: "_patchDecimalPerf",
                             source: "if (typeof _patchDecimalPerf === 'function') _patchDecimalPerf();") else {
            tearDown(); return nil
        }
        guard await safeEval(wv, label: "timesEffectsOf patch",
                             source: GameEngine.timesEffectsOfPatchSource) else {
            tearDown(); return nil
        }

        // Step 6: load the bench function.
        guard await safeEval(wv, label: "jit-bench", source: bench) else {
            tearDown(); return nil
        }

        // Step 7: actually run it.
        let raw = try? await wv.evaluateJavaScript("_runJITBench(\(iterations))")
        let dict = raw as? [String: Any]
        let elapsed = (dict?["elapsedMs"] as? NSNumber)?.doubleValue ?? -1
        let checksum = dict?["checksum"] as? String ?? ""
        tearDown()
        if elapsed < 0 || checksum.isEmpty {
            debugLog("JIT BENCH: WKWebView _runJITBench returned invalid \(String(describing: dict))")
            return nil
        }
        return (elapsed, checksum)
    }

    /// Evaluate a script and log any thrown error. Returns true on success.
    /// Wraps the source in a try/catch IIFE so a real JS exception comes
    /// back as a diagnostic object — WKWebView's default error description
    /// for a thrown exception is just "A JavaScript exception occurred"
    /// with no message/stack. The wrap also makes the result a bridgeable
    /// value (object on error, undefined on success) so the unsupported-
    /// result-type quirk doesn't fire.
    private func safeEval(_ wv: WKWebView, label: String, source: String) async -> Bool {
        let wrapped = """
        (function() {
            try {
        \(source)
            } catch (e) {
                return { __jitBenchError: true,
                         message: String((e && e.message) || e),
                         stack: e && e.stack ? String(e.stack) : null };
            }
        })()
        """
        do {
            let raw = try await wv.evaluateJavaScript(wrapped)
            if let dict = raw as? [String: Any],
               dict["__jitBenchError"] as? Bool == true {
                let msg = dict["message"] as? String ?? "<no message>"
                let stack = dict["stack"] as? String ?? ""
                debugLog("JIT BENCH: WKWebView eval threw at '\(label)': \(msg)\n\(stack)")
                return false
            }
            return true
        } catch {
            let ns = error as NSError
            if ns.domain == WKError.errorDomain
                && ns.code == WKError.Code.javaScriptResultTypeIsUnsupported.rawValue {
                return true
            }
            debugLog("JIT BENCH: WKWebView eval failed at '\(label)': \(error.localizedDescription)")
            return false
        }
    }

    // MARK: WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.continuation?.resume()
            self.continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            debugLog("JIT BENCH: WKWebView navigation failed: \(error.localizedDescription)")
            self.continuation?.resume()
            self.continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            debugLog("JIT BENCH: WKWebView provisional navigation failed: \(error.localizedDescription)")
            self.continuation?.resume()
            self.continuation = nil
        }
    }

    // MARK: helpers

    private func tearDown() {
        webView?.navigationDelegate = nil
        webView = nil
    }

    /// Remove top-level `globalThis.X = ...;` assignments that conflict
    /// with WKWebView's read-only built-ins. The bundle and `_patchDecimalPerf`
    /// don't depend on the shim versions of these — they're stub
    /// replacements for what JSContext lacks, and WKWebView has the real
    /// thing. Recognised by a marker comment + a multi-line block ending
    /// at a `};` on its own line (or by single-line form for one-liners).
    private func stripWKWebViewIncompatibleShims(_ source: String) -> String {
        // Names whose `globalThis.<name> = …` block we want to strip. These
        // are the assignments the bundle would ignore-or-prefer-real-version
        // anyway in a WebView context.
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
            // Match a top-level `globalThis.NAME = ` assignment.
            if let name = names.first(where: { trimmed.hasPrefix("globalThis.\($0) ") || trimmed.hasPrefix("globalThis.\($0)=") }) {
                _ = name
                let startIdx = i
                // Determine if it's a single-line statement (ends with `;`)
                // or a multi-line block (ends at a `};` on its own line).
                if trimmed.hasSuffix(";") && !trimmed.hasSuffix("{};") && !trimmed.contains("{") {
                    lines[i] = "// [JIT BENCH stripped] " + lines[i]
                    i += 1
                    continue
                }
                // Multi-line: find the matching closing brace at line scope.
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
                    lines[j] = "// [JIT BENCH stripped] " + lines[j]
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
#endif
