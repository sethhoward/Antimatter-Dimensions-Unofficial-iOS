//
//  CelestialNavigationData.swift
//  AntiMatter
//
//  Static geometry for the Celestial Navigation map. Ported from
//  src/core/secret-formula/celestials/navigation.js. All runtime
//  completion fractions / legend text live in CelestialNavigationState
//  and come from JS via pollNavigation().
//
//  Coordinate space matches the web SVG (y axis grows downward). We use
//  the node positions directly; the Canvas view translates to local
//  coordinates after computing bounds.
//

import SwiftUI

enum CelestialNavPathKind: Equatable {
    /// Straight line from one node center to another (both endpoint diameters are trimmed
    /// from the start/end so the stroke ends at the node edges).
    case linear(from: String, to: String, fromRadius: CGFloat, toRadius: CGFloat)
    /// Straight line between two explicit positions with a pathStart/pathEnd fraction
    /// trim (mirrors web's `pathStart`/`pathEnd`). Used for Ra's pet→parent-celestial
    /// gradient links where both endpoints are known positions, not node ids.
    case linearPos(from: CGPoint, to: CGPoint, pathStart: Double, pathEnd: Double)
    /// Logarithmic spiral around a center (Teresa's reality ring).
    case logSpiral(center: CGPoint, startAngle: Double, startRadius: CGFloat, endAngle: Double, endRadius: CGFloat)
    /// Arc of a circle around a center.
    case arc(center: CGPoint, radius: CGFloat, startAngle: Double, endAngle: Double)
}

/// A partial-circle "ring" rendered around Ra's central node. Drawn as a stroked
/// arc with a cut-out gap centered at `gapCenterDeg` spanning `gapDeg` degrees.
/// Matches web `ra-ring-1..5` which use the same (rMajor=90, rMinor=80) donut shape.
struct CelestialNavRingDefinition: Identifiable {
    let id: String
    let center: CGPoint
    let rMajor: CGFloat     // outer radius
    let rMinor: CGFloat     // inner radius (stroke width ≈ rMajor - rMinor)
    let gapCenterDeg: Double
    let gapDeg: Double
    let color: Color
    /// Node ID to use for visibility gating. nil = use `id`.
    /// Required for rings whose id has no matching node entry (e.g. ra-ring-1..5 gate on "ra").
    var visibilityId: String? = nil
}

struct CelestialNavNodeDefinition: Identifiable {
    let id: String
    let position: CGPoint
    let rMajor: CGFloat
    let rMinor: CGFloat?       // nil for ring-only (stroke); non-nil = filled inner circle
    let symbol: String?        // unicode glyph or SF symbol name (prefix "sf:")
    let color: Color
    /// The subtab users jump to when they tap this node. nil → no action.
    let targetSubtab: Subtab?
    let legendAngleDeg: Double
    let legendDiagonal: CGFloat
    let legendHorizontal: CGFloat
    let alwaysShowLegend: Bool
    let fallbackLegend: String
    /// Whether this node participates in the bulk "Show details" legend mode.
    /// Defaults to true. Set false on sub-tree nodes whose labels would
    /// stack on top of each other (V's 9 achievement hexagon corners, Ra's
    /// 4 pets — all at the same legend angle, all sharing the same generic
    /// fallback text). Those nodes still respond to taps; their labels are
    /// just suppressed in bulk mode to keep the map readable.
    var participatesInBulkLegend: Bool = true
}

struct CelestialNavConnectorDefinition: Identifiable {
    let id: String             // matches node id it attaches to (for completion lookup)
    let kind: CelestialNavPathKind
    /// Primary (complete) color: gradient stop A.
    let colorA: Color
    /// Secondary (complete) color: gradient stop B. If same as A → solid.
    let colorB: Color
    let completeWidth: CGFloat
    let incompleteWidth: CGFloat
    /// Node ID to use for visibility gating. nil = use `id`.
    /// Required for connectors whose id has no matching node entry (e.g. ra-pet-*-link,
    /// laitela-3rd-dim-b, laitela-destabilization-b).
    var visibilityId: String? = nil
}

enum CelestialNavigationData {
    // MARK: - Positions (direct port of navigation.js `Positions` table)

    static let teresa              = CGPoint(x: 100, y: 100)
    static let teresaPerkPointShop = CGPoint(x: 0,   y: 50)

    static let effarigShop          = CGPoint(x: 300, y: 0)
    static let effarigRealityUnlock = CGPoint(x: 400, y: 50)
    static let effarigNode          = CGPoint(x: 550, y: 25)

