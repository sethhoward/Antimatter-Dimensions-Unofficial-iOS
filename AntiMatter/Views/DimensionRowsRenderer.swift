//
//  DimensionRowsRenderer.swift
//  AntiMatter
//
//  CALayer-based renderer for the 8 antimatter dimension rows on iPhone.
//  Replaces SwiftUI DimensionRow views to eliminate per-frame text resolution
//  and layout measurement (~20% main thread CPU). iPad keeps SwiftUI rows.
//
//  Architecture: single UIView with 8 row sublayers. Each row has CATextLayers
//  for text and CALayers for progress fills. Updates are direct property sets
//  (no sizeThatFits, no view diffing, no attribute graph).
//

import SwiftUI
import UIKit
import CoreText

// MARK: - SwiftUI bridge

struct DimensionRowsRenderer: UIViewRepresentable {
    let engine: GameEngine

    func makeUIView(context: Context) -> DimensionRowsView {
        let view = DimensionRowsView()
        view.onBuy = { [weak engine] tier, howMany in
            guard let engine else { return }
            if howMany <= 1 {
                engine.buyDimension(tier)
            } else {
                engine.buyAsManyAsYouCanBuy(tier)
            }
        }
        return view
    }

    func updateUIView(_ uiView: DimensionRowsView, context: Context) {
        let dims = engine.gameState.dimensions
        let buyUntil10 = engine.gameState.buyUntil10
        let continuumActive = engine.continuumUnlocked && !engine.continuumDisabled
        uiView.update(dimensions: dims, buyUntil10: buyUntil10, continuumActive: continuumActive)
    }
}

// MARK: - Core Animation view

final class DimensionRowsView: UIView {

    var onBuy: ((Int, Int) -> Void)?

    private var rows: [RowLayers] = []
    private let rowHeight: CGFloat = 44
    private let buttonWidth: CGFloat = 140
    private let hPad: CGFloat = 6
    private let vPad: CGFloat = 4
    private var isSetUp = false

    /// Cached state from the last `update()` call — replayed after deferred `setupRows()`.
    private var cachedDimensions: [DimensionState]?
    private var cachedBuyUntil10: Bool = true
    private var cachedContinuumActive: Bool = false
    /// Number of visible rows (for dynamic intrinsicContentSize).
    private var visibleRowCount: Int = 0

    // Colors (cached as CGColor)
    private static let goodCG = UIColor(named: "Good")!.cgColor
    private static let goodDarkCG = UIColor(named: "GoodDark")!.cgColor
    private static let disabledCG = UIColor(named: "DisabledButton")!.cgColor
    private static let disabledBorderCG = UIColor(named: "DisabledBorder")!.cgColor
    private static let sidebarBgCG = UIColor(named: "SidebarBackground")!.cgColor
    private static let antimatterTintCG = UIColor(named: "AntimatterRed")!.withAlphaComponent(0.3).cgColor
    private static let blackCG = UIColor.black.cgColor
    private static let whiteCG = UIColor.white.cgColor
    private static let secondaryCG = UIColor.white.withAlphaComponent(0.6).cgColor

    // Fonts (cached as CTFont)
    private static let nameFont = CTFontCreateUIFontForLanguage(.system, 14, nil)!

    /// Shared number formatter for "Continuum: X,XXX.XX" readouts.
    private static let continuumFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
    private static let nameFontMedium: CTFont = {
        let desc = CTFontCopyFontDescriptor(nameFont)
        let traits = [kCTFontWeightTrait: 0.23] as CFDictionary // medium weight
        let medDesc = CTFontDescriptorCreateCopyWithAttributes(desc, traits)
        return CTFontCreateWithFontDescriptor(medDesc, 14, nil)
    }()
    private static let multiplierFont = CTFontCreateUIFontForLanguage(.system, 11, nil)!
    private static let amountFont: CTFont = {
        CTFontCreateWithName("Menlo" as CFString, 14, nil)
    }()
    private static let rateFont: CTFont = {
        CTFontCreateWithName("Menlo" as CFString, 10, nil)
    }()
    private static let buyLabelFont: CTFont = {
        let desc = CTFontCopyFontDescriptor(CTFontCreateUIFontForLanguage(.system, 11, nil)!)
        let traits = [kCTFontWeightTrait: 0.4] as CFDictionary // semibold
        let sbDesc = CTFontDescriptorCreateCopyWithAttributes(desc, traits)
        return CTFontCreateWithFontDescriptor(sbDesc, 11, nil)
    }()
    private static let costFont: CTFont = {
        CTFontCreateWithName("Menlo" as CFString, 10, nil)
    }()

