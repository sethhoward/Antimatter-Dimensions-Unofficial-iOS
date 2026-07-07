//
//  DimensionsTabRenderers.swift
//  AntiMatter
//
//  CATextLayer-backed renderers for 30Hz text on the Antimatter Dimensions
//  tab (iPhone). Bypasses SwiftUI `ResolvedTextFilter` on:
//    - `DimensionInfoText` (Buy 10 mult / Sacrifice multiplier line)
//    - `DimBoostRow` / `GalaxyRow` (title + requirement text)
//    - Sacrifice button label
//

import SwiftUI
import UIKit

// MARK: - Generic single-line CATextLayer leaf

/// Lightweight CATextLayer-backed text view for single lines of 30Hz text.
/// Intrinsic content size derives from measured text; SwiftUI treats it
/// like any other leaf with a natural size.
struct CATextLeaf: UIViewRepresentable {
    let text: String
    let font: UIFont
    let color: UIColor
    var alignment: CATextLayerAlignmentMode = .center
    var allowsWrap: Bool = false
    /// When true, the view reports `noIntrinsicMetric` for width so SwiftUI
    /// frame modifiers (`.frame(maxWidth: .infinity)`) actually expand it.
    /// Text is centered within the expanded bounds by CATextLayer's alignment.
    /// Use `false` + `.fixedSize()` for intrinsic-width sizing.
    var stretchHorizontally: Bool = false

    func makeUIView(context: Context) -> CATextLeafView {
        let v = CATextLeafView()
        v.stretchHorizontally = stretchHorizontally
        return v
    }

    func updateUIView(_ uiView: CATextLeafView, context: Context) {
        uiView.stretchHorizontally = stretchHorizontally
        uiView.update(text: text, font: font, color: color,
                      alignment: alignment, allowsWrap: allowsWrap)
    }

    /// If the parent proposes a specific width (e.g. `.frame(maxWidth: .infinity)`),
    /// use it — the internal CATextLayer aligns text within its bounds.
    /// Otherwise fall back to intrinsic width (for `.fixedSize()` call sites).
    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView: CATextLeafView,
                      context: Context) -> CGSize? {
        let intrinsic = uiView.intrinsicContentSize
        let w = proposal.width ?? intrinsic.width
        let h = proposal.height ?? intrinsic.height
        return CGSize(width: w, height: h)
    }
}

final class CATextLeafView: UIView {
    private let textLayer = CATextLayer()

    var stretchHorizontally: Bool = false {
        didSet {
            if stretchHorizontally != oldValue {
                invalidateIntrinsicContentSize()
            }
        }
    }

    private var cachedText: String?
    private var cachedFontID: ObjectIdentifier?
    private var cachedColorCG: CGColor?
    private var cachedAlignment: CATextLayerAlignmentMode = .center
    private var cachedAllowsWrap: Bool = false
    private var measuredSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        textLayer.actions = [
            "string": NSNull(), "contents": NSNull(),
            "foregroundColor": NSNull(), "bounds": NSNull(),
            "position": NSNull(), "fontSize": NSNull()
        ]
        textLayer.contentsScale = traitCollection.displayScale
        textLayer.truncationMode = .end
        // Defaults must match `cachedAlignment` + `cachedAllowsWrap` —
        // otherwise `update()`'s change-detection skips the initial sync
        // and CATextLayer keeps its `.natural` (leading) default.
        textLayer.alignmentMode = .center
        textLayer.isWrapped = false
        self.layer.addSublayer(textLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        textLayer.frame = bounds
    }

    override var intrinsicContentSize: CGSize {
        if stretchHorizontally {
            return CGSize(width: UIView.noIntrinsicMetric, height: measuredSize.height)
        }
        return measuredSize
    }

    func update(text: String, font: UIFont, color: UIColor,
                alignment: CATextLayerAlignmentMode, allowsWrap: Bool) {
        let fontID = ObjectIdentifier(font)
        let textChanged = text != cachedText
        let fontChanged = fontID != cachedFontID
        let colorChanged = (cachedColorCG.map { $0 != color.cgColor } ?? true)
        let alignmentChanged = alignment != cachedAlignment
        let wrapChanged = allowsWrap != cachedAllowsWrap

        guard textChanged || fontChanged || colorChanged
            || alignmentChanged || wrapChanged else { return }

        if fontChanged {
            textLayer.font = font
            textLayer.fontSize = font.pointSize
            cachedFontID = fontID
        }
        if colorChanged {
            textLayer.foregroundColor = color.cgColor
            cachedColorCG = color.cgColor
        }
        if alignmentChanged {
            textLayer.alignmentMode = alignment
            cachedAlignment = alignment
        }
        if wrapChanged {
            textLayer.isWrapped = allowsWrap
            cachedAllowsWrap = allowsWrap
        }
        if textChanged {
            textLayer.string = text
            cachedText = text
        }

        // Re-measure when text or font changed (both affect size).
        if textChanged || fontChanged {
            let measured = (text as NSString).size(withAttributes: [.font: font])
            // ~1.2x line height is safe for most fonts at small sizes.
            let newSize = CGSize(width: ceil(measured.width),
                                 height: ceil(measured.height * 1.2))
            if newSize != measuredSize {
                measuredSize = newSize
                invalidateIntrinsicContentSize()
            }
        }
    }
}

// MARK: - DimBoost / Galaxy row header (title + requirement)

/// Two- or three-line header for DimBoost and Galaxy rows: bold title +
/// optional subtitle (e.g. galaxy count breakdown "100 + 40 = 140") +
/// secondary-colored requirement text. All lines updated via CATextLayer.
struct PrestigeActionHeaderRenderer: UIViewRepresentable {
    let title: String
    let subtitle: String?
    let requirement: String

