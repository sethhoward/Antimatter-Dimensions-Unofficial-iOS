//
//  InfinityUpgradesTab.swift
//  AntiMatter
//
//  Infinity Upgrades — 4x4 grid of upgrades purchased with Infinity Points,
//  plus a repeatable 2x IP multiplier and offline IP generation upgrade.
//  Colors match the web Modern UI dark theme per-column scheme.
//

import SwiftUI

struct InfinityUpgradesTab: View {
    let engine: GameEngine

    /// Mirrors web's shift-key preview — when true, charged upgrades show
    /// their charged effect description instead of the normal one.
    @State private var showCharged = false

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if engine.pelleDoomed {
                    PelleSimpleDisabledBanner(
                        text: "Pre-Doom Infinity Upgrades and IP multipliers are disabled. Infinity Upgrades cannot be charged while Doomed."
                    )
                }
                InfinityUpgradesHeader(engine: engine)
                InfinityUpgradesChargeControls(engine: engine, showCharged: $showCharged)
                if metrics.isCompact && engine.gameState.infinity.ipMultUnlocked {
                    InfinityUpgradesIPMultTopRow(engine: engine)
                    InfinityUpgradesCapDisclosure(engine: engine)
                }
                InfinityUpgradesGrid(engine: engine, showCharged: showCharged)
                InfinityUpgradesBottomRow(engine: engine, hideIPMult: metrics.isCompact)
                if !metrics.isCompact && engine.gameState.infinity.ipMultUnlocked {
                    InfinityUpgradesCapDisclosure(engine: engine)
                }
                PhoneTabBarSpacer()
            }
            .padding()
        }
    }
}

// MARK: - Charge Controls (Ra Teresa pet lv 2)

private struct InfinityUpgradesChargeControls: View {
    let engine: GameEngine
    @Binding var showCharged: Bool

    var body: some View {
        let inf = engine.gameState.infinity
        InfinityUpgradesChargeControlsInner(
            chargeUnlocked: inf.chargeInfinityUpgradesUnlocked,
            disChargeOnReality: inf.disChargeOnReality,
            usedCharges: inf.usedInfinityCharges,
            totalCharges: inf.totalInfinityCharges,
            showCharged: showCharged,
            onRespec: { engine.toggleInfinityChargeRespec() },
            onToggleShowCharged: { showCharged.toggle() }
        ).equatable()
    }
}