    private var scale: CGFloat { window?.screen.scale ?? UITraitCollection.current.displayScale }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup layers

    private func setupRows() {
        guard !isSetUp else { return }
        isSetUp = true

        for i in 0..<8 {
            let row = RowLayers()

            // Root layer for this row
            row.root.frame = CGRect(x: 0, y: CGFloat(i) * rowHeight, width: bounds.width, height: rowHeight)

            // Alternating background tint (even tiers = 2,4,6,8 → indices 1,3,5,7)
            row.bg.frame = CGRect(origin: .zero, size: CGSize(width: bounds.width, height: rowHeight))
            row.bg.backgroundColor = (i + 1) % 2 == 0 ? Self.antimatterTintCG : nil
            row.root.addSublayer(row.bg)

            let bx = bounds.width - buttonWidth - hPad
            let textAreaWidth = bx - hPad - 12 // space for name+amount columns
            let nameColWidth = textAreaWidth * 0.41
            let amountX = hPad + nameColWidth + 4

            // Name label
            configureTL(row.nameLayer, font: Self.nameFontMedium, color: Self.whiteCG,
                        frame: CGRect(x: hPad, y: vPad, width: nameColWidth, height: 18))
            row.root.addSublayer(row.nameLayer)

            // Multiplier label — shares the bottom line with the rate; spans the
            // full text width and the rate is positioned right after it (see
            // layoutMultiplierAndRate) so a long multiplier doesn't truncate
            // inside the narrow name column. Initial width is the full span; the
            // real split is set on the first update once the string is known.
            configureTL(row.multiplierLayer, font: Self.multiplierFont, color: Self.secondaryCG,
                        frame: CGRect(x: hPad, y: vPad + 20, width: bx - hPad, height: 16))
            row.root.addSublayer(row.multiplierLayer)

            // Amount
            configureTL(row.amountLayer, font: Self.amountFont, color: Self.whiteCG,
                        frame: CGRect(x: amountX, y: vPad, width: bx - amountX - 4, height: 18))
            row.root.addSublayer(row.amountLayer)

            // Rate of change — placeholder frame; layoutMultiplierAndRate sets
            // its real x/width after the multiplier on the first update.
            configureTL(row.rateLayer, font: Self.rateFont, color: Self.secondaryCG,
                        frame: CGRect(x: amountX, y: vPad + 20, width: bx - amountX - 4, height: 16))
            row.root.addSublayer(row.rateLayer)

            // Buy button container
            let btnH: CGFloat = 36
            let btnY = (rowHeight - btnH) / 2
            row.buttonContainer.frame = CGRect(x: bx, y: btnY, width: buttonWidth, height: btnH)
            row.buttonContainer.cornerRadius = 6
            row.buttonContainer.borderWidth = 1
            row.buttonContainer.masksToBounds = true
            row.buttonContainer.backgroundColor = Self.blackCG
            row.buttonContainer.borderColor = Self.goodCG

            // Progress fills inside button
            row.progressBg.frame = CGRect(x: 0, y: 0, width: 0, height: btnH)
            row.progressBg.backgroundColor = Self.goodDarkCG
            row.buttonContainer.addSublayer(row.progressBg)

            row.progressFg.frame = CGRect(x: 0, y: 0, width: 0, height: btnH)
            row.progressFg.backgroundColor = Self.goodCG
            row.buttonContainer.addSublayer(row.progressFg)

            // Buy label (centered top)
            configureTL(row.buyLabel, font: Self.buyLabelFont, color: Self.whiteCG,
                        frame: CGRect(x: 4, y: 4, width: buttonWidth - 8, height: 16))
            row.buyLabel.alignmentMode = .center
            row.buttonContainer.addSublayer(row.buyLabel)

            // Cost label (centered bottom)
            configureTL(row.costLabel, font: Self.costFont, color: Self.whiteCG,
                        frame: CGRect(x: 4, y: 20, width: buttonWidth - 8, height: 14))
            row.costLabel.alignmentMode = .center
            row.buttonContainer.addSublayer(row.costLabel)

            row.root.addSublayer(row.buttonContainer)

            // Cache button frame in parent coordinates for hit testing
            row.buyButtonFrame = CGRect(x: bx, y: CGFloat(i) * rowHeight + btnY, width: buttonWidth, height: btnH)

            // Hidden by default — update() will unhide visible rows.
            row.root.isHidden = true

            layer.addSublayer(row.root)
            rows.append(row)
        }
    }