    static let enslavedReality     = CGPoint(x: 650, y: 250)
    /// "Break a chain" (glyph level 5000) — 75pt out from enslavedReality at -60°.
    /// Matches web `navigation.js:91`: Positions.enslavedGlyphLevel.
    static let enslavedGlyphLevel: CGPoint = {
        let angle: CGFloat = -60 * .pi / 180
        return CGPoint(x: 650 + 75 * cos(angle), y: 250 + 75 * sin(angle))
    }()
    /// "Break a chain" (glyph rarity 100) — 75pt out from enslavedReality at 120°.
    /// Matches web `navigation.js:92`: Positions.enslavedGlyphRarity.
    static let enslavedGlyphRarity: CGPoint = {
        let angle: CGFloat = 120 * .pi / 180
        return CGPoint(x: 650 + 75 * cos(angle), y: 250 + 75 * sin(angle))
    }()

    static let vUnlockAchievement  = CGPoint(x: 400, y: 350 + 50 * sqrt(3))
    // Six hexagon positions around vUnlockAchievement, matching web navigation.js
    // Positions.vAchievement0..5 (lines 95-100).
    static let vAchievement0       = CGPoint(x: 350, y: 350)
    static let vAchievement1       = CGPoint(x: 450, y: 350)
    static let vAchievement2       = CGPoint(x: 500, y: 350 + 50 * sqrt(3))
    static let vAchievement3       = CGPoint(x: 450, y: 350 + 100 * sqrt(3))
    static let vAchievement4       = CGPoint(x: 350, y: 350 + 100 * sqrt(3))
    static let vAchievement5       = CGPoint(x: 300, y: 350 + 50 * sqrt(3))

    static let raReality           = CGPoint(x: 400, y: 200)
    // Four pet positions — 85pt polar offsets from raReality at 252°/140°/78°/0°.
    // Web uses Math.sin(θ) for x and Math.cos(θ) for y, where θ is in radians.
    private static func raPolar(angleDeg: Double) -> CGPoint {
        let r = angleDeg * .pi / 180
        return CGPoint(x: 400 + 85 * sin(r), y: 200 + 85 * cos(r))
    }
    static let raPetTeresa   = raPolar(angleDeg: 252)
    static let raPetEffarig  = raPolar(angleDeg: 140)
    static let raPetEnslaved = raPolar(angleDeg: 78)
    static let raPetV        = raPolar(angleDeg: 0)

    static let laitelaFirstCenter  = CGPoint(x: 150, y: 450)
    static let laitelaFirstLeft    = CGPoint(x: 100, y: 500)
    static let laitelaFirstRight   = CGPoint(x: 200, y: 500)
    static let laitelaSecondCenter = CGPoint(x: 150, y: 550)
    static let laitelaSecondLeft   = CGPoint(x: 100, y: 600)
    static let laitelaSecondRight  = CGPoint(x: 200, y: 600)
    static let laitelaThirdCenter  = CGPoint(x: 150, y: 650)

    static let pelleUnlock         = CGPoint(x: 450, y: 580)

    // MARK: - Canvas bounds

    /// Logical SVG bounds used by the web version. Canvas centers content here.
    static let canvasBounds = CGRect(x: -100, y: -100, width: 900, height: 900)

    // MARK: - Nodes (primary celestials + Teresa's shop)

