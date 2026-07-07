//
//  DecimalFormat.swift
//  AntiMatter
//
//  Swift port of the Scientific notation formatter from Antimatter Dimensions.
//  Reads mantissa/exponent from break_infinity.js Decimal objects via JSValue,
//  formats identically to the JS format()/formatX()/formatInt() functions.
//

import Foundation
import JavaScriptCore

// MARK: - GameDecimal

/// Lightweight representation of a break_infinity.js Decimal.
/// mantissa is normalized: 1 ≤ |m| < 10 (or 0 for zero).
struct GameDecimal {
    let mantissa: Double
    let exponent: Int

    static let zero = GameDecimal(mantissa: 0, exponent: 0)

    var isZero: Bool { mantissa == 0 }
    var isInfinite: Bool { mantissa.isInfinite }
    var isNaN: Bool { mantissa.isNaN }

    /// Compare: self >= other (matching break_infinity.js Decimal.gte)
    func gte(_ other: GameDecimal) -> Bool {
        if mantissa == 0 { return other.mantissa <= 0 }
        if other.mantissa == 0 { return mantissa >= 0 }
        if mantissa > 0 && other.mantissa < 0 { return true }
        if mantissa < 0 && other.mantissa > 0 { return false }
        // Both positive
        if mantissa > 0 {
            if exponent != other.exponent { return exponent > other.exponent }
            return mantissa >= other.mantissa
        }
        // Both negative
        if exponent != other.exponent { return exponent < other.exponent }
        return mantissa >= other.mantissa
    }

    /// Reconstruct as a Double (only valid for small exponents).
    var toDouble: Double { mantissa * pow(10.0, Double(exponent)) }

    init(mantissa: Double, exponent: Int) {
        self.mantissa = mantissa
        self.exponent = exponent
    }

    init(double value: Double) {
        if value == 0 || value.isNaN || value.isInfinite {
            self = .zero
            return
        }
        let e = Int(floor(log10(abs(value))))
        self.mantissa = value / pow(10.0, Double(e))
        self.exponent = e
    }

    init(from jsValue: JSValue?) {
        // C-API fast path skips the JSValue ObjC wrapper mint per property read
        // (~50% of GameDecimal.init CPU under Instruments). Gated on UserDefaults
        // during validation. Debug builds run both paths and log any divergence.
        if gameDecimalUseCAPIFlag {
            #if DEBUG
            self.init(fastFrom: jsValue, divergenceCheck: true)
            #else
            self.init(fastFrom: jsValue)
            #endif
            return
        }
        guard let v = jsValue, !v.isUndefined, !v.isNull else {
            self = .zero
            return
        }
        let m = v.forProperty("mantissa")?.toDouble() ?? 0
        let e = v.forProperty("exponent")?.toDouble() ?? 0
        // Guard against Infinity/NaN and extreme exponents that would overflow Int
        let clampedExponent: Int
        if e.isFinite {
            if e > Double(Int.max / 2) { clampedExponent = Int.max / 2 }
            else if e < Double(Int.min / 2) { clampedExponent = Int.min / 2 }
            else { clampedExponent = Int(e) }
        } else {
            clampedExponent = e > 0 ? Int.max / 2 : 0
        }
        self.init(mantissa: m, exponent: clampedExponent)
    }
}

// MARK: - GameDecimal C API fast path
//
// `init(from:)` mints two ObjC JSValue wrappers (one per property read) plus
// the "mantissa"/"exponent" NSString bridges, all autoreleased. Instruments
// showed `-[JSContext wrapperForJSObject:]` consuming ~18ms of a 40ms
// capture window in `GameDecimal.init`, plus ARC overhead. The C-API path
// reads the same two Number properties without the wrapper layer.
//
// `cachedDecimalKeys` is populated once at startup by `initializeGameDecimalCAPI`
// (called from `GameEngine.start()` after the bundle loads). JSStringRef is
// context-independent and refcounted — we never release these strings; they
// live for the app's lifetime, costing one allocation each.

private struct CachedDecimalKeys {
    let mantissa: JSStringRef
    let exponent: JSStringRef
}

private nonisolated(unsafe) var cachedDecimalKeys: CachedDecimalKeys?

