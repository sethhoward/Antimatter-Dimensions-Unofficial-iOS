//
//  CompactAntimatterDisplayRenderer.swift
//  AntiMatter
//
//  CALayer-based renderer for the iPhone compact header's antimatter block
//  (antimatter amount, AM/sec, tickspeed readout). Replaces the SwiftUI
//  `Text`-based `CompactAntimatterDisplay` to bypass `ResolvedTextFilter`
//  on 4 high-frequency text fields updating at 30Hz.
//
//  Architecture mirrors `DimensionRowsRenderer`: one `UIView` with
//  `CATextLayer` sublayers, cached fonts/colors, implicit animations
//  disabled for string/color updates.
//

import SwiftUI
import UIKit
import CoreText

// MARK: - SwiftUI bridge

struct CompactAntimatterDisplayRenderer: UIViewRepresentable {
    let engine: GameEngine
    /// When non-nil, renders a single inline currency line (value + short
    /// label, e.g. "10 EP") instead of the full antimatter block. Used by
    /// the tap-to-cycle header. `shortName` matches antimatter's
    /// "X antimatter" suffix style so cycling never reflows the layout.
    var alternate: (value: String, shortName: String, color: Color)? = nil

    func makeUIView(context: Context) -> CompactAntimatterDisplayView {
        CompactAntimatterDisplayView()
    }

    func updateUIView(_ uiView: CompactAntimatterDisplayView, context: Context) {
        if let alt = alternate {
            uiView.updateAlternate(value: alt.value, shortName: alt.shortName, color: UIColor(alt.color))
        } else {
            // Web HeaderCenterContainer.vue:38 strips AM/sec + tickspeed info
            // once `hasRealityButton = realityUnlocked || realityStudyBought` to
            // make room for the Reality button. The info relocates under the
            // Tickspeed button in the AD tab (TickspeedRow.vue:110-115).
            uiView.update(
                antimatter: engine.antimatter,
                antimatterPerSec: engine.antimatterPerSec,
                tickspeedMultiplier: engine.tickspeedMultiplier,
                tickspeedPerSecond: engine.tickspeedPerSecond,
                tickspeedUnlocked: engine.tickspeedUnlocked,
                hideRateAndTickspeed: engine.gameState.infinity.showRealityButton
            )
        }
    }
}

// MARK: - Core Animation view

final class CompactAntimatterDisplayView: UIView {

    private let amLayer = CATextLayer()
    private let amPerSecLayer = CATextLayer()
    private let tickMultLayer = CATextLayer()
    private let tickPerSecLayer = CATextLayer()

    // Cached inputs — skip no-op writes.
    private var cachedAM: String?
    private var cachedPerSec: String?
    private var cachedTickMult: String?
    private var cachedTickPS: String?
    private var cachedTickUnlocked: Bool = true
    private var cachedHideRateAndTickspeed: Bool = false