    static let nodes: [CelestialNavNodeDefinition] = [
        CelestialNavNodeDefinition(
            id: "teresa-reality-unlock",
            position: teresa, rMajor: 32, rMinor: 22,
            symbol: "Ϟ", color: GameColor.teresa,
            targetSubtab: .teresa,
            legendAngleDeg: 135, legendDiagonal: 16, legendHorizontal: 16,
            alwaysShowLegend: false,
            fallbackLegend: "Teresa"
        ),
        CelestialNavNodeDefinition(
            id: "teresa-pp-shop",
            position: teresaPerkPointShop, rMajor: 16, rMinor: 0,
            symbol: nil, color: GameColor.teresa,
            targetSubtab: .teresa,
            legendAngleDeg: -35, legendDiagonal: 16, legendHorizontal: 16,
            alwaysShowLegend: false,
            fallbackLegend: "Teresa's Perk Point Shop"
        ),
        CelestialNavNodeDefinition(
            id: "effarig-shop",
            position: effarigShop, rMajor: 24, rMinor: nil,
            symbol: "Ϙ", color: GameColor.effarig,
            targetSubtab: .effarig,
            legendAngleDeg: -135, legendDiagonal: 16, legendHorizontal: 16,
            alwaysShowLegend: false,
            fallbackLegend: "Effarig's Shop"
        ),
        // The "Unlock Effarig's Reality" small ring sits between the shop and the
        // concentric run-completion rings (web navigation.js:357 — rMajor=16).
        CelestialNavNodeDefinition(
            id: "effarig-reality-unlock",
            position: effarigRealityUnlock, rMajor: 16, rMinor: nil,
            symbol: nil, color: GameColor.effarig,
            targetSubtab: .effarig,
            legendAngleDeg: 75, legendDiagonal: 40, legendHorizontal: 16,
            alwaysShowLegend: false,
            fallbackLegend: "Unlock Effarig's Reality"
        ),
        // Three concentric run-completion rings at effarigNode. Outer = Infinity
        // stage, middle = Eternity stage, filled center = Reality stage.
        // Drawn in this order so the small filled center + symbol render on top
        // of the larger rings (Canvas iterates `nodes` in array order).
        CelestialNavNodeDefinition(
            id: "effarig-infinity",
            position: effarigNode, rMajor: 60, rMinor: nil,
            symbol: nil, color: GameColor.effarig,
            targetSubtab: .effarig,
            legendAngleDeg: 0, legendDiagonal: 100, legendHorizontal: 16,
            alwaysShowLegend: false,
            fallbackLegend: "Effarig's Infinity"
        ),
        CelestialNavNodeDefinition(
            id: "effarig-eternity",
            position: effarigNode, rMajor: 40, rMinor: nil,
            symbol: nil, color: GameColor.effarig,
            targetSubtab: .effarig,
            legendAngleDeg: -45, legendDiagonal: 16, legendHorizontal: 16,
            alwaysShowLegend: false,
            fallbackLegend: "Effarig's Eternity"
        ),
        CelestialNavNodeDefinition(
            id: "effarig-reality",
            position: effarigNode, rMajor: 20, rMinor: 18,
            symbol: "Ϙ", color: GameColor.effarig,
            targetSubtab: .effarig,
            legendAngleDeg: -120, legendDiagonal: 82, legendHorizontal: 16,
            alwaysShowLegend: true,
            fallbackLegend: "Effarig's Reality"
        ),
        CelestialNavNodeDefinition(
            id: "enslaved-reality",
            position: enslavedReality, rMajor: 32, rMinor: 22,
            symbol: nil, color: GameColor.enslaved,
            targetSubtab: .namelessOnes,
            legendAngleDeg: 45, legendDiagonal: 16, legendHorizontal: 16,
            alwaysShowLegend: false,
            fallbackLegend: "The Nameless Ones"
        ),
        // "Break a chain" unlock rings — glyph level 5000 + rarity 100 requirements
        // for the Nameless Ones' RUN unlock. Web navigation.js:567 / :609.
        CelestialNavNodeDefinition(
            id: "enslaved-unlock-glyph-level",
            position: enslavedGlyphLevel, rMajor: 22, rMinor: nil,
            symbol: nil, color: GameColor.enslaved,
            targetSubtab: .namelessOnes,
            legendAngleDeg: -60, legendDiagonal: 16, legendHorizontal: 16,
            alwaysShowLegend: false,
            fallbackLegend: "Break a chain"
        ),
        CelestialNavNodeDefinition(
            id: "enslaved-unlock-glyph-rarity",
            position: enslavedGlyphRarity, rMajor: 22, rMinor: nil,
            symbol: nil, color: GameColor.enslaved,
            targetSubtab: .namelessOnes,
            legendAngleDeg: 120, legendDiagonal: 16, legendHorizontal: 16,
            alwaysShowLegend: false,
            fallbackLegend: "Break a chain"
        ),
        CelestialNavNodeDefinition(
            id: "v-unlock-achievement",
            position: vUnlockAchievement, rMajor: 32, rMinor: 22,
            symbol: "⌬", color: GameColor.v,
            targetSubtab: .v,
            legendAngleDeg: 135, legendDiagonal: 16, legendHorizontal: 16,
            alwaysShowLegend: false,
            fallbackLegend: "V"
        ),
        CelestialNavNodeDefinition(
            id: "ra",
            position: raReality, rMajor: 32, rMinor: 22,
            // Web uses Font Awesome `\uf185` sun; we don't bundle FA. Route to
            // the SF Symbol sun (same escape-hatch CelestialPalette uses for
            // Ra's quote-modal watermark). drawNodes() branches on "sf:".
            symbol: "sf:sun.max.fill", color: GameColor.ra,
            targetSubtab: .ra,
            legendAngleDeg: 90, legendDiagonal: 16, legendHorizontal: 16,
            alwaysShowLegend: false,
            fallbackLegend: "Ra"
        ),
        CelestialNavNodeDefinition(
            id: "laitela",
            position: laitelaFirstCenter, rMajor: 24, rMinor: 16,
            symbol: "ᛝ", color: GameColor.laitela,
            targetSubtab: .laitela,
            legendAngleDeg: -135, legendDiagonal: 16, legendHorizontal: 16,
            // Always show the multi-line progress legend (Reality Machines
            // bind you / antimatter goal / ID blocker) — mirrors web
            // navigation.js:1447 `alwaysShowLegend: true`.
            alwaysShowLegend: true,
            fallbackLegend: "Lai'tela's Reality"
        ),
        CelestialNavNodeDefinition(
            id: "pelle",
            position: pelleUnlock, rMajor: 32, rMinor: 22,
            symbol: "♅", color: GameColor.pelle,
            targetSubtab: .pelle,
            legendAngleDeg: 45, legendDiagonal: 16, legendHorizontal: 16,
            alwaysShowLegend: false,
            fallbackLegend: "Pelle"
        )
    ] + vSubTreeNodes + raPetNodes + laitelaSubTreeNodes