/// Idempotent. Safe to call from multiple start() entry points.
func initializeGameDecimalCAPI() {
    if cachedDecimalKeys != nil { return }
    guard let m = JSStringCreateWithUTF8CString("mantissa"),
          let e = JSStringCreateWithUTF8CString("exponent") else { return }
    cachedDecimalKeys = CachedDecimalKeys(mantissa: m, exponent: e)
}

/// Cached UserDefaults read. Updated by `setGameDecimalUseCAPI(_:)`. The flag is
/// read inside the GameDecimal init hot path so we cache it in a plain var
/// rather than hitting UserDefaults dozens of times per tick.
nonisolated(unsafe) var gameDecimalUseCAPIFlag: Bool =
    UserDefaults.standard.bool(forKey: "gameDecimalUseCAPI")

/// Toggle the C-API path at runtime. Persists to UserDefaults and updates the
/// cached flag. Call from the Debug tab.
func setGameDecimalUseCAPI(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: "gameDecimalUseCAPI")
    gameDecimalUseCAPIFlag = enabled
}

#if DEBUG
/// Tracks divergence between the legacy path and the C-API path. Logged
/// throttled — once per second — so a real divergence is loud without
/// flooding the console.
private nonisolated(unsafe) var lastDivergenceLogTime: TimeInterval = 0
private nonisolated(unsafe) var divergenceCount: Int = 0

private func logDivergence(legacyM: Double, legacyE: Int, fastM: Double, fastE: Int) {
    divergenceCount &+= 1
    let now = ProcessInfo.processInfo.systemUptime
    guard now - lastDivergenceLogTime > 1 else { return }
    lastDivergenceLogTime = now
    print("🔴 GameDecimal C-API divergence (#\(divergenceCount)): legacy=(\(legacyM), \(legacyE)) fast=(\(fastM), \(fastE))")
}
#endif

extension GameDecimal {
    /// Read mantissa/exponent via the JavaScriptCore C API. Bypasses the
    /// per-property ObjC JSValue wrapper. Falls back to `.zero` for any
    /// non-object or undefined input, matching the legacy initializer's
    /// behavior.
    init(fastFrom jsValue: JSValue?) {
        guard let v = jsValue, !v.isUndefined, !v.isNull,
              let keys = cachedDecimalKeys else {
            self = .zero
            return
        }
        let ctx = v.context.jsGlobalContextRef
        let valueRef = v.jsValueRef

        // Decimals are objects, but the legacy `forProperty` path also reads
        // primitive JSValues (Number, String, Boolean) via JS autoboxing —
        // looking up `.mantissa` on a Number returns `undefined`, which
        // `.toDouble()` then converts to NaN. The downstream clamp lets NaN
        // exponent flow to 0, and `formatDecimal`/`isNaN` short-circuit to
        // "0" on display. To match that behavior on this path (so the
        // divergence harness doesn't flag the bogus inputs), non-object
        // inputs yield (NaN, NaN) here rather than (0, 0).
        let m: Double
        let e: Double
        if JSValueIsObject(ctx, valueRef) {
            var exception: JSValueRef? = nil
            if let obj = JSValueToObject(ctx, valueRef, &exception),
               exception == nil {
                let mRef = JSObjectGetProperty(ctx, obj, keys.mantissa, &exception)
                m = (exception == nil && mRef != nil)
                    ? JSValueToNumber(ctx, mRef, &exception)
                    : .nan
                exception = nil
                let eRef = JSObjectGetProperty(ctx, obj, keys.exponent, &exception)
                e = (exception == nil && eRef != nil)
                    ? JSValueToNumber(ctx, eRef, &exception)
                    : .nan
            } else {
                m = .nan; e = .nan
            }
        } else {
            // Primitive (Number/String/Boolean) — legacy reads return
            // undefined → NaN after autoboxing missing-property lookups.
            m = .nan; e = .nan
        }

        self.mantissa = m
        // Same clamp logic as the legacy init — break_infinity.js exponents
        // can be arbitrarily large, but Int overflow on extreme values would
        // crash. Int.max/2 leaves headroom for downstream arithmetic.
        if e.isFinite {
            if e > Double(Int.max / 2) { self.exponent = Int.max / 2 }
            else if e < Double(Int.min / 2) { self.exponent = Int.min / 2 }
            else { self.exponent = Int(e) }
        } else {
            self.exponent = e > 0 ? Int.max / 2 : 0
        }
    }