    private func configureTL(_ tl: CATextLayer, font: CTFont, color: CGColor, frame: CGRect) {
        tl.frame = frame
        tl.font = font
        tl.fontSize = CTFontGetSize(font)
        tl.foregroundColor = color
        tl.contentsScale = scale
        tl.truncationMode = .end
        tl.isWrapped = false
        tl.actions = ["string": NSNull(), "foregroundColor": NSNull(),
                       "backgroundColor": NSNull(), "opacity": NSNull(),
                       "bounds": NSNull(), "position": NSNull(), "hidden": NSNull()]
    }

    /// Typographic width of a string in a given CTFont. Used to position the
    /// rate layer right after the multiplier on the shared bottom line.
    private static func textWidth(_ s: String, font: CTFont) -> CGFloat {
        guard !s.isEmpty else { return 0 }
        let attr = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attr)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Lay the multiplier + rate on a shared bottom line: the multiplier is
    /// left-aligned at the row start and takes the width it needs (up to the
    /// available bottom width minus a reserve for the rate), and the rate sits
    /// immediately after it. This lets a long multiplier use the full row width
    /// instead of truncating inside the narrow name column. Only called when the
    /// multiplier string changes (and on relayout), so per-tick rate string
    /// updates don't pay for measurement.
    private func layoutMultiplierAndRate(_ row: RowLayers) {
        let bx = bounds.width - buttonWidth - hPad
        let y = vPad + 20
        let gap: CGFloat = 6
        let rateReserve: CGFloat = 74 // worst-case room for "(+9999.99%/s)"
        let bottomWidth = bx - hPad
        let measured = Self.textWidth((row.multiplierLayer.string as? String) ?? "", font: Self.multiplierFont)
        let maxMult = max(0, bottomWidth - rateReserve - gap)
        let multW = min(measured, maxMult)
        row.multiplierLayer.frame = CGRect(x: hPad, y: y, width: multW, height: 16)
        let rateX = hPad + multW + gap
        row.rateLayer.frame = CGRect(x: rateX, y: y, width: max(0, bx - rateX - 4), height: 16)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if !isSetUp && bounds.width > 0 {
            setupRows()
            // Replay cached state so rows are correctly configured on first layout.
            if let dims = cachedDimensions {
                update(dimensions: dims, buyUntil10: cachedBuyUntil10, continuumActive: cachedContinuumActive)
            }
        } else if isSetUp {
            // Relayout on rotation/size change
            let bx = bounds.width - buttonWidth - hPad
            let textAreaWidth = bx - hPad - 12
            let nameColWidth = textAreaWidth * 0.42
            let amountX = hPad + nameColWidth + 4

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (i, row) in rows.enumerated() {
                row.root.frame = CGRect(x: 0, y: CGFloat(i) * rowHeight, width: bounds.width, height: rowHeight)
                row.bg.frame = CGRect(origin: .zero, size: CGSize(width: bounds.width, height: rowHeight))
                row.nameLayer.frame.size.width = nameColWidth
                row.amountLayer.frame = CGRect(x: amountX, y: vPad, width: bx - amountX - 4, height: 18)
                // Multiplier + rate share the bottom line — reposition for the new width.
                layoutMultiplierAndRate(row)
                let btnY = (rowHeight - 36) / 2
                row.buttonContainer.frame = CGRect(x: bx, y: btnY, width: buttonWidth, height: 36)
                row.buyButtonFrame = CGRect(x: bx, y: CGFloat(i) * rowHeight + btnY, width: buttonWidth, height: 36)
            }
            CATransaction.commit()
        }
    }

    override var intrinsicContentSize: CGSize {
        let count = max(visibleRowCount, 0)
        return CGSize(width: UIView.noIntrinsicMetric, height: rowHeight * CGFloat(count))
    }

    // MARK: - Update from state