    // Fonts — toll-free bridged from UIFont for mono-digit variants.
    private static let amBoldFontUI = UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .bold)
    private static let suffixFontUI = UIFont.systemFont(ofSize: 12)
    private static let amPerSecFontUI = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let tickFontUI = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    // Colors cached as CGColor (UIColor from SwiftUI Color).
    private static let amColorCG = UIColor(GameColor.antimatter).cgColor
    private static let amSuffixUI = UIColor.white.withAlphaComponent(0.7)
    private static let amSuffixCG = amSuffixUI.cgColor
    private static let amPerSecCG = UIColor.white.withAlphaComponent(0.5).cgColor
    private static let tickCG = UIColor.white.withAlphaComponent(0.4).cgColor

    private var intrinsicHeight: CGFloat = 62

    /// True while rendering an alternate currency (IP/EP/TT/RM/Replicanti).
    /// Renders inline as "{value} {short_label}" on the amLayer only; all
    /// other lines stay hidden so the slot height matches antimatter.
    private var isAlternate: Bool = false
    private var cachedAltValue: String?
    private var cachedAltShort: String?
    private var cachedAltColorCG: CGColor?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        configureLayers()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configureLayers() {
        let scale = window?.screen.scale ?? traitCollection.displayScale
        for layer in [amLayer, amPerSecLayer, tickMultLayer, tickPerSecLayer] {
            // Disable implicit animations on every property we mutate at 30Hz.
            layer.actions = [
                "string": NSNull(),
                "contents": NSNull(),
                "foregroundColor": NSNull(),
                "hidden": NSNull(),
                "opacity": NSNull()
            ]
            layer.contentsScale = scale
            layer.alignmentMode = .center
            layer.truncationMode = .end
            self.layer.addSublayer(layer)
        }
        amPerSecLayer.font = Self.amPerSecFontUI
        amPerSecLayer.fontSize = 11
        amPerSecLayer.foregroundColor = Self.amPerSecCG
        tickMultLayer.font = Self.tickFontUI
        tickMultLayer.fontSize = 10
        tickMultLayer.foregroundColor = Self.tickCG
        tickPerSecLayer.font = Self.tickFontUI
        tickPerSecLayer.fontSize = 10
        tickPerSecLayer.foregroundColor = Self.tickCG
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        if isAlternate {
            // Single inline "value short_label" line, vertically centered in
            // whatever slot the parent provides (matches antimatter's
            // 24pt amount line so cycling never reflows surrounding rows).
            let valueH: CGFloat = 24
            let y = max(0, (bounds.height - valueH) / 2)
            amLayer.frame = CGRect(x: 0, y: y, width: w, height: valueH)
        } else {
            amLayer.frame       = CGRect(x: 0, y: 0,  width: w, height: 24)
            amPerSecLayer.frame = CGRect(x: 0, y: 24, width: w, height: 14)
            tickMultLayer.frame = CGRect(x: 0, y: 38, width: w, height: 12)
            tickPerSecLayer.frame = CGRect(x: 0, y: 50, width: w, height: 12)
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: intrinsicHeight)
    }

    // MARK: - Updates

    func update(antimatter: String,
                antimatterPerSec: String,
                tickspeedMultiplier: String,
                tickspeedPerSecond: String,
                tickspeedUnlocked: Bool,
                hideRateAndTickspeed: Bool = false) {

        // Flip back from alternate mode: unhide tickspeed lines, re-layout.
        if isAlternate {
            isAlternate = false
            cachedAltValue = nil
            cachedAltShort = nil
            cachedAltColorCG = nil
            amPerSecLayer.isHidden = hideRateAndTickspeed
            tickMultLayer.isHidden = hideRateAndTickspeed || !cachedTickUnlocked
            tickPerSecLayer.isHidden = hideRateAndTickspeed || !cachedTickUnlocked
            // Force string re-write so cached paths don't short-circuit.
            cachedAM = nil
            cachedPerSec = nil
            setNeedsLayout()
        }

        if hideRateAndTickspeed != cachedHideRateAndTickspeed {
            cachedHideRateAndTickspeed = hideRateAndTickspeed
            amPerSecLayer.isHidden = hideRateAndTickspeed
            tickMultLayer.isHidden = hideRateAndTickspeed || !cachedTickUnlocked
            tickPerSecLayer.isHidden = hideRateAndTickspeed || !cachedTickUnlocked
            // Web strips the three info lines to give the Reality button room;
            // shrink the intrinsic height so the header reflows.
            intrinsicHeight = hideRateAndTickspeed ? 24 : 62
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }

        if antimatter != cachedAM {
            cachedAM = antimatter
            let attr = NSMutableAttributedString(
                string: antimatter,
                attributes: [
                    .font: Self.amBoldFontUI,
                    .foregroundColor: UIColor(cgColor: Self.amColorCG)
                ]
            )
            attr.append(NSAttributedString(
                string: " antimatter",
                attributes: [
                    .font: Self.suffixFontUI,
                    .foregroundColor: Self.amSuffixUI
                ]
            ))
            amLayer.string = attr
        }

        if antimatterPerSec != cachedPerSec {
            cachedPerSec = antimatterPerSec
            amPerSecLayer.string = "\(antimatterPerSec) AM/s"
        }

        if tickspeedMultiplier != cachedTickMult {
            cachedTickMult = tickspeedMultiplier
            tickMultLayer.string = "ADs produce \(tickspeedMultiplier) faster"
        }

        if tickspeedPerSecond != cachedTickPS {
            cachedTickPS = tickspeedPerSecond
            tickPerSecLayer.string = "Total Tickspeed: \(tickspeedPerSecond)/s"
        }

        if tickspeedUnlocked != cachedTickUnlocked {
            cachedTickUnlocked = tickspeedUnlocked
            tickMultLayer.isHidden = hideRateAndTickspeed || !tickspeedUnlocked
            tickPerSecLayer.isHidden = hideRateAndTickspeed || !tickspeedUnlocked
        }
    }

    /// Alternate mode: render a single inline line `{value} {short_label}`
    /// on `amLayer` (matching antimatter's "1.38 K antimatter" style — bold
    /// colored value + grey suffix). All other layers stay hidden so the
    /// slot height matches the antimatter mode and cycling never reflows
    /// surrounding rows.
    func updateAlternate(value: String, shortName: String, color: UIColor) {
        if !isAlternate {
            isAlternate = true
            // Hide every other line — alternates are single-line by design.
            amPerSecLayer.isHidden = true
            tickMultLayer.isHidden = true
            tickPerSecLayer.isHidden = true
            setNeedsLayout()
        }

        let colorChanged = (cachedAltColorCG.map { $0 != color.cgColor } ?? true)

        if value != cachedAltValue || shortName != cachedAltShort || colorChanged {
            cachedAltValue = value
            cachedAltShort = shortName
            cachedAltColorCG = color.cgColor
            let attr = NSMutableAttributedString(
                string: value,
                attributes: [
                    .font: Self.amBoldFontUI,
                    .foregroundColor: color
                ]
            )
            attr.append(NSAttributedString(
                string: " \(shortName)",
                attributes: [
                    .font: Self.suffixFontUI,
                    .foregroundColor: Self.amSuffixUI
                ]
            ))
            amLayer.string = attr
            cachedAM = nil // force re-write on mode flip back
        }
    }
}
