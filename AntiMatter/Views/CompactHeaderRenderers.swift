//
//  CompactHeaderRenderers.swift
//  AntiMatter
//
//  CATextLayer-backed renderers for iPhone header text that updates at 30Hz.
//  Bypasses SwiftUI `ResolvedTextFilter` on:
//    - `NotchCurrencyLabel` (EP/IP in notch area)
//    - Prestige button labels (`compactEternityButton`, `compactCrunchButton`,
//      `compactRealityButton` label bodies)
//
//  The SwiftUI `Button` shell (tap handling, background, border, glow modifier,
//  opacity) stays — we only replace the inner `Text` bodies.
//

import SwiftUI
import UIKit

// MARK: - Notch currency label

struct NotchCurrencyLabelRenderer: UIViewRepresentable {
    let value: String
    let suffix: String
    let color: Color

    func makeUIView(context: Context) -> NotchCurrencyLabelView {
        NotchCurrencyLabelView()
    }

    func updateUIView(_ uiView: NotchCurrencyLabelView, context: Context) {
        uiView.update(value: value, suffix: suffix, color: UIColor(color))
    }
}

final class NotchCurrencyLabelView: UIView {
    private let textLayer = CATextLayer()

    private var cachedValue: String?
    private var cachedSuffix: String?
    private var cachedColorCG: CGColor?
    private var cachedWidth: CGFloat = 0

    private static let valueFontUI = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
    private static let suffixFontUI = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    private static let suffixColor = UIColor.white.withAlphaComponent(0.5)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        textLayer.actions = [
            "string": NSNull(), "contents": NSNull(),
            "foregroundColor": NSNull()
        ]
        textLayer.contentsScale = traitCollection.displayScale
        textLayer.alignmentMode = .left
        textLayer.truncationMode = .end
        self.layer.addSublayer(textLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        textLayer.frame = bounds
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: cachedWidth, height: 17)
    }

    func update(value: String, suffix: String, color: UIColor) {
        let colorChanged = (cachedColorCG.map { $0 != color.cgColor } ?? true)
        if value == cachedValue && suffix == cachedSuffix && !colorChanged { return }
        cachedValue = value
        cachedSuffix = suffix
        cachedColorCG = color.cgColor

        let attr = NSMutableAttributedString(
            string: value,
            attributes: [
                .font: Self.valueFontUI,
                .foregroundColor: color
            ]
        )
        attr.append(NSAttributedString(
            string: " \(suffix)",
            attributes: [
                .font: Self.suffixFontUI,
                .foregroundColor: Self.suffixColor
            ]
        ))
        textLayer.string = attr

        let measured = attr.size()
        let w = ceil(measured.width)
        if w != cachedWidth {
            cachedWidth = w
            invalidateIntrinsicContentSize()
        }
    }
}

// MARK: - Two-tone inline label (localized format + colored value substring)
//
// Powers `CompactRMDisplay` ("You have X Reality Machines") and
// `CompactRealityShardsDisplay` ("You have X Reality Shards."). The
// call site passes a pre-localized string built via String(localized:)
// (which the String Catalog extracts as "You have %@ Reality Machines")
// plus the value substring as a separate argument. The renderer finds
// the value's range inside the formatted text and colors that range —
// preserving the SwiftUI `Text("You have \(Text(rm).color) Reality
// Machines")` localization shape that the catalog can extract from.

struct TwoToneInlineLabelRenderer: UIViewRepresentable {
    /// Fully-localized text including the substituted value
    /// (e.g. "You have 1.23e45 Reality Machines").
    let formattedText: String
    /// The value substring inside `formattedText` that should be colored.
    /// Must appear as a unique substring; for our formatted numbers it
    /// always does.
    let valueSubstring: String
    let valueColor: Color
    let surroundColor: Color
    let font: UIFont

    func makeUIView(context: Context) -> TwoToneInlineLabelView {
        TwoToneInlineLabelView()
    }

    func updateUIView(_ uiView: TwoToneInlineLabelView, context: Context) {
        uiView.update(
            formattedText: formattedText,
            valueSubstring: valueSubstring,
            valueColor: UIColor(valueColor),
            surroundColor: UIColor(surroundColor),
            font: font
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView: TwoToneInlineLabelView,
                      context: Context) -> CGSize? {
        let intrinsic = uiView.intrinsicContentSize
        let w = proposal.width ?? intrinsic.width
        let h = proposal.height ?? intrinsic.height
        return CGSize(width: w, height: h)
    }
}

final class TwoToneInlineLabelView: UIView {
    private let textLayer = CATextLayer()