    init(title: String, subtitle: String? = nil, requirement: String) {
        self.title = title
        self.subtitle = subtitle
        self.requirement = requirement
    }

    func makeUIView(context: Context) -> PrestigeActionHeaderView {
        PrestigeActionHeaderView()
    }

    func updateUIView(_ uiView: PrestigeActionHeaderView, context: Context) {
        uiView.update(title: title, subtitle: subtitle, requirement: requirement)
    }
}

final class PrestigeActionHeaderView: UIView {
    private let titleLayer = CATextLayer()
    private let subtitleLayer = CATextLayer()
    private let reqLayer = CATextLayer()

    private var cachedTitle: String?
    private var cachedSubtitle: String?
    private var cachedReq: String?
    private var hasSubtitle: Bool = false
    private static let subtitleBaseSize: CGFloat = 13
    private static let subtitleMinScale: CGFloat = 0.4   // 13pt → 5.2pt floor
    /// Safety factor to leave a small margin so kerning/hinting at smaller
    /// font sizes doesn't push the last glyph past the right edge.
    private static let subtitleFitFactor: CGFloat = 0.96
    // 16pt title + 1pt gap + 12pt req = 29pt, matches performLayout total.
    // Initialized to the layout-computed value so SwiftUI's first-pass
    // intrinsic size matches the post-layout value (prevents y-axis jitter
    // between DimBoost and Galaxy rows in HStack(.top)).
    private var measuredHeight: CGFloat = 29

    // iPhone compact sizing — matches the original `.subheadline.monospacedDigit()`
    // for title (~15pt system bold equivalent) and `.caption` (11pt) for req.
    private static let titleFont = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
    private static let subtitleFont = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private static let reqFont = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let titleColorCG = UIColor.white.cgColor
    private static let subtitleColorCG = UIColor.white.withAlphaComponent(0.85).cgColor
    private static let reqColorCG = UIColor.white.withAlphaComponent(0.6).cgColor

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        for layer in [titleLayer, subtitleLayer, reqLayer] {
            layer.actions = [
                "string": NSNull(), "contents": NSNull(),
                "foregroundColor": NSNull(), "bounds": NSNull(),
                "position": NSNull(), "fontSize": NSNull()
            ]
            layer.contentsScale = traitCollection.displayScale
            layer.alignmentMode = .center
            layer.truncationMode = .end
            self.layer.addSublayer(layer)
        }
        titleLayer.font = Self.titleFont
        titleLayer.fontSize = 15
        titleLayer.foregroundColor = Self.titleColorCG
        subtitleLayer.font = Self.subtitleFont
        subtitleLayer.fontSize = 13
        subtitleLayer.foregroundColor = Self.subtitleColorCG
        subtitleLayer.isHidden = true
        reqLayer.font = Self.reqFont
        reqLayer.fontSize = 11
        reqLayer.foregroundColor = Self.reqColorCG
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let titleH: CGFloat = 16
        let subH: CGFloat = 14
        let reqH: CGFloat = 12
        let gap: CGFloat = 1
        // Top-anchor so DimBoost and Galaxy headers align in HStack(.top).
        // Don't center within bounds.height — that shifts the title down if
        // the parent stretches the view beyond its intrinsic height.
        titleLayer.frame = CGRect(x: 0, y: 0, width: w, height: titleH)
        let total: CGFloat
        if hasSubtitle {
            subtitleLayer.frame = CGRect(x: 0, y: titleH + gap, width: w, height: subH)
            // Auto-shrink the subtitle when it overflows — long galaxy
            // breakdowns ("33,938 + 15,931 + 14,802 = 64,671") otherwise
            // truncate with "..." at the default 13pt size.
            applySubtitleAutoShrink(width: w)
            reqLayer.frame = CGRect(x: 0, y: titleH + gap + subH + gap, width: w, height: reqH)
            total = titleH + gap + subH + gap + reqH
        } else {
            reqLayer.frame = CGRect(x: 0, y: titleH + gap, width: w, height: reqH)
            total = titleH + gap + reqH
        }
        if measuredHeight != total {
            measuredHeight = total
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: measuredHeight)
    }

    func update(title: String, subtitle: String?, requirement: String) {
        if title != cachedTitle {
            titleLayer.string = title
            cachedTitle = title
        }
        let nextHasSubtitle = (subtitle?.isEmpty == false)
        if subtitle != cachedSubtitle {
            subtitleLayer.string = subtitle
            cachedSubtitle = subtitle
        }
        if nextHasSubtitle != hasSubtitle {
            hasSubtitle = nextHasSubtitle
            subtitleLayer.isHidden = !nextHasSubtitle
            setNeedsLayout()
        }
        if requirement != cachedReq {
            reqLayer.string = requirement
            cachedReq = requirement
        }
    }

    private func applySubtitleAutoShrink(width: CGFloat) {
        guard width > 0, let text = cachedSubtitle, !text.isEmpty else {
            subtitleLayer.fontSize = Self.subtitleBaseSize
            return
        }
        let target = width * Self.subtitleFitFactor
        let natural = (text as NSString).size(withAttributes: [.font: Self.subtitleFont]).width
        if natural > target {
            let scale = max(Self.subtitleMinScale, target / natural)
            subtitleLayer.fontSize = Self.subtitleBaseSize * scale
        } else {
            subtitleLayer.fontSize = Self.subtitleBaseSize
        }
    }
}