    static let nodesByID: [String: CelestialNavNodeDefinition] = {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }()

    // MARK: - Connectors

    static let connectors: [CelestialNavConnectorDefinition] = [
        // Teresa reality ring — logarithmic spiral around Teresa's node.
        CelestialNavConnectorDefinition(
            id: "teresa-reality-unlock",
            kind: .logSpiral(center: teresa,
                             startAngle: -.pi, startRadius: 69,
                             endAngle: .pi, endRadius: 26),
            colorA: GameColor.teresa, colorB: GameColor.teresa,
            completeWidth: 6, incompleteWidth: 4
        ),
        // Teresa → Teresa's Perk Point Shop
        CelestialNavConnectorDefinition(
            id: "teresa-pp-shop",
            kind: .linear(from: "teresa-reality-unlock", to: "teresa-pp-shop",
                          fromRadius: 78, toRadius: 15),
            colorA: GameColor.teresa, colorB: GameColor.teresa,
            completeWidth: 6, incompleteWidth: 4
        ),
        // Teresa → Effarig Shop (gradient)
        CelestialNavConnectorDefinition(
            id: "effarig-shop",
            kind: .linear(from: "teresa-reality-unlock", to: "effarig-shop",
                          fromRadius: 80, toRadius: 23),
            colorA: GameColor.teresa, colorB: GameColor.effarig,
            completeWidth: 6, incompleteWidth: 4
        ),
        // Effarig Shop → "Unlock Effarig's Reality" small ring.
        CelestialNavConnectorDefinition(
            id: "effarig-reality-unlock",
            kind: .linear(from: "effarig-shop", to: "effarig-reality-unlock",
                          fromRadius: 23, toRadius: 15),
            colorA: GameColor.effarig, colorB: GameColor.effarig,
            completeWidth: 6, incompleteWidth: 4
        ),
        // Unlock ring → outer Infinity ring (effarigNode).
        CelestialNavConnectorDefinition(
            id: "effarig-infinity",
            kind: .linear(from: "effarig-reality-unlock", to: "effarig-infinity",
                          fromRadius: 15, toRadius: 59),
            colorA: GameColor.effarig, colorB: GameColor.effarig,
            completeWidth: 6, incompleteWidth: 4
        ),
        // Eternity stage — log spiral from below the rings into the middle ring.
        // Web: LogarithmicSpiral.fromPolarEndpoints((560,25), -π → 0, r 66 → 26).
        CelestialNavConnectorDefinition(
            id: "effarig-eternity",
            kind: .logSpiral(center: CGPoint(x: 560, y: 25),
                             startAngle: -.pi, startRadius: 66,
                             endAngle: 0, endRadius: 26),
            colorA: GameColor.effarig, colorB: GameColor.effarig,
            completeWidth: 6, incompleteWidth: 4
        ),
        // Reality stage — continues the spiral from the middle into the centre.
        // Web: LogarithmicSpiral.fromPolarEndpoints((558,25), 0 → π, r 26 → 24).
        CelestialNavConnectorDefinition(
            id: "effarig-reality",
            kind: .logSpiral(center: CGPoint(x: 558, y: 25),
                             startAngle: 0, startRadius: 26,
                             endAngle: .pi, endRadius: 24),
            colorA: GameColor.effarig, colorB: GameColor.effarig,
            completeWidth: 6, incompleteWidth: 4
        ),
        // Effarig (outer Eternity ring) → Enslaved. Web uses Positions.effarigNode
        // at r=40-1, the Eternity ring's outer edge.
        CelestialNavConnectorDefinition(
            id: "enslaved-reality",
            kind: .linear(from: "effarig-eternity", to: "enslaved-reality",
                          fromRadius: 39, toRadius: 31),
            colorA: GameColor.effarig, colorB: GameColor.enslaved,
            completeWidth: 6, incompleteWidth: 4
        ),
        // Glyph-level chain ring → Enslaved (trimmed both ends per the web).
        CelestialNavConnectorDefinition(
            id: "enslaved-unlock-glyph-level",
            kind: .linear(from: "enslaved-unlock-glyph-level", to: "enslaved-reality",
                          fromRadius: 21, toRadius: 31),
            colorA: GameColor.enslaved, colorB: GameColor.enslaved,
            completeWidth: 6, incompleteWidth: 4
        ),
        // Glyph-rarity chain ring → Glyph-level ring.
        CelestialNavConnectorDefinition(
            id: "enslaved-unlock-glyph-rarity",
            kind: .linear(from: "enslaved-unlock-glyph-rarity", to: "enslaved-unlock-glyph-level",
                          fromRadius: 21, toRadius: 21),
            colorA: GameColor.enslaved, colorB: GameColor.enslaved,
            completeWidth: 6, incompleteWidth: 4
        ),
        // Enslaved → V
        CelestialNavConnectorDefinition(
            id: "v-unlock-achievement",
            kind: .linear(from: "enslaved-reality", to: "v-unlock-achievement",
                          fromRadius: 31, toRadius: 31),
            colorA: GameColor.enslaved, colorB: GameColor.v,
            completeWidth: 6, incompleteWidth: 4
        ),
        // V → Ra
        CelestialNavConnectorDefinition(
            id: "ra",
            kind: .linear(from: "v-unlock-achievement", to: "ra",
                          fromRadius: 31, toRadius: 31),
            colorA: GameColor.v, colorB: GameColor.ra,
            completeWidth: 6, incompleteWidth: 4
        ),
        // Ra → Lai'tela
        CelestialNavConnectorDefinition(
            id: "laitela",
            kind: .linear(from: "ra", to: "laitela",
                          fromRadius: 31, toRadius: 23),
            colorA: GameColor.ra, colorB: GameColor.laitela,
            completeWidth: 6, incompleteWidth: 4
        ),
        // Lai'tela → Pelle
        CelestialNavConnectorDefinition(
            id: "pelle",
            kind: .linear(from: "laitela", to: "pelle",
                          fromRadius: 23, toRadius: 31),
            colorA: GameColor.laitela, colorB: GameColor.pelle,
            completeWidth: 6, incompleteWidth: 4
        )
    ] + vSubTreeConnectors + raPetConnectors + laitelaSubTreeConnectors