    private var cachedFormattedText: String?
    private var cachedValueSubstring: String?
    private var cachedValueColorCG: CGColor?
    private var cachedSurroundColorCG: CGColor?
    private var cachedFontID: ObjectIdentifier?
    private var measuredSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        textLayer.actions = [
            "string": NSNull(), "contents": NSNull(),
            "foregroundColor": NSNull(), "bounds": NSNull(),
            "position": NSNull()
        ]
        textLayer.contentsScale = traitCollection.displayScale
        textLayer.alignmentMode = .center
        textLayer.truncationMode = .end
        self.layer.addSublayer(textLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        textLayer.frame = bounds
    }

    override var intrinsicContentSize: CGSize { measuredSize }

    func update(formattedText: String, valueSubstring: String,
                valueColor: UIColor, surroundColor: UIColor, font: UIFont) {
        let fontID = ObjectIdentifier(font)
        let textChanged = formattedText != cachedFormattedText
        let valueChanged = valueSubstring != cachedValueSubstring
        let valueColorChanged = (cachedValueColorCG.map { $0 != valueColor.cgColor } ?? true)
        let surroundColorChanged = (cachedSurroundColorCG.map { $0 != surroundColor.cgColor } ?? true)
        let fontChanged = fontID != cachedFontID

        guard textChanged || valueChanged
            || valueColorChanged || surroundColorChanged || fontChanged else { return }

        cachedFormattedText = formattedText
        cachedValueSubstring = valueSubstring
        cachedValueColorCG = valueColor.cgColor
        cachedSurroundColorCG = surroundColor.cgColor
        cachedFontID = fontID

        let attr = NSMutableAttributedString(string: formattedText, attributes: [
            .font: font, .foregroundColor: surroundColor
        ])
        // Color the value range, if found. If the value substring isn't
        // present (e.g. localization quirk or empty value), the whole
        // string just renders in `surroundColor`.
        if !valueSubstring.isEmpty,
           let range = formattedText.range(of: valueSubstring) {
            let nsRange = NSRange(range, in: formattedText)
            attr.addAttribute(.foregroundColor, value: valueColor, range: nsRange)
        }
        textLayer.string = attr

        let measured = attr.size()
        let newSize = CGSize(width: ceil(measured.width),
                             height: ceil(measured.height * 1.2))
        if newSize != measuredSize {
            measuredSize = newSize
            invalidateIntrinsicContentSize()
        }
    }
}

// MARK: - Prestige button label renderers
//
// All three share the same structural shape: up to 3 stacked text lines
// (primary bold + up to 2 secondary lines), foreground color passed in,
// state-driven branching. Implemented as a single `PrestigeLabelView` with
// three `CATextLayer` sublayers; each renderer picks which lines to show
// and what strings to set based on its own state struct.

struct CompactEternityLabelRenderer: UIViewRepresentable {
    let inf: InfinityState
    let color: Color

    func makeUIView(context: Context) -> PrestigeLabelView {
        PrestigeLabelView()
    }

