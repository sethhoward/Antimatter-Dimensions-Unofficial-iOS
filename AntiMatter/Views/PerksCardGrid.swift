//
//  PerksCardGrid.swift
//  AntiMatter
//
//  Shared (iPad + iPhone) Perks renderer: spatial card grid.
//  Replaces the older tiny-node-with-tap-to-detail graph on both
//  platforms. Uniform 250×140 cards with 14pt label + 13pt body
//  (no truncation), family-colored borders, edge-clipped connection
//  lines, and an AP diamond badge anchored mostly inside the card.
//
//  Single Canvas draw — z-order:
//    1. connection lines (edge-to-edge, child family color)
//    2. card opaque fills + borders
//    3. card text
//    4. AP diamond badges
//

import SwiftUI

struct PerksCardGrid: View {
    let engine: GameEngine
    @Binding var selectedPerk: PerkInfo?
    /// Extra zoom-independent bottom inset for the scroll view. iPhone
    /// passes 80 to clear the floating glass tab bar; iPad passes 0.
    var bottomInset: CGFloat = 80

    private var state: PerksState { engine.gameState.perksState }

    // Card geometry. Sized to fit the longest description in the dataset
    // without truncation: PEC1 normalizes to 186 chars, so at 13pt body
    // text on a ~234pt usable text width that's ~6 lines, plus label +
    // padding ≈ 140pt tall card.
    private static let cardWidth: CGFloat = 250
    private static let cardHeight: CGFloat = 140
    private static let gutterX: CGFloat = 16
    private static let gutterY: CGFloat = 24
    private static let cellW: CGFloat = cardWidth + gutterX   // 266
    private static let cellH: CGFloat = cardHeight + gutterY  // 164

    // Original perk position grid steps from `pollPerks` decoder are 150
    // horizontally and 100 vertically. Scale onto our card-cell pitch.
    private static let scaleX: CGFloat = cellW / 150  // 1.77
    private static let scaleY: CGFloat = cellH / 100  // 1.64

    // AP diamond badge: bigger + biased inward so most of it sits inside
    // the card with only a small "sticker" peek into the gutter.
    private static let badgeSize: CGFloat = 26
    private static let badgeInset: CGFloat = 9   // distance from corner

    private static let internalPadH: CGFloat = 8
    private static let internalPadV: CGFloat = 6
    private static let labelFontSize: CGFloat = 14
    private static let descFontSize: CGFloat = 13
    private static let labelToBodyGap: CGFloat = 4

    private static let badgeFill = Color(red: 0.992, green: 0.847, blue: 0.208) // #fdd835

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                Text("You have \(Text("\(state.perkPoints)").foregroundStyle(GameColor.reality)) Perk \(state.perkPoints == 1 ? "Point" : "Points").")
                    .foregroundStyle(.secondary)
                    .font(.subheadline.monospacedDigit())