    // MARK: - V sub-tree (6 unlock spokes + 9 achievement hexagons)
    // Ported from navigation.js lines 740-1124. Yellow #ffe066 throughout.

    private static let vYellow = GameColor.v  // GameColor.v = #ffe066

    static let vSubTreeNodes: [CelestialNavNodeDefinition] = {
        func unlockNode(_ i: Int, _ pos: CGPoint, _ angle: Double) -> CelestialNavNodeDefinition {
            CelestialNavNodeDefinition(
                id: "v-unlock-\(i)",
                position: pos, rMajor: 8, rMinor: 6,
                symbol: nil, color: vYellow, targetSubtab: .v,
                legendAngleDeg: angle, legendDiagonal: 30, legendHorizontal: 16,
                alwaysShowLegend: false, fallbackLegend: "V unlock",
                participatesInBulkLegend: false
            )
        }
        func achNode(_ i: Int, _ pos: CGPoint, _ angle: Double) -> CelestialNavNodeDefinition {
            CelestialNavNodeDefinition(
                id: "v-achievement-\(i)",
                position: pos, rMajor: 8, rMinor: 6,
                symbol: nil, color: vYellow, targetSubtab: .v,
                legendAngleDeg: angle, legendDiagonal: 16, legendHorizontal: 16,
                alwaysShowLegend: false, fallbackLegend: "V-Achievement",
                participatesInBulkLegend: false
            )
        }
        return [
            // Web navigation.js: v-unlock-{1..6} position map:
            // 1 → vAchievement1, 2 → vAchievement2, 3 → vAchievement3,
            // 4 → vAchievement4, 5 → vAchievement5, 6 → vAchievement0.
            unlockNode(1, vAchievement1, -135),
            unlockNode(2, vAchievement2, -45),
            unlockNode(3, vAchievement3, 45),
            unlockNode(4, vAchievement4, 135),
            unlockNode(5, vAchievement5, -135),
            unlockNode(6, vAchievement0, -135),
            achNode(0, vAchievement0, -135),
            achNode(1, vAchievement1, 20),
            achNode(2, vAchievement2, -45),
            achNode(3, vAchievement3, 135),
            achNode(4, vAchievement4, 60),
            achNode(5, vAchievement5, -100),
            achNode(6, vAchievement1, 20),     // Hard-0 overlays vA1
            achNode(7, vAchievement3, 60),     // Hard-1 overlays vA3
            achNode(8, vAchievement5, -100)    // Hard-2 overlays vA5
        ]
    }()

    static let vSubTreeConnectors: [CelestialNavConnectorDefinition] = {
        func spoke(_ i: Int, _ target: String) -> CelestialNavConnectorDefinition {
            CelestialNavConnectorDefinition(
                id: "v-unlock-\(i)",
                kind: .linear(from: "v-unlock-achievement", to: target,
                              fromRadius: 20, toRadius: 8),
                colorA: vYellow, colorB: vYellow,
                completeWidth: 6, incompleteWidth: 4
            )
        }
        func ring(_ i: Int, _ from: String, _ to: String) -> CelestialNavConnectorDefinition {
            CelestialNavConnectorDefinition(
                id: "v-achievement-\(i)",
                kind: .linear(from: from, to: to, fromRadius: 8, toRadius: 8),
                colorA: vYellow, colorB: vYellow,
                completeWidth: 6, incompleteWidth: 4
            )
        }
        return [
            spoke(1, "v-unlock-1"), spoke(2, "v-unlock-2"), spoke(3, "v-unlock-3"),
            spoke(4, "v-unlock-4"), spoke(5, "v-unlock-5"), spoke(6, "v-unlock-6"),
            ring(0, "v-achievement-5", "v-achievement-0"),
            ring(1, "v-achievement-0", "v-achievement-1"),
            ring(2, "v-achievement-1", "v-achievement-2"),
            ring(3, "v-achievement-2", "v-achievement-3"),
            ring(4, "v-achievement-3", "v-achievement-4"),
            ring(5, "v-achievement-4", "v-achievement-5")
        ]
    }()