    func updateUIView(_ v: PrestigeLabelView, context: Context) {
        let cg = UIColor(color).cgColor
        if inf.isInEternityChallenge && !inf.canEternity {
            v.setOne(primary: "Reach \(inf.eternityGoal) IP", color: cg)
        } else if inf.isInEternityChallenge && inf.canEternity {
            if inf.ecFullyCompleted {
                v.setTwo(
                    primary: "Other challenges\nawait...",
                    secondary: "(Already completed)",
                    primaryMultiline: true,
                    color: cg
                )
            } else if inf.ecHasMoreCompletions && !inf.ecNextGoalAt.isEmpty {
                v.setTwo(
                    primary: "\(inf.ecGainedCompletions) completion\(inf.ecGainedCompletions == 1 ? "" : "s")",
                    secondary: "Next goal at \(inf.ecNextGoalAt) IP",
                    color: cg
                )
            } else if !inf.ecFailedRestriction.isEmpty {
                v.setTwo(
                    primary: "\(inf.ecGainedCompletions) completion\(inf.ecGainedCompletions == 1 ? "" : "s")",
                    secondary: inf.ecFailedRestriction,
                    color: cg
                )
            } else {
                v.setTwo(
                    primary: "Other challenges\nawait...",
                    secondary: "\(inf.ecGainedCompletions) completion\(inf.ecGainedCompletions == 1 ? "" : "s")",
                    primaryMultiline: true,
                    color: cg
                )
            }
        } else if !inf.canEternity {
            v.setOne(primary: "Reach \(inf.eternityGoal) IP", color: cg)
        } else if !inf.eternityUnlocked {
            v.setOne(primary: "Become Eternal", color: cg)
        } else if inf.isDilationActive {
            // Dilation-mode label mirrors web `EternityButton.vue:231`.
            // Three-line layout so long tachyon values don't truncate:
            //   "Eternity for" / "{value}" / "TP"
            v.setThree(primary: "Eternity for",
                       secondary: inf.dilationTachyonGain,
                       tertiary: "TP",
                       secondaryFontSize: 12,
                       tertiaryFontSize: 11,
                       color: cg)
        } else if inf.showEPRate {
            v.setThree(
                primary: "Eternity for \(inf.gainedEP) EP",
                secondary: "Current: \(inf.currentEPRate) EP/min",
                tertiary: "Peak: \(inf.peakEPRate) EP/min\nat \(inf.peakEPRateVal) EP",
                color: cg
            )
        } else {
            // Mirrors web `EternityButton.vue:210-213`. Three lines — value
            // gets its own full-width line so long EP numbers (1.95e37,348,715)
            // wrap/shrink without truncating; unit "EP" sits below as its own line.
            v.setThree(primary: "Eternity for",
                       secondary: inf.gainedEP,
                       tertiary: "EP",
                       secondaryFontSize: 12,
                       tertiaryFontSize: 11,
                       color: cg)
        }
    }
}

struct CompactCrunchLabelRenderer: UIViewRepresentable {
    let inf: InfinityState
    let tessGlow: Bool
    let color: Color

    func makeUIView(context: Context) -> PrestigeLabelView {
        PrestigeLabelView()
    }

    func updateUIView(_ v: PrestigeLabelView, context: Context) {
        let cg = UIColor(color).cgColor
        if tessGlow {
            v.setOne(primary: "Enough IP for a Tesseract", color: cg)
        } else if inf.canCrunch {
            if inf.inAntimatterChallenge {
                v.setOne(primary: "Big Crunch (Complete)", color: cg)
            } else if inf.showIPRate {
                // 3 visual lines so the content fits in the base 80pt
                // prestige slot. Peak rate + the AM at peak are combined
                // onto one line ("Peak: X IP/min @ Y IP") with
                // auto-shrink rather than wrapped via `\n`. Keeps the
                // header from growing to fit a 4-line variant that
                // would force every other prestige button (UnlockID,
                // Eternity, etc.) in the same HStack to share the
                // taller envelope.
                v.setThree(
                    primary: "Crunch for \(inf.gainedIP) IP",
                    secondary: "Current: \(inf.currentIPRate) IP/min",
                    tertiary: "Peak: \(inf.peakIPRate) IP/min @ \(inf.peakIPRateVal) IP",
                    color: cg
                )
            } else {
                // Mirrors web `BigCrunchButton.vue:130-133`. Three lines —
                // value on its own row so long IP numbers wrap/shrink without
                // truncating; "IP" sits below as its own line.
                v.setThree(primary: "Big Crunch for",
                           secondary: inf.gainedIP,
                           tertiary: "IP",
                           secondaryFontSize: 12,
                           tertiaryFontSize: 11,
                           color: cg)
            }
        } else {
            v.setOne(primary: "Reach \(inf.infinityGoal)", color: cg)
        }
    }
}

struct CompactRealityLabelRenderer: UIViewRepresentable {
    let inf: InfinityState
    let needsStudy: Bool
    let color: Color

    func makeUIView(context: Context) -> PrestigeLabelView {
        PrestigeLabelView()
    }