    func update(dimensions: [DimensionState], buyUntil10: Bool, continuumActive: Bool = false) {
        // Always cache for deferred replay after setupRows().
        cachedDimensions = dimensions
        cachedBuyUntil10 = buyUntil10
        cachedContinuumActive = continuumActive

        if !isSetUp && bounds.width > 0 {
            setupRows()
        }
        guard isSetUp else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for (i, row) in rows.enumerated() {
            guard i < dimensions.count else {
                row.root.isHidden = true
                continue
            }
            let dim = dimensions[i]

            guard dim.isVisible else {
                row.root.isHidden = true
                continue
            }
            row.root.isHidden = false

            let isLocked = !dim.isAvailableForPurchase

            // Text updates (direct property sets — no layout measurement)
            row.amountLayer.string = dim.amount
            row.rateLayer.string = dim.rateOfChange.map { "(+\($0)%/s)" } ?? ""

            // Multiplier (changes infrequently — skip if same). When it changes,
            // re-measure and reposition the rate after it on the shared bottom line.
            if row.lastMultiplier != dim.multiplier {
                row.multiplierLayer.string = dim.multiplier
                row.lastMultiplier = dim.multiplier
                layoutMultiplierAndRate(row)
            }

            // Name (set once, never changes)
            if row.nameLayer.string as? String == nil {
                row.nameLayer.string = dim.shortDisplayName
            }

            // Buy button text. When Lai'tela's Continuum is active, the
            // button becomes a non-interactive readout showing the continuum
            // "ownership" value — no buy, no cost line. Matches web
            // `ModernAntimatterDimensionRow.vue`.
            if continuumActive && !isLocked {
                row.buyLabel.string = "Continuum:"
                row.costLabel.string = Self.continuumFormatter.string(from: NSNumber(value: dim.continuumValue)) ?? "0"
            } else if isLocked {
                row.buyLabel.string = "Locked"
                row.costLabel.string = "Cost: \(dim.singleCost) \(dim.costSuffix)"
            } else {
                row.buyLabel.string = "Buy \(dim.howManyCanBuy)"
                row.costLabel.string = "Cost: \(buyUntil10 ? dim.until10Cost : dim.singleCost) \(dim.costSuffix)"
            }

            // Progress fills — suppressed in continuum mode (no "progress to
            // next 10" concept applies).
            let canAfford = dim.isAffordable && !isLocked && !continuumActive
            if continuumActive && !isLocked {
                row.progressBg.isHidden = true
                row.progressFg.isHidden = true
                row.buttonContainer.backgroundColor = Self.blackCG
                row.buttonContainer.borderColor = Self.goodCG
            } else if canAfford {
                let canBuyFrac = min(CGFloat(dim.boughtBefore10 + dim.howManyCanBuy), 10) / 10
                let boughtFrac = CGFloat(dim.boughtBefore10) / 10
                row.progressBg.isHidden = false
                row.progressFg.isHidden = boughtFrac <= 0
                row.progressBg.frame.size.width = buttonWidth * canBuyFrac
                row.progressFg.frame.size.width = buttonWidth * boughtFrac
                row.buttonContainer.backgroundColor = Self.blackCG
                row.buttonContainer.borderColor = Self.goodCG
            } else if isLocked {
                row.progressBg.isHidden = true
                row.progressFg.isHidden = true
                row.buttonContainer.backgroundColor = Self.sidebarBgCG
                row.buttonContainer.borderColor = Self.disabledBorderCG
            } else {
                // Not affordable
                row.progressBg.isHidden = true
                row.progressFg.isHidden = true
                row.buttonContainer.backgroundColor = Self.disabledCG
                row.buttonContainer.borderColor = Self.disabledBorderCG
            }

            // Row opacity for locked dimensions
            row.root.opacity = isLocked ? 0.5 : 1.0

            // Store state for tap handling — continuum suppresses buys.
            row.tier = dim.tier
            row.howManyCanBuy = dim.howManyCanBuy
            row.isTappable = dim.isAffordable && !isLocked && !continuumActive
        }

        // Track visible count for dynamic intrinsicContentSize.
        let newVisibleCount = dimensions.prefix(rows.count).filter(\.isVisible).count
        if newVisibleCount != visibleRowCount {
            visibleRowCount = newVisibleCount
            invalidateIntrinsicContentSize()
        }

        CATransaction.commit()
    }

    // MARK: - Tap handling

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        for row in rows where !row.root.isHidden && row.isTappable {
            if row.buyButtonFrame.contains(point) {
                Haptics.tap()
                onBuy?(row.tier, row.howManyCanBuy)
                return
            }
        }
    }
}

// MARK: - Per-row layer storage

private final class RowLayers {
    let root = CALayer()
    let bg = CALayer()
    let nameLayer = CATextLayer()
    let multiplierLayer = CATextLayer()
    let amountLayer = CATextLayer()
    let rateLayer = CATextLayer()
    let buttonContainer = CALayer()
    let progressBg = CALayer()
    let progressFg = CALayer()
    let buyLabel = CATextLayer()
    let costLabel = CATextLayer()

    var buyButtonFrame: CGRect = .zero
    var tier: Int = 0
    var howManyCanBuy: Int = 0
    var isTappable: Bool = false
    var lastMultiplier: String?

    init() {
        // Disable implicit animations on container layers
        for l in [root, bg, buttonContainer, progressBg, progressFg] {
            l.actions = ["opacity": NSNull(), "hidden": NSNull(),
                         "bounds": NSNull(), "position": NSNull(),
                         "backgroundColor": NSNull(), "borderColor": NSNull()]
        }
    }
}