    // MARK: - Ra sub-tree (4 pet nodes + 4 ra→pet spokes + 4 pet→parent gradient links)

    static let raPetNodes: [CelestialNavNodeDefinition] = {
        func pet(_ key: String, _ pos: CGPoint, _ angle: Double) -> CelestialNavNodeDefinition {
            CelestialNavNodeDefinition(
                id: "ra-pet-\(key)",
                position: pos, rMajor: 12, rMinor: 8,
                symbol: nil, color: GameColor.ra, targetSubtab: .ra,
                legendAngleDeg: angle, legendDiagonal: 30, legendHorizontal: 16,
                alwaysShowLegend: false, fallbackLegend: "Ra's pet",
                participatesInBulkLegend: false
            )
        }
        return [
            pet("teresa",   raPetTeresa,   142),
            pet("effarig",  raPetEffarig,  142),
            pet("enslaved", raPetEnslaved, 142),
            pet("v",        raPetV,        142)
        ]
    }()

    static let raPetConnectors: [CelestialNavConnectorDefinition] = [
        // ra → each pet (purple spokes)
        CelestialNavConnectorDefinition(
            id: "ra-pet-teresa",
            kind: .linear(from: "ra", to: "ra-pet-teresa", fromRadius: 31, toRadius: 11),
            colorA: GameColor.ra, colorB: GameColor.ra,
            completeWidth: 6, incompleteWidth: 4
        ),
        CelestialNavConnectorDefinition(
            id: "ra-pet-effarig",
            kind: .linear(from: "ra", to: "ra-pet-effarig", fromRadius: 31, toRadius: 11),
            colorA: GameColor.ra, colorB: GameColor.ra,
            completeWidth: 6, incompleteWidth: 4
        ),
        CelestialNavConnectorDefinition(
            id: "ra-pet-enslaved",
            kind: .linear(from: "ra", to: "ra-pet-enslaved", fromRadius: 31, toRadius: 11),
            colorA: GameColor.ra, colorB: GameColor.ra,
            completeWidth: 6, incompleteWidth: 4
        ),
        CelestialNavConnectorDefinition(
            id: "ra-pet-v",
            kind: .linear(from: "ra", to: "ra-pet-v", fromRadius: 31, toRadius: 11),
            colorA: GameColor.ra, colorB: GameColor.ra,
            completeWidth: 6, incompleteWidth: 4
        ),
        // pet → parent celestial (gradient links — completion = pet level / 25)
        // visibilityId maps each link to its corresponding pet node (the link id is synthetic).
        CelestialNavConnectorDefinition(
            id: "ra-pet-teresa-link",
            kind: .linearPos(from: raPetTeresa, to: teresa, pathStart: 0.05, pathEnd: 0.70),
            colorA: GameColor.ra, colorB: GameColor.teresa,
            completeWidth: 6, incompleteWidth: 4,
            visibilityId: "ra-pet-teresa"
        ),
        CelestialNavConnectorDefinition(
            id: "ra-pet-effarig-link",
            kind: .linearPos(from: raPetEffarig, to: effarigNode, pathStart: 0.05, pathEnd: 0.60),
            colorA: GameColor.ra, colorB: GameColor.effarig,
            completeWidth: 6, incompleteWidth: 4,
            visibilityId: "ra-pet-effarig"
        ),
        CelestialNavConnectorDefinition(
            id: "ra-pet-enslaved-link",
            kind: .linearPos(from: raPetEnslaved, to: enslavedReality, pathStart: 0.05, pathEnd: 0.55),
            colorA: GameColor.ra, colorB: GameColor.enslaved,
            completeWidth: 6, incompleteWidth: 4,
            visibilityId: "ra-pet-enslaved"
        ),
        CelestialNavConnectorDefinition(
            id: "ra-pet-v-link",
            kind: .linearPos(from: raPetV, to: vUnlockAchievement, pathStart: 0.05, pathEnd: 0.42),
            colorA: GameColor.ra, colorB: GameColor.v,
            completeWidth: 6, incompleteWidth: 4,
            visibilityId: "ra-pet-v"
        )
    ]

    // MARK: - Ra decorative rings (5 partial circles around ra)