                Text("Perk choices are permanent and cannot be respecced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Perks marked with a ◆ also give Automator Points.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)

            ZoomableScrollView(
                minZoom: 0.15,
                maxZoom: 2.0,
                bottomInset: bottomInset,
                initialFocus: initialFocus,
                zoomScale: Binding(
                    get: { engine.perksZoom },
                    set: { engine.perksZoom = $0 }
                ),
                contentOffset: Binding(
                    get: { engine.perksOffset },
                    set: { engine.perksOffset = $0 }
                )
            ) {
                cardsCanvas
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout helpers

    private struct CanvasGeometry {
        let bounds: CGRect
        let totalW: CGFloat
        let totalH: CGFloat
    }

    private func computeGeometry(_ perks: [PerkInfo]) -> CanvasGeometry {
        guard !perks.isEmpty else {
            return CanvasGeometry(bounds: .zero, totalW: 100, totalH: 100)
        }
        let xs = perks.map { $0.x * Self.scaleX }
        let ys = perks.map { $0.y * Self.scaleY }
        let margin: CGFloat = Self.cardWidth
        let minX = (xs.min() ?? 0) - margin
        let maxX = (xs.max() ?? 0) + margin
        let minY = (ys.min() ?? 0) - margin
        let maxY = (ys.max() ?? 0) + margin
        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return CanvasGeometry(bounds: bounds, totalW: bounds.width, totalH: bounds.height)
    }

    private func cardRect(for perk: PerkInfo, bounds: CGRect) -> CGRect {
        let cx = perk.x * Self.scaleX - bounds.minX
        let cy = perk.y * Self.scaleY - bounds.minY
        return CGRect(
            x: cx - Self.cardWidth / 2,
            y: cy - Self.cardHeight / 2,
            width: Self.cardWidth,
            height: Self.cardHeight
        )
    }

    /// Default open-zoom landing point: center on the Reality perk (id 0).
    /// Returned in unscaled (pre-zoom) canvas-local coords.
    private var initialFocus: CGPoint? {
        guard let reality = state.perks.first(where: { $0.id == 0 }) else { return nil }
        let geom = computeGeometry(state.perks)
        return CGPoint(
            x: reality.x * Self.scaleX - geom.bounds.minX,
            y: reality.y * Self.scaleY - geom.bounds.minY
        )
    }

    /// Clip a center-to-center segment to the rectangular edges of two equal-
    /// sized cards, returning the (entry, exit) endpoints of the visible
    /// "in the gutter" portion. Returns nil when the cards are too close
    /// (i.e. the line doesn't escape either rect).
    private static func clipLineToCardEdges(
        from: CGPoint,
        to: CGPoint
    ) -> (CGPoint, CGPoint)? {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let absDx = abs(dx)
        let absDy = abs(dy)
        if absDx < 0.001 && absDy < 0.001 { return nil }

        let halfW = cardWidth / 2
        let halfH = cardHeight / 2
        let txEdge = absDx > 0.001 ? halfW / absDx : .greatestFiniteMagnitude
        let tyEdge = absDy > 0.001 ? halfH / absDy : .greatestFiniteMagnitude
        let exitT = min(txEdge, tyEdge)

        // Both endpoints have identical card size, so entry into the
        // destination rect mirrors the exit from source.
        let entryT = 1 - exitT
        if exitT >= entryT { return nil }

        let p1 = CGPoint(x: from.x + exitT * dx, y: from.y + exitT * dy)
        let p2 = CGPoint(x: from.x + entryT * dx, y: from.y + entryT * dy)
        return (p1, p2)
    }

    // MARK: - Canvas

    private var cardsCanvas: some View {
        let perks = state.perks
        guard !perks.isEmpty else {
            return AnyView(Color.clear.frame(width: 100, height: 100))
        }

        let perkMap = Dictionary(uniqueKeysWithValues: perks.map { ($0.id, $0) })
        let geom = computeGeometry(perks)
        let pelleDoomed = engine.pelleDoomed
        let uselessPerks = engine.pelleUselessPerks

        let canvas = Canvas { ctx, _ in
            // 1. Connection lines (edge-to-edge between card borders).
            //    Color = child's family color; thick + bright when both
            //    bought, thinner + dimmer otherwise.
            for perk in perks {
                for connID in perk.connectedTo {
                    guard connID > perk.id, let other = perkMap[connID] else { continue }
                    let bothBought = perk.isBought && other.isBought
                    let (parent, child) = perk.y <= other.y ? (perk, other) : (other, perk)
                    let pCenter = CGPoint(
                        x: cardRect(for: parent, bounds: geom.bounds).midX,
                        y: cardRect(for: parent, bounds: geom.bounds).midY
                    )
                    let cCenter = CGPoint(
                        x: cardRect(for: child, bounds: geom.bounds).midX,
                        y: cardRect(for: child, bounds: geom.bounds).midY
                    )
                    guard let (p1, p2) = Self.clipLineToCardEdges(from: pCenter, to: cCenter) else {
                        continue
                    }

                    let childColor = PerksTab.familyColor(child.family)
                    let lineColor = bothBought ? childColor : childColor.opacity(0.45)
                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)
                    ctx.stroke(
                        path,
                        with: .color(lineColor),
                        style: StrokeStyle(
                            lineWidth: bothBought ? 6 : 3,
                            lineCap: .round
                        )
                    )
                }
            }

            // 2. Card fills + borders. Two-pass fill so the line layer is
            //    fully masked: opaque black base, then optional family
            //    tint or unavailable gray on top.
            for perk in perks {
                let rect = cardRect(for: perk, bounds: geom.bounds)
                let family = PerksTab.familyColor(perk.family)
                let path = Path(roundedRect: rect, cornerRadius: 10)

                // Opaque black base (always) — guarantees lines beneath
                // never bleed through, regardless of state-color opacity.
                ctx.fill(path, with: .color(.black))

                if perk.isBought {
                    ctx.fill(path, with: .color(family.opacity(0.55)))
                } else if !perk.canBeBought {
                    ctx.fill(path, with: .color(GameColor.unavailableBg))
                }

                // Border: full saturation when bought/available, 40% when
                // locked. Drawn after fills so it sits on top.
                let border: Color = (perk.isBought || perk.canBeBought)
                    ? family
                    : family.opacity(0.4)
                ctx.stroke(path, with: .color(border), lineWidth: 2)
            }

            // 3. Card text. Strikethrough on doom-disabled perks is baked
            //    into AttributedString decoration rather than applied via
            //    `Text.strikethrough()` — `GraphicsContext.resolve(_:)`
            //    drops decoration view modifiers, so a `.strikethrough()`
            //    on a Text outside Canvas works fine but inside Canvas
            //    silently no-ops. AttributedString's `strikethroughStyle`
            //    attribute survives resolve.
            for perk in perks {
                let rect = cardRect(for: perk, bounds: geom.bounds)
                let isPelleUseless = pelleDoomed
                    && perk.isBought
                    && uselessPerks.contains(perk.id)
                let textColor: Color = (perk.isBought || perk.canBeBought)
                    ? .white
                    : Color(white: 0.7)

                var labelAttr = AttributedString(perk.label)
                labelAttr.font = .system(size: Self.labelFontSize, weight: .bold)
                labelAttr.foregroundColor = textColor
                if isPelleUseless {
                    // SwiftUI's AttributedString attribute scope only
                    // exposes `strikethroughStyle`; the strike color
                    // inherits from `foregroundColor` (textColor here).
                    labelAttr.strikethroughStyle = .single
                }
                let labelOrigin = CGPoint(
                    x: rect.minX + Self.internalPadH,
                    y: rect.minY + Self.internalPadV
                )
                ctx.draw(ctx.resolve(Text(labelAttr)), at: labelOrigin, anchor: .topLeading)

                var descAttr = AttributedString(perk.description)
                descAttr.font = .system(size: Self.descFontSize)
                descAttr.foregroundColor = textColor
                if isPelleUseless {
                    descAttr.strikethroughStyle = .single
                }
                let descOrigin = CGPoint(
                    x: rect.minX + Self.internalPadH,
                    y: labelOrigin.y + Self.labelFontSize + Self.labelToBodyGap
                )
                let descSize = CGSize(
                    width: rect.width - 2 * Self.internalPadH,
                    height: rect.maxY - descOrigin.y - Self.internalPadV
                )
                ctx.draw(ctx.resolve(Text(descAttr)), in: CGRect(origin: descOrigin, size: descSize))
            }

            // 4. AP diamond badge — biased inward so most of the diamond
            //    sits inside the card with a small overhang into the
            //    top-right gutter. Drawn last so it always sits above
            //    lines, fills, borders, and any text that runs near the
            //    corner.
            for perk in perks where perk.automatorPoints > 0 {
                let rect = cardRect(for: perk, bounds: geom.bounds)
                let center = CGPoint(
                    x: rect.maxX - Self.badgeInset,
                    y: rect.minY + Self.badgeInset
                )
                let half = Self.badgeSize / 2
                var diamond = Path()
                diamond.move(to: CGPoint(x: center.x, y: center.y - half))
                diamond.addLine(to: CGPoint(x: center.x + half, y: center.y))
                diamond.addLine(to: CGPoint(x: center.x, y: center.y + half))
                diamond.addLine(to: CGPoint(x: center.x - half, y: center.y))
                diamond.closeSubpath()
                ctx.fill(diamond, with: .color(Self.badgeFill))
                ctx.stroke(diamond, with: .color(.black.opacity(0.7)), lineWidth: 1)

                let numText = Text("\(perk.automatorPoints)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.black)
                ctx.draw(ctx.resolve(numText), at: center, anchor: .center)
            }
        }
        .frame(width: geom.totalW, height: geom.totalH)
        .contentShape(Rectangle())
        .onTapGesture { location in
            for perk in perks {
                if cardRect(for: perk, bounds: geom.bounds).contains(location) {
                    selectedPerk = perk
                    return
                }
            }
        }

        return AnyView(canvas)
    }
}