    #if DEBUG
    /// Divergence-checked initializer used during validation. Runs both paths
    /// on the same JSValue and logs (throttled to 1/s) if they disagree on
    /// mantissa or exponent. Result returned is the fast path's value — the
    /// legacy path is a comparison-only baseline.
    init(fastFrom jsValue: JSValue?, divergenceCheck: Bool) {
        // Fast path
        self.init(fastFrom: jsValue)
        guard divergenceCheck else { return }

        // Compute legacy values for comparison without recursion through the
        // gated `init(from:)`.
        let legacyM: Double
        let legacyE: Int
        if let v = jsValue, !v.isUndefined, !v.isNull {
            legacyM = v.forProperty("mantissa")?.toDouble() ?? 0
            let e = v.forProperty("exponent")?.toDouble() ?? 0
            if e.isFinite {
                if e > Double(Int.max / 2) { legacyE = Int.max / 2 }
                else if e < Double(Int.min / 2) { legacyE = Int.min / 2 }
                else { legacyE = Int(e) }
            } else {
                legacyE = e > 0 ? Int.max / 2 : 0
            }
        } else {
            legacyM = 0
            legacyE = 0
        }

        // NaN ≠ NaN by IEEE rule, so compare bitwise for the mantissa to
        // catch genuine divergence including NaN-vs-NaN consistency.
        let mantissaMatches = self.mantissa.bitPattern == legacyM.bitPattern
        if !mantissaMatches || self.exponent != legacyE {
            logDivergence(
                legacyM: legacyM, legacyE: legacyE,
                fastM: self.mantissa, fastE: self.exponent
            )
        }
    }
    #endif
}

// MARK: - Suffix Parsing (input)

/// Suffix → exponent mapping for user input parsing (case-insensitive).
/// Ordered longest-first so "Qa" is checked before "Q" (not a real suffix, but safe).
private let suffixExponents: [(suffix: String, exponent: Int)] = [
    ("Qa", 15), ("Qt", 18), ("Sx", 21), ("Sp", 24), ("Oc", 27), ("No", 30),
    ("K", 3), ("M", 6), ("B", 9), ("T", 12),
]