    static let raRings: [CelestialNavRingDefinition] = [
        CelestialNavRingDefinition(id: "ra-ring-1", center: raReality, rMajor: 90, rMinor: 80,
                                   gapCenterDeg: 74,  gapDeg: 268, color: GameColor.ra, visibilityId: "ra"),
        CelestialNavRingDefinition(id: "ra-ring-2", center: raReality, rMajor: 90, rMinor: 80,
                                   gapCenterDeg: 161, gapDeg: 318, color: GameColor.ra, visibilityId: "ra"),
        CelestialNavRingDefinition(id: "ra-ring-3", center: raReality, rMajor: 90, rMinor: 80,
                                   gapCenterDeg: 231, gapDeg: 301, color: GameColor.ra, visibilityId: "ra"),
        CelestialNavRingDefinition(id: "ra-ring-4", center: raReality, rMajor: 90, rMinor: 80,
                                   gapCenterDeg: 293, gapDeg: 334, color: GameColor.ra, visibilityId: "ra"),
        CelestialNavRingDefinition(id: "ra-ring-5", center: raReality, rMajor: 90, rMinor: 80,
                                   gapCenterDeg: -14, gapDeg: 316, color: GameColor.ra, visibilityId: "ra")
    ]

    // MARK: - Laitela sub-tree (6 dimension nodes + 9 connectors)

    static let laitelaSubTreeNodes: [CelestialNavNodeDefinition] = [
        CelestialNavNodeDefinition(
            id: "laitela-2nd-dim",
            position: laitelaFirstLeft, rMajor: 8, rMinor: 6,
            symbol: "2", color: GameColor.laitela, targetSubtab: .laitela,
            legendAngleDeg: 135, legendDiagonal: 30, legendHorizontal: 16,
            alwaysShowLegend: false, fallbackLegend: "2nd Dark Matter Dimension"
        ),
        CelestialNavNodeDefinition(
            id: "laitela-singularity",
            position: laitelaFirstRight, rMajor: 8, rMinor: 6,
            symbol: nil, color: GameColor.laitela, targetSubtab: .laitela,
            legendAngleDeg: 45, legendDiagonal: 50, legendHorizontal: 16,
            alwaysShowLegend: false, fallbackLegend: "Singularity"
        ),
        CelestialNavNodeDefinition(
            id: "laitela-3rd-dim",
            position: laitelaSecondCenter, rMajor: 15, rMinor: 10,
            symbol: "3", color: GameColor.laitela, targetSubtab: .laitela,
            legendAngleDeg: 15, legendDiagonal: 30, legendHorizontal: 16,
            alwaysShowLegend: false, fallbackLegend: "3rd Dark Matter Dimension"
        ),
        CelestialNavNodeDefinition(
            id: "laitela-4th-dim",
            position: laitelaSecondLeft, rMajor: 8, rMinor: 6,
            symbol: "4", color: GameColor.laitela, targetSubtab: .laitela,
            legendAngleDeg: 225, legendDiagonal: 30, legendHorizontal: 16,
            alwaysShowLegend: false, fallbackLegend: "4th Dark Matter Dimension"
        ),
        CelestialNavNodeDefinition(
            id: "laitela-annihilation",
            position: laitelaSecondRight, rMajor: 8, rMinor: 6,
            symbol: nil, color: GameColor.laitela, targetSubtab: .laitela,
            legendAngleDeg: 315, legendDiagonal: 30, legendHorizontal: 16,
            alwaysShowLegend: false, fallbackLegend: "Annihilate DMDs"
        ),
        CelestialNavNodeDefinition(
            id: "laitela-destabilization",
            position: laitelaThirdCenter, rMajor: 15, rMinor: 10,
            symbol: nil, color: GameColor.laitela, targetSubtab: .laitela,
            legendAngleDeg: 180, legendDiagonal: 30, legendHorizontal: 16,
            alwaysShowLegend: false, fallbackLegend: "Destabilize Lai'tela's Reality"
        )
    ]