    func updateUIView(_ v: PrestigeLabelView, context: Context) {
        let cg = UIColor(color).cgColor
        if needsStudy {
            v.setTwo(primary: "Buy Reality study", secondary: "in Time Studies",
                     secondaryFontSize: 11, color: cg)
        } else if !inf.canReality {
            v.setOne(primary: "Reach 1e4000 EP", color: cg)
        } else {
            // Matches Vue RealityButton.vue:149-156. Web combines
            // `formatMachinesGained` + `formatMachineStats` on one row;
            // we split them so the cap/stats line stays legible at iPhone
            // width without crushing the machines-gained value.
            //   Line 1: "Make a new Reality"
            //   Line 2: gainedRM  (e.g. "No Machines gained")
            //   Line 3: machineStats (e.g. "(iM Cap: 37)") — hidden if empty
            //   Line 4: gainedGlyphLevel
            if inf.machineStats.isEmpty {
                // Allow `gainedRM` to wrap to a second line when it's too long
                // to fit at 12pt bold (e.g. "Machines gained: 2.49e928,815" at
                // late game). Earlier in the game (Effarig stage) the value is
                // short enough that this is a no-op; once RM gains balloon the
                // wrap kicks in instead of leaving a "Machines gained: 2.49e…"
                // ellipsis-truncation.
                v.setThree(
                    primary: "Make a new Reality",
                    secondary: inf.gainedRM,
                    tertiary: inf.gainedGlyphLevel,
                    secondaryFontSize: 12,  // bold, pairs with primary
                    secondaryWraps: true,
                    tertiaryFontSize: 12,   // match glyph level readability
                    color: cg
                )
            } else {
                v.setFour(
                    primary: "Make a new Reality",
                    secondary: inf.gainedRM,
                    tertiary: inf.machineStats,
                    quaternary: inf.gainedGlyphLevel,
                    secondaryWraps: true,
                    color: cg
                )
            }
        }
    }
}

// MARK: - Prestige label view (shared by all three prestige buttons)

final class PrestigeLabelView: UIView {
    private let line1 = CATextLayer()   // primary (bold, 12pt)
    private let line2 = CATextLayer()   // secondary (11pt default, 12pt bold, or 10pt for rate captions)
    private let line3 = CATextLayer()   // tertiary (10pt default, 11pt for Reality 4-line)
    private let line4 = CATextLayer()   // quaternary (11pt; only used by the Reality 4-line variant)

    // State — drives layoutSubviews. Setters update state and call
    // setNeedsLayout(); performLayout() does frame + auto-shrink fontSize.
    private var text1: String?          // nil = hidden
    private var text2: String?
    private var text3: String?
    private var text4: String?
    private var currentColorCG: CGColor = UIColor.white.cgColor
    private var primaryMultiline = false
    private var secondaryWraps = false
    private var secondaryBaseSize: CGFloat = 11
    private var tertiaryBaseSize: CGFloat = 10
    private var quaternaryBaseSize: CGFloat = 11

    /// Measured content height — updated by performLayout(), drives
    /// intrinsicContentSize so the SwiftUI Button (via UIViewRepresentable)
    /// can grow to fit 2-line primaries or 3-line rate mode.
    private var measuredHeight: CGFloat = 12

    // Base font sizes (pre-shrink). Auto-shrink can reduce these to 0.7x min,
    // matching SwiftUI's `.minimumScaleFactor(0.7)` behavior in the original.
    private static let primaryBaseSize: CGFloat = 12
    private static let tertiaryBaseSize: CGFloat = 10
    private static let minScale: CGFloat = 0.7