/// Parse a user-typed number string that may use suffix notation (e.g. "16M", "1.5 B", "100t")
/// into a string compatible with the JS `Decimal` constructor (scientific notation or plain number).
/// Pass-through for scientific notation (`1e7`, `e15`) and plain numbers.
func parseDecimalInput(_ input: String) -> String {
    let cleaned = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
    guard !cleaned.isEmpty else { return input }

    // Already scientific notation or shorthand exponent — pass through
    let lower = cleaned.lowercased()
    if lower.hasPrefix("e") && Double(String(lower.dropFirst())) != nil {
        return cleaned
    }
    if cleaned.contains("e") || cleaned.contains("E") {
        // e.g. "1e7", "2.5E6" — JS Decimal handles these
        return cleaned
    }

    // Try matching a suffix at the end (case-insensitive)
    for (suffix, exp) in suffixExponents {
        if lower.hasSuffix(suffix.lowercased()) {
            let numPart = String(cleaned.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            if let value = Double(numPart) {
                // Convert value × 10^exp to scientific notation
                let result = value * pow(10.0, Double(exp))
                if result.isInfinite || result.isNaN {
                    return cleaned
                }
                if result < 1e21 {
                    // Small enough for a plain integer string
                    return String(format: "%.0f", result)
                }
                // Use scientific notation for large values
                let e = Int(floor(log10(result)))
                let m = result / pow(10.0, Double(e))
                return "\(m)e\(e)"
            }
        }
    }

    // Plain number — return as-is
    return cleaned
}

// MARK: - Notation selection

/// Notations ported natively to Swift. The web game supports 22 — we surface only
/// the five "serious" ones; the rest silently fall back to `.mixedScientific`.
enum GameNotation: String, CaseIterable {
    case scientific        = "Scientific"
    case engineering       = "Engineering"
    case letters           = "Letters"
    case mixedScientific   = "Mixed scientific"
    case mixedEngineering  = "Mixed engineering"

    static let supportedNames: Set<String> = Set(allCases.map(\.rawValue))
}

/// Global formatter state. pollDirect's main-thread dispatch writes this; all
/// `formatDecimal` callers are on main, so a plain var is safe.
enum NotationFormatter {
    nonisolated(unsafe) static var current: GameNotation = .mixedScientific
}

// MARK: - Formatting

/// Standard notation suffixes (exponent 3 = K, 6 = M, etc.)
/// Matches the web game's MixedScientific default: Standard for e < 33, Scientific for e >= 33.
private let standardSuffixes = ["K", "M", "B", "T", "Qa", "Qt", "Sx", "Sp", "Oc", "No"]

/// Lowercase a-z — matches ADNotations' `LettersNotation` letter set.
private let lettersAlphabet: [Character] = Array("abcdefghijklmnopqrstuvwxyz")

/// Matches the game's `format(value, places, placesUnder1000)`. Dispatches on
/// `NotationFormatter.current`. Scientific / Engineering / Letters / Mixed
/// variants are all handled natively.
func formatDecimal(_ d: GameDecimal, places: Int = 0, placesUnder1000: Int = 0) -> String {
    if d.isNaN { return "0" }
    if d.isInfinite { return d.mantissa < 0 ? "-Infinite" : "Infinite" }

    let negative = d.mantissa < 0
    let absMantissa = abs(d.mantissa)
    let sign = negative ? "-" : ""

    // Very small: exponent < -300
    if d.exponent < -300 {
        if absMantissa == 0 { return "0" }
        return "\(sign)\(formatFixed(0, placesUnder1000))"
    }

    // Under 1000: exponent < 3 — all notations fall back to plain fixed-point.
    if d.exponent < 3 {
        let value = absMantissa * pow(10.0, Double(d.exponent))
        return "\(sign)\(formatFixed(value, placesUnder1000))"
    }

    // Renormalize mantissa to [1, 10) if needed
    var m = absMantissa
    var e = d.exponent
    if m > 0 && !(1 <= m && m < 10) {
        let adjust = Int(floor(log10(m)))
        m /= pow(10.0, Double(adjust))
        e += adjust
    }

    switch NotationFormatter.current {
    case .mixedScientific:
        if e < 33 { return formatStandardSuffix(sign: sign, m: m, e: e, places: places) }
        return formatScientific(sign: sign, m: m, e: e, places: places)
    case .mixedEngineering:
        if e < 33 { return formatStandardSuffix(sign: sign, m: m, e: e, places: places) }
        return formatEngineering(sign: sign, m: m, e: e, places: places)
    case .scientific:
        return formatScientific(sign: sign, m: m, e: e, places: places)
    case .engineering:
        return formatEngineering(sign: sign, m: m, e: e, places: places)
    case .letters:
        return formatLetters(sign: sign, m: m, e: e, places: places)
    }
}

/// Standard (K/M/B/T/Qa/...) — shared by Mixed Scientific and Mixed Engineering
/// for exponent 3..32.
private func formatStandardSuffix(sign: String, m: Double, e: Int, places: Int) -> String {
    let suffixIndex = e / 3 - 1 // 3→0(K), 6→1(M), 9→2(B), ...
    if suffixIndex >= 0 && suffixIndex < standardSuffixes.count {
        let suffix = standardSuffixes[suffixIndex]
        let remainder = e % 3
        let displayValue = m * pow(10.0, Double(remainder))
        return "\(sign)\(formatFixed(displayValue, places)) \(suffix)"
    }
    // Fallback (shouldn't hit for e < 33).
    return formatScientific(sign: sign, m: m, e: e, places: places)
}

/// Scientific — `m.mm e EXP`. Handles rounding-up to 10.
private func formatScientific(sign: String, m: Double, e: Int, places: Int) -> String {
    var mantissa = m
    var exponent = e
    let mStr = formatFixed(mantissa, places)
    let p = max(0, places)
    let tenStr = p < formattedTen.count ? formattedTen[p] : formatFixed(10, p)
    if mStr == tenStr {
        mantissa = 1
        exponent += 1
    }
    let finalStr = formatFixed(mantissa, places)
    if exponent == 0 { return "\(sign)\(finalStr)" }
    return "\(sign)\(finalStr)e\(formatExponent(exponent))"
}

/// Engineering — exponent rounded down to a multiple of 3, mantissa in [1, 1000).
private func formatEngineering(sign: String, m: Double, e: Int, places: Int) -> String {
    let remainder = ((e % 3) + 3) % 3
    var mantissa = m * pow(10.0, Double(remainder))
    var exponent = e - remainder
    // Rounding guard: if toFixed pushes mantissa to "1000.00", shift one step.
    let mStr = formatFixed(mantissa, places)
    let p = max(0, places)
    let thousandStr = p < formattedThousand.count ? formattedThousand[p] : formatFixed(1000, p)
    if mStr == thousandStr {
        mantissa = 1
        exponent += 3
    }
    let finalStr = formatFixed(mantissa, places)
    if exponent == 0 { return "\(sign)\(finalStr)" }
    return "\(sign)\(finalStr)e\(formatExponent(exponent))"
}

/// Letters — engineering mantissa + a letter sequence (a, b, c, ..., z, aa, ab, ...).
/// Matches ADNotations' `LettersNotation` (extends `CustomNotation`, base 26).
private func formatLetters(sign: String, m: Double, e: Int, places: Int) -> String {
    let remainder = ((e % 3) + 3) % 3
    var mantissa = m * pow(10.0, Double(remainder))
    var exponent = e - remainder
    let mStr = formatFixed(mantissa, places)
    let p = max(0, places)
    let thousandStr = p < formattedThousand.count ? formattedThousand[p] : formatFixed(1000, p)
    if mStr == thousandStr {
        mantissa = 1
        exponent += 3
    }
    let finalStr = formatFixed(mantissa, places)
    if exponent == 0 { return "\(sign)\(finalStr)" }
    return "\(sign)\(finalStr)\(lettersTranscribe(exponent))"
}

/// Transcribe `exponent` (multiple of 3) to a letter sequence — mirrors
/// `CustomNotation.prototype.transcribe` with `letters = "a..z"`, base = 26.
private func lettersTranscribe(_ rawExponent: Int) -> String {
    let base = lettersAlphabet.count
    var normalized = rawExponent / 3
    if normalized <= 0 { return "" }
    if normalized <= base {
        return String(lettersAlphabet[normalized - 1])
    }
    var out: [Character] = []
    while normalized > base {
        let remainder = normalized % base
        let letterIndex = (remainder == 0 ? base : remainder) - 1
        out.append(lettersAlphabet[letterIndex])
        normalized = (normalized - remainder) / base
        if remainder == 0 { normalized -= 1 }
    }
    out.append(lettersAlphabet[normalized - 1])
    return String(out.reversed())
}

/// Matches the game's `formatX(value, places, placesUnder1000)`.
func formatX(_ d: GameDecimal, places: Int = 2, placesUnder1000: Int = 2) -> String {
    "×\(formatDecimal(d, places: places, placesUnder1000: placesUnder1000))"
}

/// Format a plain JS number (not a break_infinity Decimal) for display.
/// Uses standard suffixes (K, M, B, T, ...) for 1e3–1e32, then scientific notation.
func formatPlainNumber(_ value: Double) -> String {
    if value.isNaN || value == 0 { return "0" }
    if abs(value) < 1000 {
        if value == value.rounded() {
            return addCommas(String(Int(value)))
        }
        return String(format: "%.2f", value)
    }
    // Delegate to formatDecimal for consistent suffix/scientific formatting
    return formatDecimal(GameDecimal(double: value), places: 2, placesUnder1000: 2)
}

/// Mirrors the web autobuyer interval input's `value.toString()` display
/// (`AutobuyerInput.vue` float type). Shows whole numbers without a decimal
/// point and fractional values with their significant digits intact — so
/// sub-0.1s intervals (down to 0, "buy max every tick") render faithfully
/// instead of being rounded to one decimal place.
func formatAutobuyerInterval(_ value: Double) -> String {
    if value.isNaN { return "0" }
    if value == value.rounded() && abs(value) < 1e15 {
        return String(Int(value))
    }
    return String(value)
}

/// Matches the game's `formatInt(value)` — integer with commas.
func formatInt(_ value: Int) -> String {
    addCommas(String(value))
}

/// Matches the game's `formatInt(value)` for Decimals.
/// Web does `formatWithCommas(value.toNumber().toFixed(0))` — plain integer with commas
/// for any representable value, falling back to notation for very large numbers.
func formatInt(_ d: GameDecimal) -> String {
    if d.isNaN { return "0" }
    if d.isInfinite { return "Infinite" }
    // Double has ~15 significant digits; for exponent < 15 we can reconstruct
    // the exact integer string with commas (matching web's toFixed(0) behavior).
    if d.exponent < 15 {
        let v = Int(round(d.toDouble))
        return addCommas(String(v))
    }
    // Very large: fall through to standard format
    return formatDecimal(d, places: 0, placesUnder1000: 0)
}

/// Format the exponent part, matching the game's `Notation.formatExponent()`.
///
/// - exponent < 100,000: plain number string
/// - exponent < 1,000,000,000: comma-separated
/// - exponent >= 1,000,000,000: recursive scientific notation
private func formatExponent(_ exponent: Int) -> String {
    let absExp = abs(exponent)
    let sign = exponent < 0 ? "-" : ""

    if absExp < 100_000 {
        return "\(sign)\(absExp)"
    }
    if absExp < 1_000_000_000 {
        return "\(sign)\(addCommas(String(absExp)))"
    }
    // Recursive: format the exponent itself as a Decimal in scientific notation
    let expDecimal = GameDecimal(mantissa: Double(exponent) / pow(10.0, floor(log10(Double(absExp)))),
                                 exponent: Int(floor(log10(Double(absExp)))))
    return formatDecimal(expDecimal, places: 2, placesUnder1000: 2)
}

// MARK: - Helpers

/// Pre-built format strings for `formatFixed`. Avoids per-call interpolation
/// of `"%.\(p)f"`. Covers every `places` value the formatters actually use;
/// larger `p` falls through to runtime interpolation.
private let fixedFormatStrings: [String] = (0...6).map { "%.\($0)f" }

/// Pre-rendered `formatFixed(10, places)` / `formatFixed(1000, places)` values
/// for the round-up overflow check in `formatScientific` / `formatEngineering`
/// / `formatLetters`. Each call site previously paid an extra
/// `String(format: "%.\(p)f", 10.0)` allocation just to compare against the
/// just-computed mantissa string. Hardcoded since these are constants.
private let formattedTen: [String] = [
    "10", "10.0", "10.00", "10.000", "10.0000", "10.00000", "10.000000",
]
private let formattedThousand: [String] = [
    "1000", "1000.0", "1000.00", "1000.000", "1000.0000", "1000.00000", "1000.000000",
]

/// Fixed-point format matching JS Number.toFixed().
private func formatFixed(_ value: Double, _ places: Int) -> String {
    let p = max(0, places)
    let fmt = p < fixedFormatStrings.count ? fixedFormatStrings[p] : "%.\(p)f"
    return String(format: fmt, value)
}

/// Insert commas every 3 digits in the integer part. Single-pass build with
/// pre-reserved capacity — avoids the prior `split` + double-`reversed`
/// allocations. Called at 30Hz on every header `formatInt(...)` plus the
/// Dim Boost / Galaxy counts.
private func addCommas(_ value: String) -> String {
    // Locate the decimal point (if any). Integer part is everything before it.
    let dotIndex = value.firstIndex(of: ".")
    let intEnd = dotIndex ?? value.endIndex
    let intSubstring = value[value.startIndex..<intEnd]

    // Strip the sign so the digit grouping math is straightforward.
    let negative = intSubstring.first == "-"
    let digits = negative ? intSubstring.dropFirst() : intSubstring
    let digitCount = digits.count

    // Fast path: no commas needed for ≤3 integer digits. Bypasses all allocation
    // for the common single-digit / under-1000 case.
    if digitCount <= 3 { return value }

    // Capacity: digits + (digitCount-1)/3 commas + optional minus + optional
    // dot + fractional part. Over-reserves by at most a handful of bytes.
    var out = String()
    out.reserveCapacity(value.count + digitCount / 3)
    if negative { out.append("-") }

    // First group is whatever's left over after taking 3-digit groups from the
    // right (1, 2, or 3 digits). Then all subsequent groups are exactly 3 with
    // a leading comma.
    let firstGroupSize = digitCount % 3 == 0 ? 3 : digitCount % 3
    let firstGroupEnd = digits.index(digits.startIndex, offsetBy: firstGroupSize)
    out.append(contentsOf: digits[digits.startIndex..<firstGroupEnd])

    var groupStart = firstGroupEnd
    while groupStart < digits.endIndex {
        out.append(",")
        let groupEnd = digits.index(groupStart, offsetBy: 3)
        out.append(contentsOf: digits[groupStart..<groupEnd])
        groupStart = groupEnd
    }

    if let dotIndex {
        out.append(contentsOf: value[dotIndex...])
    }
    return out
}