    static let laitelaSubTreeConnectors: [CelestialNavConnectorDefinition] = [
        // unlock → 2nd-dim
        CelestialNavConnectorDefinition(
            id: "laitela-2nd-dim",
            kind: .linear(from: "laitela", to: "laitela-2nd-dim", fromRadius: 14, toRadius: 7),
            colorA: GameColor.laitela, colorB: GameColor.laitela,
            completeWidth: 6, incompleteWidth: 4
        ),
        // unlock → singularity
        CelestialNavConnectorDefinition(
            id: "laitela-singularity",
            kind: .linear(from: "laitela", to: "laitela-singularity", fromRadius: 14, toRadius: 7),
            colorA: GameColor.laitela, colorB: GameColor.laitela,
            completeWidth: 6, incompleteWidth: 4
        ),
        // 2nd-dim → 3rd-dim
        CelestialNavConnectorDefinition(
            id: "laitela-3rd-dim",
            kind: .linear(from: "laitela-2nd-dim", to: "laitela-3rd-dim", fromRadius: 7, toRadius: 14),
            colorA: GameColor.laitela, colorB: GameColor.laitela,
            completeWidth: 6, incompleteWidth: 4
        ),
        // singularity → 3rd-dim (secondary path; gates on the destination node like the primary)
        CelestialNavConnectorDefinition(
            id: "laitela-3rd-dim-b",
            kind: .linear(from: "laitela-singularity", to: "laitela-3rd-dim", fromRadius: 7, toRadius: 14),
            colorA: GameColor.laitela, colorB: GameColor.laitela,
            completeWidth: 6, incompleteWidth: 4,
            visibilityId: "laitela-3rd-dim"
        ),
        // 3rd-dim → 4th-dim
        CelestialNavConnectorDefinition(
            id: "laitela-4th-dim",
            kind: .linear(from: "laitela-3rd-dim", to: "laitela-4th-dim", fromRadius: 14, toRadius: 7),
            colorA: GameColor.laitela, colorB: GameColor.laitela,
            completeWidth: 6, incompleteWidth: 4
        ),
        // 3rd-dim → annihilation
        CelestialNavConnectorDefinition(
            id: "laitela-annihilation",
            kind: .linear(from: "laitela-3rd-dim", to: "laitela-annihilation", fromRadius: 14, toRadius: 7),
            colorA: GameColor.laitela, colorB: GameColor.laitela,
            completeWidth: 6, incompleteWidth: 4
        ),
        // 4th-dim → destabilization
        CelestialNavConnectorDefinition(
            id: "laitela-destabilization",
            kind: .linear(from: "laitela-4th-dim", to: "laitela-destabilization", fromRadius: 7, toRadius: 14),
            colorA: GameColor.laitela, colorB: GameColor.laitela,
            completeWidth: 6, incompleteWidth: 4
        ),
        // annihilation → destabilization (secondary path; gates on the destination node like the primary)
        CelestialNavConnectorDefinition(
            id: "laitela-destabilization-b",
            kind: .linear(from: "laitela-annihilation", to: "laitela-destabilization", fromRadius: 7, toRadius: 14),
            colorA: GameColor.laitela, colorB: GameColor.laitela,
            completeWidth: 6, incompleteWidth: 4,
            visibilityId: "laitela-destabilization"
        )
    ]

    // MARK: - Path sampling

    /// Samples a path into N points (including both endpoints) in the path's native
    /// coordinate space. Canvas translates these by -bounds.origin.
    static func samplePoints(_ kind: CelestialNavPathKind, samples: Int = 40) -> [CGPoint] {
        switch kind {
        case .linear(let from, let to, let fromRadius, let toRadius):
            guard let a = nodesByID[from]?.position,
                  let b = nodesByID[to]?.position else { return [] }
            let dx = b.x - a.x, dy = b.y - a.y
            let dist = hypot(dx, dy)
            guard dist > 0 else { return [a] }
            let ux = dx / dist, uy = dy / dist
            let start = CGPoint(x: a.x + ux * fromRadius, y: a.y + uy * fromRadius)
            let end   = CGPoint(x: b.x - ux * toRadius,   y: b.y - uy * toRadius)
            return [start, end]

        case .linearPos(let a, let b, let pathStart, let pathEnd):
            let dx = b.x - a.x, dy = b.y - a.y
            let dist = hypot(dx, dy)
            guard dist > 0 else { return [a] }
            let s = max(0, min(pathStart, 1)), e = max(0, min(pathEnd, 1))
            let start = CGPoint(x: a.x + dx * s, y: a.y + dy * s)
            let end   = CGPoint(x: a.x + dx * e, y: a.y + dy * e)
            return [start, end]

        case .logSpiral(let center, let startAngle, let startRadius, let endAngle, let endRadius):
            // Logarithmic spiral: r(θ) = a·e^(kθ) where a,k solve startRadius/endRadius at endpoints.
            let k = log(endRadius / startRadius) / (endAngle - startAngle)
            let a = startRadius / exp(k * startAngle)
            var pts: [CGPoint] = []
            pts.reserveCapacity(samples + 1)
            for i in 0...samples {
                let t = Double(i) / Double(samples)
                let theta = startAngle + (endAngle - startAngle) * t
                let r = a * exp(k * theta)
                pts.append(CGPoint(x: center.x + r * cos(theta),
                                   y: center.y + r * sin(theta)))
            }
            return pts

        case .arc(let center, let radius, let startAngle, let endAngle):
            var pts: [CGPoint] = []
            pts.reserveCapacity(samples + 1)
            for i in 0...samples {
                let t = Double(i) / Double(samples)
                let theta = startAngle + (endAngle - startAngle) * t
                pts.append(CGPoint(x: center.x + radius * cos(theta),
                                   y: center.y + radius * sin(theta)))
            }
            return pts
        }
    }
}