    private static let boldFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
    private static let regularFont12 = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    private static let smallFont9 = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let smallFont8 = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        for layer in [line1, line2, line3, line4] {
            layer.actions = [
                "string": NSNull(), "contents": NSNull(),
                "foregroundColor": NSNull(), "hidden": NSNull(),
                "opacity": NSNull(), "bounds": NSNull(),
                "position": NSNull(), "fontSize": NSNull()
            ]
            layer.contentsScale = traitCollection.displayScale
            layer.alignmentMode = .center
            layer.truncationMode = .end
            layer.isHidden = true
            self.layer.addSublayer(layer)
        }
        // Primary wraps to 2 lines when too long (e.g. "Reality No Machines
        // gained"). Secondary opts in to wrapping (Reality 4-line variant);
        // tertiary always wraps; quaternary stays single-line and auto-shrinks.
        line1.isWrapped = true
        line1.font = Self.boldFont
        line2.isWrapped = true
        line3.isWrapped = true
        line3.font = Self.smallFont8
        line4.font = Self.smallFont9
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        performLayout()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: measuredHeight)
    }

    private func performLayout() {
        let w = bounds.width
        let h = bounds.height
        let show1 = text1 != nil
        let show2 = text2 != nil
        let show3 = text3 != nil
        let show4 = text4 != nil
        let count = (show1 ? 1 : 0) + (show2 ? 1 : 0) + (show3 ? 1 : 0) + (show4 ? 1 : 0)
        guard count > 0, w > 0, h > 0 else { return }

        // Primary line: wraps to 2 lines if content is too wide at baseSize.
        // Explicit `\n` in text also triggers 2-line height.
        let primaryNeedsTwoLines: Bool = {
            guard let t = text1 else { return false }
            if primaryMultiline || t.contains("\n") { return true }
            let natural = (t as NSString).size(withAttributes: [.font: Self.boldFont]).width
            return natural > w
        }()
        // 12pt bold system has ~14.7pt line height — two lines measure at
        // ~30pt. 28pt clipped the second line and CATextLayer fell back to
        // single-line ellipsis truncation, so we give it honest breathing
        // room (2× lineHeight rounded up) instead of an eyeballed value.
        let twoLineH = ceil(Self.boldFont.lineHeight * 2)
        let primaryH: CGFloat = primaryNeedsTwoLines ? twoLineH : 13
        // Bold secondary (>=12pt) pairs with the primary line height.
        let secondaryFontForLayout: UIFont = {
            switch secondaryBaseSize {
            case 12: return Self.boldFont
            case 10: return Self.smallFont8
            default: return Self.smallFont9
            }
        }()
        let secondaryNeedsTwoLines: Bool = {
            guard secondaryWraps, let t = text2 else { return false }
            let natural = (t as NSString).size(withAttributes: [.font: secondaryFontForLayout]).width
            return natural > w
        }()
        let secondarySingleH: CGFloat = secondaryBaseSize >= 12 ? 13 : 12
        let secondaryH: CGFloat = secondaryNeedsTwoLines
            ? ceil(secondaryFontForLayout.lineHeight * 2)
            : secondarySingleH
        let tertiaryWraps = (text3?.contains("\n") ?? false)
        // Tertiary height tracks font size — 12pt needs ~13pt line, 11pt
        // regular needs ~12pt, 10pt needs ~11pt. Wrapping doubles either way.
        let tertiarySingleH: CGFloat = tertiaryBaseSize >= 12 ? 13 : (tertiaryBaseSize >= 11 ? 12 : 11)
        let tertiaryH: CGFloat = tertiaryWraps ? tertiarySingleH * 2 : tertiarySingleH
        let quaternaryH: CGFloat = quaternaryBaseSize >= 12 ? 13 : (quaternaryBaseSize >= 11 ? 12 : 11)

        var totalH: CGFloat = 0
        if show1 { totalH += primaryH }
        if show2 { totalH += secondaryH }
        if show3 { totalH += tertiaryH }
        if show4 { totalH += quaternaryH }

        // Report measured height to SwiftUI so the Button can grow when
        // the label has multiple lines (EC, rate mode, wrapped primary).
        if measuredHeight != totalH {
            measuredHeight = totalH
            invalidateIntrinsicContentSize()
        }

        var y = max(0, (h - totalH) / 2)

        if show1, let t = text1 {
            line1.frame = CGRect(x: 0, y: y, width: w, height: primaryH)
            applyWrap(line1, text: t, font: Self.boldFont, baseSize: Self.primaryBaseSize)
            line1.foregroundColor = currentColorCG
            line1.isHidden = false
            y += primaryH
        } else {
            line1.isHidden = true
        }

        if show2, let t = text2 {
            line2.frame = CGRect(x: 0, y: y, width: w, height: secondaryH)
            // Font selection by secondary size: 12 → bold (match primary),
            // 10 → regular small (rate lines in 3-line mode),
            // otherwise → regular (default for captions/subtitles).
            if secondaryNeedsTwoLines {
                applyWrap(line2, text: t, font: secondaryFontForLayout, baseSize: secondaryBaseSize)
            } else {
                applyShrink(line2, text: t, font: secondaryFontForLayout, baseSize: secondaryBaseSize, width: w)
            }
            line2.foregroundColor = currentColorCG
            line2.isHidden = false
            y += secondaryH
        } else {
            line2.isHidden = true
        }

        if show3, let t = text3 {
            line3.frame = CGRect(x: 0, y: y, width: w, height: tertiaryH)
            // Tertiary font tracks size: 12pt uses regularFont12, 11pt uses
            // smallFont9, 10pt uses smallFont8.
            let tertFont: UIFont = tertiaryBaseSize >= 12
                ? Self.regularFont12
                : (tertiaryBaseSize >= 11 ? Self.smallFont9 : Self.smallFont8)
            line3.font = tertFont
            applyShrink(line3, text: t, font: tertFont, baseSize: tertiaryBaseSize, width: w)
            line3.foregroundColor = currentColorCG
            line3.isHidden = false
            y += tertiaryH
        } else {
            line3.isHidden = true
        }

        if show4, let t = text4 {
            line4.frame = CGRect(x: 0, y: y, width: w, height: quaternaryH)
            let quatFont: UIFont = quaternaryBaseSize >= 12 ? Self.regularFont12 : Self.smallFont9
            line4.font = quatFont
            applyShrink(line4, text: t, font: quatFont, baseSize: quaternaryBaseSize, width: w)
            line4.foregroundColor = currentColorCG
            line4.isHidden = false
        } else {
            line4.isHidden = true
        }
    }

    /// Primary-line applier: sets string at `baseSize` and lets CATextLayer
    /// wrap to 2 lines when too wide. Preferred over shrink for readability
    /// (e.g. "Reality No Machines gained" wraps instead of shrinking to 7pt).
    private func applyWrap(_ layer: CATextLayer, text: String, font: UIFont, baseSize: CGFloat) {
        layer.font = font
        layer.string = text
        layer.fontSize = baseSize
    }

    /// Secondary/tertiary applier: single-line with auto-shrink down to 0.7×.
    /// Secondary lines (rate readouts, EC subtitles) are rarely long enough
    /// to need wrap; shrink preserves the compact footprint.
    private func applyShrink(_ layer: CATextLayer, text: String, font: UIFont, baseSize: CGFloat, width: CGFloat) {
        layer.font = font
        layer.string = text
        guard width > 0 else { layer.fontSize = baseSize; return }
        let natural = (text as NSString).size(withAttributes: [.font: font]).width
        if natural > width {
            let scale = max(Self.minScale, width / natural)
            layer.fontSize = baseSize * scale
        } else {
            layer.fontSize = baseSize
        }
    }

    // MARK: - Branch entry points

    func setOne(primary: String, color: CGColor) {
        text1 = primary
        text2 = nil
        text3 = nil
        text4 = nil
        primaryMultiline = false
        secondaryWraps = false
        tertiaryBaseSize = 10
        currentColorCG = color
        setNeedsLayout()
    }

    func setTwo(primary: String, secondary: String,
                primaryMultiline: Bool = false,
                secondaryFontSize: CGFloat = 11,
                color: CGColor) {
        text1 = primary
        text2 = secondary
        text3 = nil
        text4 = nil
        self.primaryMultiline = primaryMultiline
        secondaryWraps = false
        self.secondaryBaseSize = secondaryFontSize
        tertiaryBaseSize = 10
        currentColorCG = color
        setNeedsLayout()
    }

    func setThree(primary: String, secondary: String, tertiary: String,
                  secondaryFontSize: CGFloat = 10,
                  secondaryWraps: Bool = false,
                  tertiaryFontSize: CGFloat = 10,
                  color: CGColor) {
        text1 = primary
        text2 = secondary
        text3 = tertiary
        text4 = nil
        primaryMultiline = false
        self.secondaryWraps = secondaryWraps
        secondaryBaseSize = secondaryFontSize  // default 10pt (rate mode)
        tertiaryBaseSize = tertiaryFontSize
        currentColorCG = color
        setNeedsLayout()
    }

    /// 4-line variant — Reality button post-study: header + machines gained
    /// + cap/stats + glyph level. Secondary sits at `secondaryFontSize`
    /// (12pt bold for Reality), tertiary bumped to 11pt regular, quaternary
    /// 11pt regular. Mirrors [RealityButton.vue:149-156].
    func setFour(primary: String,
                 secondary: String,
                 tertiary: String,
                 quaternary: String,
                 secondaryFontSize: CGFloat = 12,
                 secondaryWraps: Bool = false,
                 tertiaryFontSize: CGFloat = 11,
                 quaternaryFontSize: CGFloat = 12,
                 color: CGColor) {
        text1 = primary
        text2 = secondary
        text3 = tertiary
        text4 = quaternary
        primaryMultiline = false
        self.secondaryWraps = secondaryWraps
        secondaryBaseSize = secondaryFontSize
        tertiaryBaseSize = tertiaryFontSize
        quaternaryBaseSize = quaternaryFontSize
        currentColorCG = color
        setNeedsLayout()
    }
}