/// All four state inputs are transition-only (charge unlock, respec toggle,
/// per-Reality charge counters). Body skips every tick at idle.
private struct InfinityUpgradesChargeControlsInner: View, Equatable {
    let chargeUnlocked: Bool
    let disChargeOnReality: Bool
    let usedCharges: Int
    let totalCharges: Int
    let showCharged: Bool
    let onRespec: () -> Void
    let onToggleShowCharged: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chargeUnlocked == rhs.chargeUnlocked
            && lhs.disChargeOnReality == rhs.disChargeOnReality
            && lhs.usedCharges == rhs.usedCharges
            && lhs.totalCharges == rhs.totalCharges
            && lhs.showCharged == rhs.showCharged
    }

    var body: some View {
        if chargeUnlocked {
            VStack(spacing: 8) {
                Button(action: onRespec) {
                    Text(disChargeOnReality
                         ? "Respec scheduled — cancel on next Reality"
                         : "Respec Charged Infinity Upgrades on next Reality")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(disChargeOnReality ? .black : GameColor.teresa)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(disChargeOnReality ? GameColor.teresa : .black)
                        .roundedBorder(GameColor.teresa, lineWidth: 1.5)
                }
                .buttonStyle(.plain)

                Button(action: onToggleShowCharged) {
                    HStack(spacing: 6) {
                        Image(systemName: showCharged ? "bolt.fill" : "bolt")
                        Text(showCharged
                             ? "Showing: Charged effects — tap an upgrade to charge it"
                             : "Showing: Normal effects — tap to swap to charged")
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(showCharged ? .yellow : GameColor.teresa)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black)
                    .roundedBorder(showCharged ? .yellow : GameColor.teresa, lineWidth: 1)
                }
                .buttonStyle(.plain)

                Text("Charged \(usedCharges)/\(totalCharges) Infinity Upgrades. Charged upgrades have their effect altered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Header

private struct InfinityUpgradesHeader: View {
    let engine: GameEngine

    var body: some View {
        let inf = engine.gameState.infinity
        VStack(spacing: 8) {
            Text("You have \(inf.currentIP) Infinity Points")
                .font(.title3.weight(.medium).monospacedDigit())
                .foregroundStyle(GameColor.infinity)
            Text("You will gain \(inf.gainedIP) IP on Big Crunch")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("Within each column, the upgrades must be purchased from top to bottom.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 4x4 Grid (2-column on iPhone)

private struct InfinityUpgradesGrid: View {
    let engine: GameEngine
    let showCharged: Bool

    @Environment(\.layoutMetrics) private var metrics
    @State private var compactGridWidth: CGFloat = 0

    var body: some View {
        let upgrades = engine.gameState.infinity.upgrades
        // Group upgrades into columns (0-3), sorted by row
        let columns: [[InfinityUpgradeInfo]] = (0...3).map { col in
            upgrades.filter { $0.column == col }.sorted { $0.row < $1.row }
        }

        if metrics.isCompact {
            // Preserve web column semantics on iPhone — each column is
            // its own top-to-bottom stack so the "purchase top to bottom
            // within each column" hint matches the visible layout.
            // Horizontal scroll since 4 columns don't fit screen width.
            // Column width is sized so a sliver of the next column peeks
            // past the trailing edge as a swipe affordance.
            let columnWidth = max(120, (compactGridWidth - 40) / 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(0..<4, id: \.self) { col in
                        VStack(spacing: 8) {
                            ForEach(columns[col]) { upgrade in
                                InfinityUpgradeButton(upgrade: upgrade, column: col, showCharged: showCharged, isPelleDoomed: engine.pelleDoomed) {
                                    engine.buyInfinityUpgrade(upgrade.id)
                                }
                                .equatable()
                            }
                        }
                        .frame(width: columnWidth)
                        .background(InfinityUpgradesColumnBackground(cells: columns[col]).equatable())
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 4)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollEdgeFade()
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                compactGridWidth = newWidth
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<4, id: \.self) { col in
                    VStack(spacing: 8) {
                        ForEach(columns[col]) { upgrade in
                            InfinityUpgradeButton(upgrade: upgrade, column: col, showCharged: showCharged, isPelleDoomed: engine.pelleDoomed) {
                                engine.buyInfinityUpgrade(upgrade.id)
                            }
                            .equatable()
                        }
                    }
                    .background(InfinityUpgradesColumnBackground(cells: columns[col]).equatable())
                }
            }
        }
    }
}

// MARK: - Bottom Row (IP Mult + Offline)

private struct InfinityUpgradesBottomRow: View {
    let engine: GameEngine
    /// iPhone hoists the Multiply/Buy Max pair to the top of the tab via
    /// `InfinityUpgradesIPMultTopRow`; the bottom row then renders only the
    /// IP Offline upgrade. iPad keeps the original side-by-side layout.
    var hideIPMult: Bool = false

    var body: some View {
        let inf = engine.gameState.infinity
        if inf.ipMultUnlocked {
            // The IPMult card is `Pelle.uselessInfinityUpgrades.ipMult` —
            // bought-but-nullified during Doom. Apply the same "red bg +
            // strikethrough" treatment as the grid's `ipGen` card.
            let doomed = engine.pelleDoomed
            HStack(alignment: .top, spacing: 8) {
                if !hideIPMult {
                    VStack(spacing: 6) {
                        IPMultiplyButton(engine: engine, ipMult: inf.ipMult, doomed: doomed).equatable()
                        IPMultBuyMaxButton(engine: engine, ipMult: inf.ipMult, doomed: doomed).equatable()
                        if inf.ipMult.autobuyerUnlocked {
                            IPMultAutobuyerToggleRow(engine: engine, autobuyerActive: inf.ipMult.autobuyerActive, doomed: doomed).equatable()
                        }
                    }
                }

                // IP Offline upgrade — styled like InfinityUpgradeButton
                if let offline = inf.ipOfflineUpgrade {
                    InfinityUpgradeButton(upgrade: offline, column: 0, isPelleDoomed: engine.pelleDoomed) {
                        engine.buyInfinityUpgrade("ipOffline")
                    }
                    .equatable()
                }
            }
        }
    }
}

// MARK: - iPhone-only top row: Multiply IP by 2 above Buy Max, full width

private struct InfinityUpgradesIPMultTopRow: View {
    let engine: GameEngine

    var body: some View {
        let inf = engine.gameState.infinity
        let doomed = engine.pelleDoomed
        VStack(spacing: 6) {
            IPMultiplyButton(engine: engine, ipMult: inf.ipMult, doomed: doomed).equatable()
            IPMultBuyMaxButton(engine: engine, ipMult: inf.ipMult, doomed: doomed).equatable()
            if inf.ipMult.autobuyerUnlocked {
                IPMultAutobuyerToggleRow(engine: engine, autobuyerActive: inf.ipMult.autobuyerActive, doomed: doomed).equatable()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared IP Multiplier buttons (used by top row on iPhone, bottom row on iPad)

private struct IPMultiplyButton: View, Equatable {
    let engine: GameEngine
    let ipMult: IPMultState
    let doomed: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ipMult == rhs.ipMult && lhs.doomed == rhs.doomed
    }

    var body: some View {
        Button {
            engine.buyIPMult()
        } label: {
            VStack(spacing: 3) {
                Text("Multiply IP by 2")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .strikethrough(doomed)
                if ipMult.isCapped {
                    Text("CAPPED")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text("Cost: \(ipMult.cost) IP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("Currently: \(ipMult.multiplier)")
                    .font(.caption2.weight(.semibold))
                    .strikethrough(doomed)
            }
            .foregroundStyle(ipMultTextColor(ipMult: ipMult, doomed: doomed))
            .frame(maxWidth: .infinity, minHeight: 70)
            .padding(6)
            .background(ipMultBackground(ipMult: ipMult, doomed: doomed), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(ipMultBorder(ipMult: ipMult, doomed: doomed), lineWidth: doomed ? 2 : 1.5)
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!doomed && ipMult.canBeBought)
    }
}

private struct IPMultBuyMaxButton: View, Equatable {
    let engine: GameEngine
    let ipMult: IPMultState
    let doomed: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ipMult == rhs.ipMult && lhs.doomed == rhs.doomed
    }

    var body: some View {
        Button {
            engine.buyMaxIPMult()
        } label: {
            Text("Buy Max")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ipMultTextColor(ipMult: ipMult, doomed: doomed))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(ipMultBackground(ipMult: ipMult, doomed: doomed), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(ipMultBorder(ipMult: ipMult, doomed: doomed), lineWidth: doomed ? 2 : 1.5)
                )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!doomed && ipMult.canBeBought)
    }
}

// "Autobuy IP mult" inline toggle. Mirrors web `IpMultiplierButton.vue`'s
// third spoon (`PrimaryToggleButton`), gated on `Autobuyer.ipMult.isUnlocked`.
// The web toggle uses a bound `data().isAutobuyerActive` that writes back
// to `Autobuyer.ipMult.isActive` in a watcher; iOS uses a custom Binding
// that calls `engine.toggleIPMultAutobuyer()` on set so we never write an
// "already-equal" toggle that would no-op the JS side.
private struct IPMultAutobuyerToggleRow: View, Equatable {
    let engine: GameEngine
    let autobuyerActive: Bool
    let doomed: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.autobuyerActive == rhs.autobuyerActive && lhs.doomed == rhs.doomed
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { autobuyerActive },
            set: { newValue in
                if newValue != autobuyerActive {
                    engine.toggleIPMultAutobuyer()
                }
            }
        )) {
            Text("Autobuy IP mult")
                .font(.caption2.weight(.semibold))
                .strikethrough(doomed)
        }
        .toggleStyle(.switch)
        .tint(GameColor.multiplierCyan)
        .controlSize(.mini)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(GameColor.multiplierCyan.opacity(doomed ? 0.4 : 0.7), lineWidth: 1)
        )
        .allowsHitTesting(!doomed)
    }
}

private func ipMultTextColor(ipMult: IPMultState, doomed: Bool) -> Color {
    if doomed { return GameColor.pelle.readableOnDark() }
    if ipMult.isCapped { return .black }
    if ipMult.canBeBought { return GameColor.multiplierRed }
    return .white
}

private func ipMultBackground(ipMult: IPMultState, doomed: Bool) -> Color {
    if doomed { return GameColor.lockedBgRed }
    if ipMult.isCapped { return GameColor.infinity }
    if ipMult.canBeBought { return Color(white: 0.12) }
    // Unavailable: #525252 (web .o-infinity-upgrade-btn--unavailable)
    return Color(white: 0.322)
}

private func ipMultBorder(ipMult: IPMultState, doomed: Bool) -> Color {
    if doomed { return GameColor.pelle }
    if ipMult.isCapped { return GameColor.infinity.opacity(0.8) }
    if ipMult.canBeBought { return GameColor.multiplierCyan }
    // Unavailable: --color-accent #df5050 (web Modern UI red)
    return Color(red: 0.875, green: 0.314, blue: 0.314)
}

// MARK: - Soft / hard cap disclosure (web `InfinityUpgradesTab.vue:173-178`)
//
// Mirrors the web caption that appears below the bottom row when both
// `eternityUnlocked && bottomRowUnlocked`. Surfaced as a collapsible
// `DisclosureGroup` (matching `InfinityDimensionsInfoSection`) so the
// long verbatim text stays out of the way until the user wants it.
private struct InfinityUpgradesCapDisclosure: View {
    let engine: GameEngine

    var body: some View {
        let inf = engine.gameState.infinity
        InfinityUpgradesCapDisclosureInner(
            visible: engine.eternityUnlocked && inf.ipMultUnlocked,
            softCap: inf.ipMult.softCap,
            hardCap: inf.ipMult.hardCap
        ).equatable()
    }
}

/// All three inputs are stable: `visible` is a once-only transition,
/// `softCap` / `hardCap` are constants from `GameDatabase`. Body skips
/// every tick.
private struct InfinityUpgradesCapDisclosureInner: View, Equatable {
    let visible: Bool
    let softCap: String
    let hardCap: String

    @AppStorage("infinityUpgradesCapInfoExpanded") private var infoExpanded = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.visible == rhs.visible && lhs.softCap == rhs.softCap && lhs.hardCap == rhs.hardCap
    }

    var body: some View {
        if visible {
            DisclosureGroup(isExpanded: $infoExpanded) {
                Text("The Infinity Point multiplier becomes more expensive above \(softCap) Infinity Points, and cannot be purchased past \(hardCap) Infinity Points.")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            } label: {
                Text("IP multiplier soft/hard cap details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tint(.secondary)
        }
    }
}

// MARK: - Per-column gradient background (web parity)
//
// Mirrors `InfinityUpgradesTab.vue:setStyleOfColumnBg`/`getColumnColor`:
// each of the 4 cells in the column contributes a vertical band whose
// color reflects its state (charged → teresa, bought → infinity gold,
// otherwise transparent). Web stops: 0–15%, 35–40%, 60–65%, 85–100%
// with linear fades between bands.
//
// Web opacity: 0.7 base, 0.5 in dark mode (`s-base--dark`). iOS is
// always-dark, so 0.5.
private struct InfinityUpgradesColumnBackground: View, Equatable {
    let cells: [InfinityUpgradeInfo]

    /// Only `isCharged` / `isBought` per cell affect the visual gradient.
    /// Skip the rest of `InfinityUpgradeInfo` (cost, description, etc.) so
    /// unrelated upgrade-info changes don't invalidate the background.
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.cells.count == rhs.cells.count else { return false }
        for (l, r) in zip(lhs.cells, rhs.cells) {
            if l.isCharged != r.isCharged || l.isBought != r.isBought {
                return false
            }
        }
        return true
    }

    private static func bandColor(for cell: InfinityUpgradeInfo?) -> Color {
        guard let cell else { return .clear }
        if cell.isCharged { return GameColor.teresa }
        if cell.isBought { return GameColor.infinity }
        return .clear
    }

    var body: some View {
        let c1 = Self.bandColor(for: cells.indices.contains(0) ? cells[0] : nil)
        let c2 = Self.bandColor(for: cells.indices.contains(1) ? cells[1] : nil)
        let c3 = Self.bandColor(for: cells.indices.contains(2) ? cells[2] : nil)
        let c4 = Self.bandColor(for: cells.indices.contains(3) ? cells[3] : nil)
        RoundedRectangle(cornerRadius: 5)
            .fill(LinearGradient(
                stops: [
                    .init(color: c1, location: 0.00),
                    .init(color: c1, location: 0.15),
                    .init(color: c2, location: 0.35),
                    .init(color: c2, location: 0.40),
                    .init(color: c3, location: 0.60),
                    .init(color: c3, location: 0.65),
                    .init(color: c4, location: 0.85),
                    .init(color: c4, location: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
            ))
            .opacity(0.5)
    }
}

// MARK: - Per-column accent colors (dark theme, matching web Modern UI)

private enum InfinityColumnColor {
    /// Column 0: default (infinity gold)
    /// Column 1: red accent (#d50000)
    /// Column 2: gold/yellow accent (#ffd600)
    /// Column 3: cyan accent (#00e5ff)
    static func accent(for column: Int) -> Color {
        switch column {
        case 1:  GameColor.infUpgradeCol2
        case 2:  GameColor.infUpgradeCol3
        case 3:  GameColor.infUpgradeCol4
        default: GameColor.infinity
        }
    }
}

/// Infinity Upgrade ids whose effects are nullified by Pelle's Doomed
/// Reality. Mirrors `Pelle.uselessInfinityUpgrades` (`pelle.js:189-191`).
/// These get the strongest visual treatment (red background + strikethrough)
/// AND have their tap action blocked, matching the web's
/// `o-pelle-disabled-pointer { pointer-events: none }` CSS. The rest of the
/// upgrades fall under the broader "IPMults disabled" Pelle nerf and get a
/// red-bordered treatment but stay tappable.
///
/// IMPORTANT: iOS uses the JS object key (e.g. "ipGen") as
/// `InfinityUpgradeInfo.id`, NOT the `config.id` ("passiveGen"). The `name`
/// field carries `config.id` for display. We translate the web list into
/// matching iOS keys here:
///   - "passiveGen"          (config.id) → iOS key "ipGen"
///   - "ipMult"              (config.id) → rendered as a separate rebuyable
///     card in `bottomRow` and gated there directly — not in this Set.
///   - "infinitiedGeneration" (config.id) → iOS key "infinitiedGen"
///     (Break Infinity tab — shares `InfinityUpgradeButton`).
fileprivate let pelleUselessInfinityUpgrades: Set<String> = ["ipGen", "infinitiedGen"]

// MARK: - Individual Upgrade Button

/// Picks between fixed-height and flexible (`minHeight`-only) sizing for
/// the inner card content. Stable height is the load-bearing constraint
/// for grids that want a uniform tile size (Break Infinity); the flexible
/// path keeps the natural-size behaviour the main Infinity Upgrades grid
/// has always had.
private struct InfinityUpgradeCardSizing: ViewModifier {
    let fixedHeight: CGFloat?
    let fallbackMinHeight: CGFloat

    func body(content: Content) -> some View {
        if let h = fixedHeight {
            content.frame(maxWidth: .infinity, minHeight: h, maxHeight: h)
        } else {
            content.frame(maxWidth: .infinity, minHeight: fallbackMinHeight)
        }
    }
}

struct InfinityUpgradeButton: View, Equatable {
    let upgrade: InfinityUpgradeInfo
    let column: Int
    var accentOverride: Color? = nil
    var isMultiplierRow: Bool = false
    /// Shift-mode — show the charged-effect description on bought-but-chargeable
    /// upgrades. Mirrors web `ui.view.shiftDown`.
    var showCharged: Bool = false
    /// True when the parent says we're inside Doomed Reality. Drives the
    /// "useless" red-bg + strikethrough treatment for the explicitly listed
    /// IDs and the red-border treatment for everything else.
    var isPelleDoomed: Bool = false
    /// When non-nil, the card uses this exact pt height (rather than the
    /// default `minHeight`). Drops the description's `fixedSize` so
    /// `minimumScaleFactor(0.6)` actually engages and long copy scales to
    /// fit. Lets parents (e.g. `BreakInfinityUpgradeGrid`) lay out a
    /// uniform-size grid where all cards in a row read as the same tile.
    var fixedHeight: CGFloat? = nil
    let onBuy: () -> Void
    @Environment(\.layoutMetrics) private var metrics

    /// Closure excluded; everything else compared. `InfinityUpgradeInfo` is
    /// `Equatable` (synthesized) — its fields (cost, description, isBought,
    /// canBeBought, isCharged) only change on player action (buy / charge /
    /// new prereq met), not per tick. Big win: 16+ button instances in the
    /// grid mostly all skip body each gameState reassignment.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.upgrade == rhs.upgrade
            && lhs.column == rhs.column
            && lhs.accentOverride == rhs.accentOverride
            && lhs.isMultiplierRow == rhs.isMultiplierRow
            && lhs.showCharged == rhs.showCharged
            && lhs.isPelleDoomed == rhs.isPelleDoomed
            && lhs.fixedHeight == rhs.fixedHeight
    }

    private var isPelleUseless: Bool {
        isPelleDoomed && pelleUselessInfinityUpgrades.contains(upgrade.id)
    }

    private var columnAccent: Color { accentOverride ?? InfinityColumnColor.accent(for: column) }

    /// When should the description swap to the charged variant?
    /// Web: always when upgrade is charged (to reflect its current effect);
    /// also when shift is held on a chargeable upgrade to preview.
    private var useChargedDescription: Bool {
        upgrade.chargedEffectText != nil && (upgrade.isCharged || (showCharged && upgrade.isBought))
    }

    var body: some View {
        let isCompact = metrics.isCompact
        let useFixed = fixedHeight != nil
        return Button {
            onBuy()
        } label: {
            VStack(spacing: 3) {
                // Description: when the parent forces a fixed card height,
                // drop `fixedSize(vertical:)` so `minimumScaleFactor(0.6)`
                // engages and long copy scales to fit instead of pushing
                // the cell taller than its siblings.
                let descText = Text(useChargedDescription ? (upgrade.chargedEffectText ?? upgrade.description) : upgrade.description)
                    .font(isCompact ? .footnote : .caption2)
                Group {
                    if useFixed {
                        descText
                            .multilineTextAlignment(.center)
                            .lineLimit(isCompact ? 6 : 4)
                            .minimumScaleFactor(0.6)
                            .strikethrough(isPelleUseless)
                    } else {
                        descText
                            .multilineTextAlignment(.center)
                            .lineLimit(isCompact ? 6 : 4)
                            .minimumScaleFactor(0.6)
                            .fixedSize(horizontal: false, vertical: true)
                            .strikethrough(isPelleUseless)
                    }
                }

                if let effect = upgrade.effectText, (upgrade.isBought || upgrade.isRebuyable), !useChargedDescription {
                    Text(effect)
                        .font(isCompact ? .footnote.weight(.semibold) : .caption2.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .strikethrough(isPelleUseless)
                }
                if !upgrade.isBought {
                    Text("Cost: \(upgrade.cost) IP")
                        .font(isCompact ? .footnote : .caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                if upgrade.isCharged {
                    Text("Charged")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.yellow)
                }
            }
            .foregroundStyle(textColor)
            .modifier(InfinityUpgradeCardSizing(fixedHeight: fixedHeight, fallbackMinHeight: isCompact ? 90 : 70))
            .padding(isCompact ? 8 : 6)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: pelleBorderWidth)
            )
        }
        // Pelle-useless upgrades stay un-tappable even when affordable —
        // matches web's `pointer-events: none` on `.o-pelle-disabled-pointer`.
        .allowsHitTesting((upgrade.canBeBought || upgrade.isBought) && !isPelleUseless)
    }

    private var pelleBorderWidth: CGFloat {
        if isPelleDoomed { return 2 }
        if upgrade.isCharged { return 2.5 }
        return isMultiplierRow && !upgrade.isBought ? 1.5 : 1
    }

    private var textColor: Color {
        if upgrade.isCharged { return .white }
        if upgrade.isBought { return .black }
        if isMultiplierRow && upgrade.canBeBought { return GameColor.multiplierRed }
        return .white
    }

    /// #1f1f1f — base/available bg (o-infinity-upgrade-btn)
    private static let baseBg = Color(white: 0.122)

    private var backgroundColor: Color {
        // Pelle "useless" — the 3 IPMult-related upgrades whose effect is
        // outright zeroed when doomed. Use Pelle red so it's distinguishable
        // from the regular bought-gold or unavailable-grey states.
        if isPelleUseless { return GameColor.lockedBgRed }
        if upgrade.isCharged { return GameColor.teresa }
        if upgrade.isBought { return GameColor.infinity }
        if upgrade.canBeBought { return Self.baseBg }
        // Unavailable: #525252 (Modern UI)
        return Color(white: 0.322)
    }

    private var borderColor: Color {
        // While doomed every upgrade gets a red border (mirrors the broader
        // "IPMults are disabled" Pelle nerf affecting all IUs).
        if isPelleDoomed { return GameColor.pelle }
        if upgrade.isCharged { return .yellow }
        if upgrade.isBought { return .black }
        if isMultiplierRow && upgrade.canBeBought { return GameColor.multiplierCyan }
        // Available and unavailable: black (base)
        return .black
    }
}
