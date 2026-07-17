//
//  TimeStudiesTab.swift
//  AntiMatter
//
//  Time Study tree — full card layout matching web Modern UI.
//  Each study shows ID, description, effect, and cost.
//  Connection lines drawn between parent→child studies.
//  V2: iPad full-card layout (V1 row layout preserved on branch time-studies-v1-row-layout).
//

import SwiftUI

// MARK: - Main Tab

struct TimeStudiesTab: View {
    let engine: GameEngine

    var body: some View {
        TimeStudiesContent(engine: engine)
    }
}

/// Wraps the full Time Studies tab. Holds @State for path / preset / import
/// sheets and reads `engine.gameState.eternity.timeStudies` internally.
/// Splitting this off keeps the parent `TimeStudiesTab` body inert across
/// per-tick state churn — the public struct re-evaluates only when the tab
/// itself is mounted/unmounted, while the Canvas-heavy tree, theorem shop,
/// preset row, and bottom bar all re-evaluate independently inside this
/// content struct.
private struct TimeStudiesContent: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.sidebarState) private var sidebarState
    @State private var showPathPreferences = false
    @State private var editingPreset: StudyPresetInfo?
    @State private var showImportSheet = false

    private var state: TimeStudiesState { engine.gameState.eternity.timeStudies }

    /// True when at least one triad study (301-304) is unlocked (any Hard
    /// V-Achievement tier completed). When false, the triad row is stripped
    /// from the tree so it doesn't reserve vertical space.
    private var showTriads: Bool {
        state.studies.contains { StudyTreeLayout.triadIDs.contains($0.id) }
    }
    private var dilationBought: Bool {
        state.studies.first { $0.id == -100 }?.isBought ?? false
    }
    private var treeLayout: StudyTreeLayout {
        metrics.isCompact
            ? .compact(showTriads: showTriads, dilationBought: dilationBought)
            : .shared(showTriads: showTriads, dilationBought: dilationBought)
    }

    var body: some View {
        VStack(spacing: 0) {
            TimeStudiesBottomBar(
                isCompact: metrics.isCompact,
                hasBoughtStudies: state.studies.contains(where: { $0.isBought }),
                respecOnNextEternity: state.respecOnNextEternity,
                engine: engine,
                showPathPreferences: $showPathPreferences,
                showImportSheet: $showImportSheet
            )
            .equatable()
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .sheet(isPresented: $showPathPreferences) {
                PathPreferencesSheet(engine: engine)
            }
            .sheet(isPresented: $showImportSheet) {
                ImportStudiesSheet(engine: engine)
            }

            TimeStudiesTheoremShop(
                isCompact: metrics.isCompact,
                shop: state.shop,
                engine: engine
            )
            .equatable()
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            TimeStudiesPresetRow(
                isCompact: metrics.isCompact,
                presets: state.presets,
                engine: engine,
                editingPreset: $editingPreset
            )
            .equatable()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .sheet(item: $editingPreset) { preset in
                EditPresetSheet(engine: engine, preset: preset)
            }

            Divider().opacity(0.3)

            ZoomableScrollView(
                minZoom: 0.25,
                maxZoom: 2.0,
                bottomInset: 80,
                doubleTapResetZoom: 1.0,
                zoomScale: Binding(
                    get: { engine.timeStudyZoom },
                    set: { engine.timeStudyZoom = $0 }
                ),
                contentOffset: Binding(
                    get: { engine.timeStudyOffset },
                    set: { engine.timeStudyOffset = $0 }
                )
            ) {
                // Hoist the equatable inputs out of the closure so the
                // diff is checked at parent-body time, before the closure
                // body builds 70+ StudyCard views.
                TimeStudyTreeView(
                    studies: state.studies,
                    showTriads: showTriads,
                    isCompact: metrics.isCompact,
                    zoomLevel: metrics.isCompact ? engine.timeStudyZoom : 1.0,
                    pelleDoomed: engine.pelleDoomed,
                    pelleUselessIds: engine.pelleUselessTimeStudies,
                    enslavedIsRunning: engine.enslavedIsRunning,
                    enslavedHasSecretStudy: engine.enslavedHasSecretStudy,
                    secretTSVisible: engine.secretTSVisible,
                    onBuy: { id in buyStudy(id) },
                    onStartEC: { sidebarState?.selectSubtab(.eternityChallenges, in: .challenges, engine: engine) },
                    onLongPress: { id in engine.purchaseStudiesUntil(id) },
                    onClaimEnslavedSecret: { engine.claimEnslavedSecretStudy() },
                    onRevealSecretTS: { engine.revealSecretTimeStudy() },
                    onHideSecretTS: { engine.hideSecretTimeStudy() }
                )
                .equatable()
                .padding(20)
            }
            .ignoresSafeArea(edges: .bottom)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func buyStudy(_ id: Int) {
        if id > 0 {
            engine.buyTimeStudy(id)
        } else if id >= -12 && id < 0 {
            engine.buyECStudy(-id)
        } else if id == -100 {
            engine.buyDilationStudy()
        } else if id <= -105 && id >= -108 {
            engine.buyTDStudy(-id - 100)
        } else if id == -200 {
            engine.buyRealityStudy()
        }
    }

    /// Whether to render the Reality study node (ID -200).
    private static func showRealityStudy(isCompact: Bool) -> Bool {
        return true
    }

    // Theorem shop, preset row, and bottom bar are all extracted into
    // Equatable structs below so the parent body's per-tick re-evaluation
    // doesn't rebuild their internal modifier chains.
}

// MARK: - Time Theorem Shop (Equatable)

/// Equatable on the full `TimeTheoremShopState` (Equatable struct). Body
/// rebuilds only when something in the shop actually changes (TT count
/// updates, costs scale, canBuy flips). Closures capture stable engine
/// reference.
private struct TimeStudiesTheoremShop: View, Equatable {
    let isCompact: Bool
    let shop: TimeTheoremShopState
    let engine: GameEngine

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isCompact == rhs.isCompact && lhs.shop == rhs.shop
    }

    var body: some View {
        VStack(spacing: isCompact ? 4 : 8) {
            Text("You have \(Text(shop.theorems).foregroundStyle(GameColor.eternity)) Time Theorems. (Total: \(Text(shop.totalTheorems).foregroundStyle(GameColor.eternity)))")
                .foregroundStyle(.secondary)
                .font((isCompact ? Font.caption : Font.subheadline).monospacedDigit())

            // Space Theorem counter — shown only after V has been unlocked
            // (totalSpaceTheorems > 0). ST lets you buy mutually-exclusive
            // Time Studies, so surfacing available ST on the tree tab matters.
            if shop.totalSpaceTheorems > 0 {
                Text("You have \(Text("\(shop.availableSpaceTheorems)").foregroundStyle(GameColor.v)) available Space Theorems. (Total earned: \(Text("\(shop.totalSpaceTheorems)").foregroundStyle(GameColor.v)))")
                    .foregroundStyle(.secondary)
                    .font((isCompact ? Font.caption : Font.subheadline).monospacedDigit())
            }

            HStack(alignment: .top, spacing: isCompact ? 4 : 8) {
                theoremBuyButton(label: "AM", cost: shop.amCost, canBuy: shop.canBuyAM) {
                    engine.buyTimeTheorem("am")
                }
                theoremBuyButton(label: "IP", cost: shop.ipCost, canBuy: shop.canBuyIP) {
                    engine.buyTimeTheorem("ip")
                }
                theoremBuyButton(label: "EP", cost: shop.epCost, canBuy: shop.canBuyEP) {
                    engine.buyTimeTheorem("ep")
                }
                theoremBuyButton(label: "Buy Max", cost: nil, canBuy: true) {
                    engine.buyMaxTimeTheorems()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func theoremBuyButton(label: String, cost: String?, canBuy: Bool, action: @escaping () -> Void) -> some View {
        GameButton(theme: .timeTheorem, isEnabled: canBuy) {
            action()
        } label: {
            VStack(spacing: 1) {
                Text(label).font((isCompact ? Font.caption2 : Font.caption).weight(.bold))
                if let cost {
                    Text(cost)
                        .font(.caption2.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, isCompact ? 2 : 6)
            .padding(.vertical, isCompact ? 2 : 4)
            .frame(maxHeight: .infinity) // vertically center content within the button
        }
        .frame(maxWidth: .infinity, minHeight: isCompact ? 34 : 40)
    }
}

// MARK: - Study Presets (Equatable)

/// Equatable on `(isCompact, presets)`. The `presets` array only changes
/// on save/load/delete, so the 6-Menu row is preserved across ticks. The
/// `editingPreset` binding is held by the parent — the `.sheet(item:)`
/// modifier lives outside this struct so the binding doesn't disturb the
/// equality check.
private struct TimeStudiesPresetRow: View, Equatable {
    let isCompact: Bool
    let presets: [StudyPresetInfo]
    let engine: GameEngine
    @Binding var editingPreset: StudyPresetInfo?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isCompact == rhs.isCompact && lhs.presets == rhs.presets
    }

    var body: some View {
        HStack(spacing: isCompact ? 3 : 6) {
            ForEach(presets) { preset in
                let displayName = preset.name.isEmpty ? "\(preset.id + 1)" : preset.name
                let hasStudies = !preset.studies.isEmpty

                Menu {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        engine.saveStudyPreset(preset.id)
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        engine.loadStudyPreset(preset.id)
                    } label: {
                        Label("Load", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!hasStudies)
                    Button { editingPreset = preset } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        let str = engine.exportStudyPreset(preset.id)
                        if !str.isEmpty {
                            UIPasteboard.general.string = str
                            engine.enqueueToast(type: "eternity", text: "Preset \(displayName) exported to clipboard")
                        }
                    } label: {
                        Label("Export", systemImage: "doc.on.clipboard")
                    }
                    .disabled(!hasStudies)
                    Divider()
                    Button(role: .destructive) {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        engine.deleteStudyPreset(preset.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(!hasStudies)
                } label: {
                    Text(displayName)
                        .font(.system(size: isCompact ? 11 : 13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(hasStudies ? GameColor.eternity : GameColor.eternity.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: isCompact ? 28 : 32)
                        .background(Color(red: 0.086, green: 0.086, blue: 0.086)) // #161616
                        .roundedBorder(hasStudies ? GameColor.eternity : GameColor.eternity.opacity(0.4), lineWidth: 1.5)
                } primaryAction: {
                    if hasStudies {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        engine.loadStudyPreset(preset.id)
                    }
                }
            }
        }
    }
}

// MARK: - Bottom bar (Equatable)

/// Equatable on `(isCompact, hasBoughtStudies, respecOnNextEternity)` —
/// `hasBoughtStudies` is the precomputed contains-check the export action
/// reads, and `respecOnNextEternity` toggles only on tap. Sheet-presenting
/// flags (`showPathPreferences`, `showImportSheet`) are bindings held by
/// the parent so the sheet modifiers don't impede skipping.
private struct TimeStudiesBottomBar: View, Equatable {
    let isCompact: Bool
    let hasBoughtStudies: Bool
    let respecOnNextEternity: Bool
    let engine: GameEngine
    @Binding var showPathPreferences: Bool
    @Binding var showImportSheet: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isCompact == rhs.isCompact
            && lhs.hasBoughtStudies == rhs.hasBoughtStudies
            && lhs.respecOnNextEternity == rhs.respecOnNextEternity
    }

    var body: some View {
        let fontSize: Font = isCompact ? .caption2 : .caption
        HStack(spacing: isCompact ? 6 : 12) {
            Button {
                if hasBoughtStudies {
                    let str = engine.exportStudies()
                    UIPasteboard.general.string = str
                    engine.enqueueToast(type: "info", text: "Study tree exported to clipboard")
                } else {
                    engine.enqueueToast(type: "error", text: "You have no Time Studies to export")
                }
            } label: {
                Label("Export", systemImage: "doc.on.clipboard")
                    .font(fontSize)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)

            Button { showImportSheet = true } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .font(fontSize)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)

            Button {
                engine.respecTimeStudies()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: respecOnNextEternity ? "checkmark.square.fill" : "square")
                        .foregroundStyle(respecOnNextEternity ? GameColor.eternity : .white.opacity(0.5))
                    Text(isCompact ? "Respec on\nnext Eternity" : "Respec on next Eternity")
                        .font(fontSize)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                showPathPreferences = true
            } label: {
                Label(isCompact ? "Paths" : "Path Preferences", systemImage: "arrow.triangle.branch")
                    .font(fontSize)
                    .foregroundStyle(GameColor.eternity)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Tree View (Equatable — skips re-render when study state unchanged)

/// Wraps the connection-line `Canvas` + 70+ `StudyCard` views in an
/// equatable subview so the parent `TimeStudiesContent` body — which
/// re-evaluates at 30Hz because `engine.gameState` is reassigned every
/// tick — doesn't rebuild the entire tree on every theorem-shop tick.
///
/// Only re-runs when the listed inputs actually change: study list (a
/// purchase / unlock flips an entry), zoom (user pinch), Pelle state,
/// Enslaved-run state. Closures capture a stable `engine` reference so
/// they're excluded from `==`.
private struct TimeStudyTreeView: View, Equatable {
    let studies: [TimeStudyInfo]
    let showTriads: Bool
    let isCompact: Bool
    let zoomLevel: CGFloat
    let pelleDoomed: Bool
    let pelleUselessIds: Set<Int>
    let enslavedIsRunning: Bool
    let enslavedHasSecretStudy: Bool
    let secretTSVisible: Bool
    let onBuy: (Int) -> Void
    let onStartEC: () -> Void
    let onLongPress: (Int) -> Void
    let onClaimEnslavedSecret: () -> Void
    let onRevealSecretTS: () -> Void
    let onHideSecretTS: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.studies == rhs.studies
            && lhs.showTriads == rhs.showTriads
            && lhs.isCompact == rhs.isCompact
            && lhs.zoomLevel == rhs.zoomLevel
            && lhs.pelleDoomed == rhs.pelleDoomed
            && lhs.pelleUselessIds == rhs.pelleUselessIds
            && lhs.enslavedIsRunning == rhs.enslavedIsRunning
            && lhs.enslavedHasSecretStudy == rhs.enslavedHasSecretStudy
            && lhs.secretTSVisible == rhs.secretTSVisible
    }

    private var dilationBought: Bool {
        studies.first { $0.id == -100 }?.isBought ?? false
    }
    private var treeLayout: StudyTreeLayout {
        isCompact
            ? .compact(showTriads: showTriads, dilationBought: dilationBought)
            : .shared(showTriads: showTriads, dilationBought: dilationBought)
    }

    var body: some View {
        let layout = treeLayout
        let studyMap = Dictionary(uniqueKeysWithValues: studies.map { ($0.id, $0) })
        let cw = layout.cardWidth
        let slotH = layout.cardHeightEstimate
        let totalW = layout.totalWidth
        let totalH = layout.totalHeight

        return ZStack(alignment: .topLeading) {
            // Connection lines (drawn first, behind cards)
            Canvas { ctx, _ in
                for conn in StudyTreeLayout.connections {
                    guard let fromPos = layout.positions[conn.from],
                          let toPos = layout.positions[conn.to] else { continue }
                    // Per-card width — the 22x "wide row" renders narrower
                    // than the rest of the tree, so mirror web's wideRow/
                    // normalRow split when computing the horizontal center.
                    let fromCw = layout.cardWidth(for: conn.from)
                    let toCw = layout.cardWidth(for: conn.to)
                    // Anchor the line endpoints at the GEOMETRIC CENTER of
                    // each card (both axes). The cards render after this
                    // Canvas in the parent ZStack with opaque backgrounds,
                    // so the segment of the line that lies inside a card is
                    // covered up — the visible portion naturally emerges
                    // from whichever edge the line happens to be travelling
                    // through. Earlier the start point was the bottom edge,
                    // which forced the bezier to start bending sideways
                    // immediately and looked wonky on the wide fan-out from
                    // a 4-cell row down to an 8-cell row (e.g. 211 → 221/222).
                    let fromPt = CGPoint(
                        x: fromPos.x + fromCw / 2,
                        y: fromPos.y + slotH / 2
                    )
                    let toPt = CGPoint(
                        x: toPos.x + toCw / 2,
                        y: toPos.y + slotH / 2
                    )
                    let isSatisfied = studyMap[conn.from]?.isBought ?? false
                    let lineColor = isSatisfied ? Color.gray.opacity(0.6) : Color.gray.opacity(0.2)

                    var path = Path()
                    path.move(to: fromPt)
                    let midY = (fromPt.y + toPt.y) / 2
                    path.addCurve(
                        to: toPt,
                        control1: CGPoint(x: fromPt.x, y: midY),
                        control2: CGPoint(x: toPt.x, y: midY)
                    )
                    ctx.stroke(path, with: .color(lineColor), style: StrokeStyle(
                        lineWidth: isSatisfied ? (isCompact ? 6 : 12) : (isCompact ? 4 : 8),
                        lineCap: .round
                    ))
                }
            }
            .frame(width: totalW, height: totalH)

            // Study cards
            ForEach(studies) { study in
                if let pos = layout.positions[study.id] {
                    let useless = pelleDoomed && pelleUselessIds.contains(study.id)
                    let lockedByDoom = pelleDoomed && study.id == -200 && !study.isBought
                    // Wide-row cards (221-228) render at a narrower width
                    // than the rest of the tree to match web's `wideRow`
                    // layout — so 8 cells fit roughly the same canvas span
                    // as the 4-cell rows above and below, keeping
                    // connection lines visually aligned. The width is
                    // pushed INTO the card via `widthOverride` (rather than
                    // just clamped from outside) because StudyCard has its
                    // own internal `.frame(width:)` on the standard size,
                    // and the inner frame wins — without the override the
                    // wide cells would render at full width and overflow
                    // into their neighbors.
                    let cardW = layout.cardWidth(for: study.id)
                    let isWide = StudyTreeLayout.wideRowIDs.contains(study.id)
                    StudyCard(study: study, isCompact: isCompact,
                             zoomLevel: zoomLevel,
                             isUselessInDoomed: useless,
                             isLockedByDoom: lockedByDoom,
                             widthOverride: isWide ? cardW : nil,
                             onBuy: { onBuy(study.id) },
                             onStartEC: study.type == .ec ? onStartEC : nil,
                             onLongPress: { onLongPress(study.id) })
                        .equatable()
                        .frame(width: cardW)
                        .offset(x: pos.x, y: pos.y)
                }
            }

            // Enslaved secret study — phantom card to the right of TS 11,
            // only rendered while inside the Nameless Ones' Reality.
            if enslavedIsRunning, let ts11 = layout.positions[11] {
                EnslavedSecretStudyCard(
                    hasClaimed: enslavedHasSecretStudy,
                    isCompact: isCompact,
                    cardWidth: cw,
                    cardHeight: slotH,
                    onTap: onClaimEnslavedSecret
                )
                .equatable()
                .frame(width: cw)
                .offset(x: ts11.x + cw + layout.hSpacing, y: ts11.y)
            }

            // SecretAchievement(21) secret time study — phantom card to the
            // LEFT of TS 11. Always rendered (invisible-but-tappable when
            // hidden), mirroring web `SecretTimeStudy.vue`. Pushed out an
            // extra card-width past the normal `hSpacing` gap so the
            // easter egg doesn't visually crowd TS 11 (it's an outlier in
            // the tree — not connected to anything — so the extra breathing
            // room signals "off-tree" more than "adjacent study").
            if let ts11 = layout.positions[11] {
                let secretGap = layout.hSpacing + cw
                SecretTimeStudyCard(
                    isVisible: secretTSVisible,
                    isCompact: isCompact,
                    cardWidth: cw,
                    cardHeight: slotH,
                    onReveal: onRevealSecretTS,
                    onHide: onHideSecretTS
                )
                .frame(width: cw)
                .offset(x: ts11.x - cw - secretGap, y: ts11.y)
            }
        }
        .frame(width: totalW, height: totalH)
    }
}

// MARK: - Study Colors (from time-studies.css, dark theme)

/// Encapsulates bought/available/unavailable colors per study path type.
/// All hex values sourced from time-studies.css (t-dark overrides where applicable).
private struct StudyColors {
    // Available state (prerequisites met + affordable, not bought)
    let availableBg: Color
    let availableText: Color
    let availableBorder: Color
    // Bought state
    let boughtBg: Color
    let boughtText: Color
    let boughtBorder: Color

    static let unavailableBg = GameColor.unavailableBg
    static let unavailableText = GameColor.unavailableText

    private static let eternityPurple = GameColor.eternity

    /// Standard: colored text/border on black bg when available, colored bg with black text when bought
    private static func standard(_ c: Color) -> StudyColors {
        StudyColors(availableBg: .black, availableText: c, availableBorder: c,
                    boughtBg: c, boughtText: .black, boughtBorder: c.opacity(0.7))
    }

    static func `for`(_ type: TimeStudyInfo.StudyType) -> StudyColors {
        switch type {
        case .antimatter: return standard(Color(red: 0.133, green: 0.667, blue: 0.282))  // #22aa48
        case .infinity:   return standard(Color(red: 0.714, green: 0.498, blue: 0.200))  // #b67f33
        case .time:       return standard(eternityPurple)
        case .active:     return standard(Color(red: 0.902, green: 0.000, blue: 0.000))  // #e60000
        case .passive:    return standard(Color(red: 0.369, green: 0.200, blue: 0.714))  // #5e33b6
        case .idle:       return standard(Color(red: 0.000, green: 0.502, blue: 1.000))  // #0080ff
        case .dilation:   return standard(Color(red: 0.25, green: 0.75, blue: 0.25))
        case .light:
            // CSS: light--available { color: white; bg: black; border: white }
            //      light--bought   { color: black; bg: white; border: black; double }
            return StudyColors(availableBg: .black, availableText: .white, availableBorder: .white,
                               boughtBg: .white, boughtText: .black, boughtBorder: .black)
        case .dark:
            // CSS: dark--available { color: black; bg: white; border: black }
            //      dark--bought   { color: white; bg: black; border: white; double }
            return StudyColors(availableBg: .white, availableText: .black, availableBorder: .black,
                               boughtBg: .black, boughtText: .white, boughtBorder: .white)
        case .reality:
            // CSS: reality--available { color: #0ba00e; bg: white; border: #0ba00e }
            //      reality--bought   { color: black; bg: #0ba00e; border: black }
            return StudyColors(availableBg: .white, availableText: GameColor.reality, availableBorder: GameColor.reality,
                               boughtBg: GameColor.reality, boughtText: .black, boughtBorder: .black)
        case .triad:
            // Triad Studies — V yellow (`--color-v--base: #ead584`). Web
            // CSS: `triad--available { color: var(--color-v--base); bg: black;
            // border: black }` + 1.5s pulse animation; `triad--bought
            // { color: black; bg: var(--color-v--base); border: black }`. iOS
            // doesn't run the pulse, so we route through `standard(...)` which
            // borders the available card in the accent (yellow) for legibility
            // — same shape as every other study type's iOS port.
            return standard(GameColor.v)
        default:
            return standard(eternityPurple)
        }
    }
}

// MARK: - Study Card (full web-style card)

// Time-study IDs nullified by Pelle's Doomed Reality are now sourced from
// `engine.pelleUselessTimeStudies` — populated once at startup from
// `Pelle.uselessTimeStudies` (`pelle.js:193`) via `_nativePelleDisabledLists()`.

/// Isolated multiline description Text. Wrapping + `minimumScaleFactor`
/// re-measurement is the heaviest per-card layout cost; making this an
/// `Equatable` leaf lets SwiftUI skip its body when the description text
/// itself hasn't changed (which is almost always — descriptions only flip
/// on rare events like achievement unlocks). The volatile `effectText`
/// sibling re-renders normally without forcing the description to re-flow.
///
/// Card row pitch on iPhone is fixed (`cardHeightEstimate=60 + vSpacing=24`);
/// letting a card grow past that box visually overlaps the next row. Triads
/// sit on the bottom row and can safely grow to 5 lines; everything else
/// stays at 3 lines and relies on `minimumScaleFactor` to squeeze long
/// descriptions (e.g. TS133's locked "Replicanti are ×10 slower until
/// 1.80e308, but..." form) into the box.
private struct StudyDescriptionText: View, Equatable {
    let text: String
    let isCompact: Bool
    let isTriad: Bool
    let color: Color
    let bodySize: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: bodySize))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineLimit(isCompact ? (isTriad ? 6 : 4) : nil)
            .minimumScaleFactor(isCompact ? 0.55 : 1)
            .fixedSize(horizontal: false, vertical: !isCompact)
    }
}

private struct StudyCard: View, Equatable {
    let study: TimeStudyInfo
    var isCompact: Bool = false
    var zoomLevel: CGFloat = 1.0
    /// True when `engine.pelleDoomed` AND this study's id is in
    /// `pelleUselessTimeStudies` AND it was already bought. Web `TimeStudyButton.vue`
    /// applies a strikethrough + grey treatment to flag that the bought study
    /// no longer provides its effect under doom.
    var isUselessInDoomed: Bool = false
    /// True when `engine.pelleDoomed` AND this is the Reality study (id -200).
    /// Web disables the buy button on the Reality study for doomed players.
    var isLockedByDoom: Bool = false
    /// Optional per-card width override. When non-nil, the card renders
    /// at this width instead of the constant `StudyTreeLayout.{compact,shared}
    /// CardWidth`. Used by the wide row (221-228) so cards fit the narrower
    /// slot computed by `StudyTreeLayout.cardWidth(for:)` instead of
    /// overflowing into their neighbors.
    var widthOverride: CGFloat? = nil
    let onBuy: () -> Void
    var onStartEC: (() -> Void)?
    var onLongPress: (() -> Void)?

    /// Closures excluded from `==` — they capture a stable engine reference
    /// and have no observable behavior change between ticks. Cards whose
    /// `study` (incl. `effectText`) is unchanged skip body re-execution.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.study == rhs.study
            && lhs.isCompact == rhs.isCompact
            && lhs.zoomLevel == rhs.zoomLevel
            && lhs.isUselessInDoomed == rhs.isUselessInDoomed
            && lhs.isLockedByDoom == rhs.isLockedByDoom
            && lhs.widthOverride == rhs.widthOverride
    }

    /// When zoomed out on iPhone, show only the label number
    private var isMinimal: Bool { isCompact && zoomLevel < 0.8 }

    /// Available = prerequisites met AND can afford (matches web's isAvailableForPurchase)
    private var isAvailable: Bool {
        study.canBeBought && study.isAffordable
    }

    private var colors: StudyColors { StudyColors.for(study.type) }

    private var borderColor: Color {
        // Pelle-useless studies use the same crimson border family regardless of
        // bought/available state (web `.c-pelle-useless` uses a single border).
        if isUselessInDoomed { return GameColor.pelle.opacity(0.9) }
        if study.isBought { return colors.boughtBorder }
        if isAvailable { return colors.availableBorder }
        return StudyColors.unavailableBg.opacity(0.7)
    }

    private var textColor: Color {
        // White on crimson reads well; grays out slightly on the unavailable
        // variant to mirror web's `filter: grayscale(90%)`.
        if isUselessInDoomed {
            if !study.isBought && !isAvailable { return Color(white: 0.15) }
            return .white
        }
        if study.isBought { return colors.boughtText }
        if isAvailable { return colors.availableText }
        return StudyColors.unavailableText
    }

    private var cardBg: Color {
        // Web `.c-pelle-useless` paints the entire card crimson regardless of
        // bought/available; the bought + unavailable variants only differ via
        // CSS grayscale filter, which we collapse to the same red here.
        if isUselessInDoomed { return GameColor.lockedBgRed }
        if study.isBought { return colors.boughtBg }
        if isAvailable { return colors.availableBg }
        return StudyColors.unavailableBg
    }

    private var isEC: Bool { study.id >= -12 && study.id < 0 }

    private var displayLabel: String {
        let id = study.id
        if id > 0 {
            switch study.type {
            case .light: return "\(id) Light"
            case .dark:  return "\(id) Dark"
            case .triad: return "\(id) Triad"
            default:     return "\(id)"
            }
        }
        if isEC { return "EC\(-id)" }
        if id == -100 { return "Dilation" }
        if id <= -105 && id >= -108 { return "TD\(-id - 100)" }
        if id == -200 { return "Reality" }
        return "?"
    }

    /// Double-border overlay for light/dark studies when they're bought —
    /// the contrast-reversed fill alone is easy to miss at small zoom, so we
    /// add a second thin inset stroke in the same color as the outer border
    /// to make the selected state unambiguous. Matches web's `.double` CSS.
    @ViewBuilder
    private var lightDarkDoubleBorder: some View {
        if study.isBought && (study.type == .light || study.type == .dark) {
            let lineWidth: CGFloat = isCompact ? 1 : 1.5
            RoundedRectangle(cornerRadius: 6)
                .inset(by: lineWidth + 2)
                .stroke(colors.boughtBorder, lineWidth: lineWidth)
        }
    }

    /// Whether any tap interaction is allowed on this card.
    private var isInteractive: Bool {
        // Non-EC: interactive when not bought (tap to buy, long-press to fill)
        // EC: also interactive when unlocked (to allow double-tap start)
        if isEC { return (study.isUnlocked && !study.isRunning) || !study.isBought }
        return !study.isBought
    }

    var body: some View {
        let titleSize: CGFloat = isMinimal ? 24 : (isCompact ? 10 : 14)
        let bodySize: CGFloat = isCompact ? 8 : 11
        VStack(spacing: isCompact ? 2 : 4) {
            Text(displayLabel)
                .font(.system(size: titleSize, weight: .bold).monospacedDigit())
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .allowsTightening(true)

            if isMinimal {
                // Zoomed out: just show the label, nothing else
            } else if isEC {
                // EC: "Eternity Challenge N (X/5)"
                Text(isCompact ? "EC\(-study.id) (\(study.completions)/5)" : "Eternity Challenge \(-study.id) (\(study.completions)/5)")
                    .font(.system(size: bodySize))
                    .foregroundStyle(textColor.opacity(0.85))
                    .multilineTextAlignment(.center)

                if !study.requirementText.isEmpty {
                    if !isCompact {
                        Text("Requirement:")
                            .font(.system(size: bodySize, weight: .medium))
                            .foregroundStyle(textColor.opacity(0.85))
                    }
                    // Volatile leaf — EC progress text ("1.0e94 / 1e95 antimatter")
                    // ticks while the player is pursuing the EC. Keeping it as
                    // a plain Text since the layout cost of a single
                    // monospaced-digit line is small and putting it in an
                    // Equatable leaf wouldn't skip it anyway (text changes
                    // every tick).
                    // No minimumScaleFactor on compact — continuous rescaling
                    // as digits grow caused visible jitter on long-running ECs
                    // (e.g. EC7). Let the text wrap to as many lines as needed
                    // instead; `fixedSize(vertical: true)` lets the card grow.
                    Text(study.requirementText)
                        .font(.system(size: bodySize).monospacedDigit())
                        .foregroundStyle(textColor.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(isCompact ? 3 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if study.isUnlocked && !study.isRunning {
                    Text(isCompact ? "Tap to view" : "Tap to view challenge")
                        .font(.system(size: bodySize, weight: .medium))
                        .foregroundStyle(textColor.opacity(0.75))
                } else if study.isRunning {
                    Text("Running")
                        .font(.system(size: bodySize, weight: .medium))
                        .foregroundStyle(textColor.opacity(0.75))
                }
            } else {
                if !study.description.isEmpty {
                    // Wrapping multiline Text is the dominant layout cost
                    // for an entire card; isolating it in an Equatable
                    // leaf lets SwiftUI skip its `sizeThatFits` work on
                    // ticks where only `effectText` changed.
                    StudyDescriptionText(
                        text: study.description,
                        isCompact: isCompact,
                        isTriad: study.type == .triad,
                        color: textColor.opacity(0.85),
                        bodySize: bodySize
                    )
                    .equatable()
                }

                if !study.effectText.isEmpty {
                    Text(isCompact ? study.effectText : "Currently: \(study.effectText)")
                        .font(.system(size: bodySize, weight: .medium).monospacedDigit())
                        .foregroundStyle(textColor.opacity(0.75))
                        .lineLimit(isCompact ? 1 : nil)
                        .minimumScaleFactor(isCompact ? 0.6 : 1)
                }

                // Requirement text (used by Reality study)
                if !study.requirementText.isEmpty && !isEC {
                    Text(study.requirementText)
                        .font(.system(size: bodySize))
                        .foregroundStyle(textColor.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: !isCompact)
                }
            }

            if !isMinimal {
                let unit = (study.type == .triad) ? "ST" : "TT"
                let longUnit = (study.type == .triad) ? "Space Theorem" : "Time Theorem"
                Text(isCompact ? "\(study.cost) \(unit)" : "Cost: \(study.cost) \(longUnit)\(study.cost == 1 ? "" : "s")")
                    .font(.system(size: bodySize).monospacedDigit())
                    .foregroundStyle(textColor.opacity(0.7))
                    .opacity(study.isBought ? 0 : 1)
            }
        }
        .padding(isCompact ? 4 : 8)
        .frame(width: widthOverride
               ?? (isCompact ? StudyTreeLayout.compactCardWidth : StudyTreeLayout.sharedCardWidth))
        .frame(minHeight: isCompact ? nil : StudyTreeLayout.sharedCardHeightEstimate)
        .background(cardBg)
        .overlay(lightDarkDoubleBorder)
        .overlay(uselessInDoomedOverlay)
        .roundedBorder(borderColor, lineWidth: isCompact ? 1 : 1.5)
        // Web `.c-pelle-useless { text-decoration: line-through }` applies to
        // every Pelle-useless study regardless of bought state.
        .strikethrough(isUselessInDoomed, color: .white.opacity(0.85))
        .onLongPressGesture(minimumDuration: 0.5) {
            if !study.isBought {
                onLongPress?()
            }
        }
        .onTapGesture(count: 1) {
            if isLockedByDoom { return }
            if isEC, study.isUnlocked, !study.isRunning {
                // Navigate to EC tab for unlocked EC studies
                Haptics.tap()
                onStartEC?()
            } else if !study.isBought && study.canBeBought {
                Haptics.tap()
                onBuy()
            }
        }
        .allowsHitTesting(isInteractive && !isLockedByDoom)
    }

    /// Translucent grey-out + "Locked by Doom" label for the Reality study
    /// when it can't be bought during a doomed run. Pelle-useless studies
    /// communicate via the crimson card background + strikethrough text in
    /// the main `body`; this overlay only handles the lock case.
    @ViewBuilder
    private var uselessInDoomedOverlay: some View {
        if isLockedByDoom {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    Text("Locked by Doom")
                        .font(.system(size: isCompact ? 9 : 11, weight: .semibold))
                        .foregroundStyle(GameColor.pelle.readableOnDark())
                )
        }
    }
}

// MARK: - Path Preferences Sheet (matches web PreferredTreeModal)

private struct PathPreferencesSheet: View {
    let engine: GameEngine
    @Environment(\.dismiss) private var dismiss

    // Local editable copy of the ordered Dimension-path priority list, seeded from game state on
    // appear (mirrors PreferredTreeModal.vue's local `dimensionPath`). We write through to JS on
    // every change so the sheet commits live rather than only on close.
    @State private var dimPaths: [Int] = []

    private var state: TimeStudiesState { engine.gameState.eternity.timeStudies }

    // Web CSS colors for study paths
    private static let dimOptions: [(id: Int, name: String, color: Color, borderColor: Color)] = [
        (1, "Antimatter", Color(red: 0.133, green: 0.667, blue: 0.282),  // #22aa48
                          Color(red: 0.098, green: 0.502, blue: 0.212)), // #198036
        (2, "Infinity",   Color(red: 0.714, green: 0.498, blue: 0.200),  // #b67f33
                          Color(red: 0.545, green: 0.384, blue: 0.153)), // #8b6227
        (3, "Time",       Color(red: 0.698, green: 0.255, blue: 0.890),  // #b241e3
                          Color(red: 0.584, green: 0.118, blue: 0.784)), // #951ec8
    ]

    private static let paceOptions: [(id: Int, name: String, color: Color, borderColor: Color)] = [
        (4, "Active",  Color(red: 0.902, green: 0.000, blue: 0.000),  // #e60000
                       Color(red: 0.800, green: 0.000, blue: 0.000)), // #cc0000
        (5, "Passive", Color(red: 0.369, green: 0.200, blue: 0.714),  // #5e33b6
                       Color(red: 0.294, green: 0.157, blue: 0.561)), // #4b288f
        (6, "Idle",    Color(red: 0.000, green: 0.502, blue: 1.000),  // #0080ff
                       Color(red: 0.000, green: 0.400, blue: 0.800)), // #0066cc
    ]

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(8)
                }
            }

            Text("Dimension Split Preference")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            // Shown once a 2nd Dimension path is selectable (Time Study 201 / timeStudySplit
            // dilation upgrade / Reality). Explains the 1st/2nd priority tap flow.
            if state.usePriority {
                Text("Tap two paths to set your 1st and 2nd priority.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                ForEach(Self.dimOptions, id: \.id) { option in
                    let priority = dimPaths.firstIndex(of: option.id).map { $0 + 1 }
                    pathButton(option: option, isSelected: priority != nil, priority: priority) {
                        selectDimPath(option.id)
                    }
                }
            }

            Text("Pace Split Preference")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                ForEach(Self.paceOptions, id: \.id) { option in
                    pathButton(option: option, isSelected: state.preferredPacePath == option.id, priority: nil) {
                        engine.setPreferredPacePath(option.id)
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        .presentationDetents([.medium])
        // Seed the local editable copy once on open. This sheet is modal over the Time Studies
        // tab, so `preferredPaths` can only change here via our own writes — no resync needed
        // (and resyncing from an intermediate poll could momentarily revert a rapid 2nd tap).
        .onAppear { dimPaths = state.preferredDimPaths }
    }

    /// Mirrors PreferredTreeModal.vue `select()`: in priority mode taps accumulate up to two
    /// (rotating the oldest out); otherwise each tap replaces the single selection.
    private func selectDimPath(_ id: Int) {
        if !state.usePriority || dimPaths.count > 1 {
            if !dimPaths.isEmpty { dimPaths.removeFirst() }
        }
        if !dimPaths.contains(id) { dimPaths.append(id) }
        engine.setPreferredDimPaths(dimPaths)
    }

    @ViewBuilder
    private func pathButton(option: (id: Int, name: String, color: Color, borderColor: Color),
                            isSelected: Bool, priority: Int?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(option.name)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isSelected ? .black : option.color)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(isSelected ? option.color : .black)
                .overlay(alignment: .topLeading) {
                    if let priority {
                        Text("\(priority)")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.black)
                            .frame(width: 18, height: 18)
                            .background(.white.opacity(0.85), in: Circle())
                            .padding(4)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(option.borderColor, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Import Studies Sheet

private struct ImportStudiesSheet: View {
    let engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    @State private var studyString: String = ""
    @State private var preview: StudyPreviewInfo = .empty
    @State private var respecAndEternity = false

    private var canEternity: Bool { engine.gameState.infinity.canEternity }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Input your tree")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(8)
                }
            }

            TextField("Study string (e.g. 11,22,32|1)", text: $studyString, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2...4)
                .onChange(of: studyString) { _, newValue in
                    refreshPreview(newValue)
                }

            // Two-column layout: info text + mini tree
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    if preview.isValid {
                        // "With current tree" shown first for import (most relevant)
                        importInfoSection(
                            header: "Importing with your current Tree will purchase:",
                            studies: preview.combinedStudies,
                            costTT: preview.combinedCostTT
                        )

                        importInfoSection(
                            header: "Importing into an empty Tree will purchase:",
                            studies: preview.emptyStudies,
                            costTT: preview.emptyCostTT
                        )

                        if !preview.emptyDimPaths.isEmpty || preview.emptyEC > 0 {
                            VStack(alignment: .leading, spacing: 2) {
                                if !preview.emptyDimPaths.isEmpty {
                                    Text("Dimension Split: \(preview.emptyDimPaths)")
                                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                                }
                                if !preview.emptyPacePaths.isEmpty {
                                    Text("Pace Split: \(preview.emptyPacePaths)")
                                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                                }
                                if preview.emptyEC > 0 {
                                    Text("Eternity Challenge: \(preview.emptyEC)\(preview.emptyStartEC ? " (will start)" : "")")
                                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                                }
                            }
                        }
                    } else if !studyString.isEmpty {
                        Text("Not a valid tree")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if preview.isValid {
                    MiniTreePreview(studyIDs: Set(preview.previewStudyIDs))
                        .frame(width: 200, height: 380)
                        .background(Color.black.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.15)))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    respecAndEternity.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: respecAndEternity ? "checkmark.square.fill" : "square")
                            .foregroundStyle(respecAndEternity ? GameColor.eternity : .white.opacity(0.4))
                        Text("Also respec tree and eternity")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(canEternity ? 0.8 : 0.4))
                    }
                }
                .buttonStyle(.plain)

                if !canEternity {
                    Text("!")
                        .font(.caption.bold())
                        .foregroundStyle(Color(red: 0.2, green: 0.13, blue: 0.13))
                        .frame(width: 18, height: 18)
                        .background(.red, in: Circle())
                }
            }

            HStack(spacing: 12) {
                Button("Paste") {
                    if let clip = UIPasteboard.general.string { studyString = clip }
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.7))

                Spacer()

                Button("Import") {
                    engine.importStudies(studyString, respecAndEternity: respecAndEternity && canEternity)
                    engine.enqueueToast(type: "eternity", text: "Study tree imported")
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(GameColor.eternity)
                .disabled(!preview.isValid)
            }
        }
        .padding(20)
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        .toolbar {
            // Keyboard-attached "Done" so the keyboard can be dismissed to
            // reach the Import button. Without this the keyboard covers the
            // button and swiping down dismisses the whole sheet instead.
            // Mirrors EditPresetSheet. (issue #71)
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func refreshPreview(_ input: String) {
        guard !input.isEmpty else { preview = .empty; return }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = engine.previewStudyString(input)
            DispatchQueue.main.async { preview = result }
        }
    }

    @ViewBuilder
    private func importInfoSection(header: String, studies: String, costTT: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !studies.isEmpty {
                Text(header)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                Text("\(studies) (Cost: \(costTT) TT)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Importing will not purchase any new Time Studies.")
                    .font(.subheadline.italic())
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Edit Preset Sheet

private struct EditPresetSheet: View {
    let engine: GameEngine
    let preset: StudyPresetInfo
    @Environment(\.dismiss) private var dismiss
    @State private var studyString: String = ""
    @State private var presetName: String = ""
    @State private var preview: StudyPreviewInfo = .empty

    private var displayName: String {
        preset.name.isEmpty ? "\(preset.id + 1)" : preset.name
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                HStack {
                    Text("Editing Study Preset \"\(displayName)\"")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(8)
                    }
                }

                // Preset name (above study string so it's visible with keyboard up)
                HStack(spacing: 8) {
                    TextField("Name", text: $presetName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .submitLabel(.done)
                        .onSubmit { performRename() }
                        .onChange(of: presetName) { _, newValue in
                            let filtered = String(newValue.prefix(4).filter { $0.asciiValue != nil })
                            if filtered != newValue { presetName = filtered }
                        }
                    Button("Rename") { performRename() }
                        .buttonStyle(.bordered)
                        .tint(GameColor.eternity)
                    Text("Max 4 characters, ASCII only")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                // Study string input
                TextField("Study string (e.g. 11,22,32|1)", text: $studyString, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2...4)
                    .onChange(of: studyString) { _, newValue in
                        refreshPreview(newValue)
                    }

                // Two-column layout: info text + mini tree
                HStack(alignment: .top, spacing: 16) {
                    // Left: info text
                    VStack(alignment: .leading, spacing: 12) {
                        if preview.isValid {
                            previewInfoSection(
                                header: "Importing into an empty Tree will purchase:",
                                studies: preview.emptyStudies,
                                costTT: preview.emptyCostTT,
                                dimPaths: preview.emptyDimPaths,
                                pacePaths: preview.emptyPacePaths,
                                ec: preview.emptyEC,
                                startEC: preview.emptyStartEC,
                                statusHeader: "Status after loading with no studies:"
                            )

                            Divider().opacity(0.3)

                            previewInfoSection(
                                header: nil,
                                studies: preview.combinedStudies,
                                costTT: preview.combinedCostTT,
                                dimPaths: preview.combinedDimPaths,
                                pacePaths: preview.combinedPacePaths,
                                ec: preview.combinedEC,
                                startEC: preview.combinedStartEC,
                                statusHeader: "Status after loading with current tree:"
                            )
                        } else if !studyString.isEmpty {
                            Text("Not a valid tree")
                                .foregroundStyle(.red)
                                .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Right: mini tree preview
                    if preview.isValid {
                        MiniTreePreview(studyIDs: Set(preview.previewStudyIDs))
                            .frame(width: 200, height: 380)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.15)))
                    }
                }

                // Bottom buttons
                HStack(spacing: 12) {
                    Button("Paste") {
                        if let clip = UIPasteboard.general.string {
                            studyString = clip
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.7))

                    Spacer()

                    Button("Save") {
                        engine.setStudyPresetString(preset.id, studies: studyString)
                        engine.enqueueToast(type: "eternity", text: "Preset saved")
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GameColor.eternity)
            }
        }
        .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            studyString = preset.studies
            presetName = preset.name
            refreshPreview(preset.studies)
        }
    }

    private func performRename() {
        engine.renameStudyPreset(preset.id, name: presetName)
        engine.enqueueToast(type: "eternity", text: "Preset renamed")
    }

    private func refreshPreview(_ input: String) {
        guard !input.isEmpty else { preview = .empty; return }
        // Run on background to avoid blocking UI (jsQueue.sync inside)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = engine.previewStudyString(input)
            DispatchQueue.main.async { preview = result }
        }
    }

    @ViewBuilder
    private func previewInfoSection(
        header: String?,
        studies: String, costTT: Int,
        dimPaths: String, pacePaths: String,
        ec: Int, startEC: Bool,
        statusHeader: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let header, !studies.isEmpty {
                Text(header)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                Text("\(studies) (Cost: \(costTT) TT)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            } else if header != nil, studies.isEmpty {
                Text("Importing will not purchase any new Time Studies.")
                    .font(.subheadline.italic())
                    .foregroundStyle(.white.opacity(0.5))
            }

            if !dimPaths.isEmpty || ec > 0 {
                Text(statusHeader)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 4)
                if !dimPaths.isEmpty {
                    Text("Dimension Split: \(dimPaths)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                if !pacePaths.isEmpty {
                    Text("Pace Split: \(pacePaths)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                if ec > 0 {
                    Text("Eternity Challenge: \(ec)\(startEC ? " (will start)" : "")")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}

// MARK: - Mini Tree Preview

/// Compact visual preview of the study tree, highlighting purchased studies.
private struct MiniTreePreview: View {
    let studyIDs: Set<Int>

    private static let nodeSize: CGFloat = 14
    private static let hGap: CGFloat = 2
    private static let vGap: CGFloat = 3

    /// Map study type → color (from time-studies.css bought colors)
    private func nodeColor(for id: Int) -> Color {
        if id >= -12 && id < 0 { return Color(red: 0.698, green: 0.255, blue: 0.890) } // #b241e3
        if id == -100 { return Color(red: 0.25, green: 0.75, blue: 0.25) }
        if id <= -105 && id >= -108 { return Color(red: 0.698, green: 0.255, blue: 0.890) }
        if id == -200 { return GameColor.reality }
        // Normal study path coloring
        if let path = GameEngine.studyPathMap[id] {
            switch path {
            case .antimatter:  return Color(red: 0.133, green: 0.667, blue: 0.282)  // #22aa48
            case .infinity:    return Color(red: 0.714, green: 0.498, blue: 0.200)  // #b67f33
            case .time:        return Color(red: 0.698, green: 0.255, blue: 0.890)  // #b241e3
            case .active:      return Color(red: 0.902, green: 0.000, blue: 0.000)  // #e60000
            case .passive:     return Color(red: 0.369, green: 0.200, blue: 0.714)  // #5e33b6
            case .idle:        return Color(red: 0.000, green: 0.502, blue: 1.000)  // #0080ff
            case .light:       return .white
            case .dark:        return Color(red: 0.3, green: 0.3, blue: 0.3) // visible dark on dark bg
            default:           return Color(red: 0.698, green: 0.255, blue: 0.890)
            }
        }
        return Color(red: 0.698, green: 0.255, blue: 0.890)  // #b241e3 default
    }

    private static let unavailableColor = GameColor.unavailableBg

    var body: some View {
        let rows = StudyTreeLayout.treeRows
        let ns = Self.nodeSize
        let hg = Self.hGap
        let vg = Self.vGap

        GeometryReader { geo in
            let maxCols = rows.map { $0.count }.max() ?? 1
            let totalW = CGFloat(maxCols) * (ns + hg) - hg
            let totalH = CGFloat(rows.count) * (ns + vg) - vg
            let scale = min(geo.size.width / totalW, geo.size.height / totalH) * 0.9
            let offsetX = (geo.size.width - totalW * scale) / 2
            let offsetY = (geo.size.height - totalH * scale) / 2

            Canvas { ctx, size in
                for (rowIdx, row) in rows.enumerated() {
                    let rowW = CGFloat(row.count) * (ns + hg) - hg
                    let startX = (totalW - rowW) / 2

                    for (colIdx, id) in row.enumerated() {
                        guard id != 0 else { continue }
                        let x = offsetX + (startX + CGFloat(colIdx) * (ns + hg)) * scale
                        let y = offsetY + CGFloat(rowIdx) * (ns + vg) * scale
                        let rect = CGRect(x: x, y: y, width: ns * scale, height: ns * scale)
                        let path = RoundedRectangle(cornerRadius: 2 * scale).path(in: rect)

                        let bought = studyIDs.contains(id)
                        if bought {
                            ctx.fill(path, with: .color(nodeColor(for: id)))
                        } else {
                            ctx.fill(path, with: .color(Self.unavailableColor.opacity(0.5)))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Tree Layout Engine

/// Computes absolute positions for all study cards in the tree.
/// Row-based layout with centered alignment, matching the web tree structure.
private struct StudyTreeLayout {
    let cardWidth: CGFloat
    let cardHeightEstimate: CGFloat
    let hSpacing: CGFloat
    let vSpacing: CGFloat

    /// Set of IDs that belong to rows which collapse when none are unlocked.
    /// Currently triad studies (301-304) — the entire row is hidden until at
    /// least one triad is unlocked (V Ra pet lv 6 unlocks the first tier).
    static let triadIDs: Set<Int> = [301, 302, 303, 304]

    /// IDs that render in the web "wideRow" — narrower card width + tighter
    /// spacing so 8 cells fit roughly within the same span as a 4-cell
    /// normal row. Mirrors `wideRow(...)` in `time-study-tree-layout.js:43-49`
    /// (`itemWidth: 12, spacing: 0.6` vs `itemWidth: 18, spacing: 3`).
    /// Without this distinction the 22x row stretched the canvas to ~2×
    /// the width of the 4-cell rows above/below, leaving the 21x → 22x and
    /// 22x → 23x connection lines visibly skewed.
    static let wideRowIDs: Set<Int> = [221, 222, 223, 224, 225, 226, 227, 228]

    /// Card render width for a given study ID. Defaults to the row's
    /// normal width; wide-row cells use a tighter geometry.
    func cardWidth(for id: Int) -> CGFloat {
        Self.wideRowIDs.contains(id) ? wideCardWidth : cardWidth
    }

    /// Full tree rows including optional triad row. Use `rows(showTriads:)`
    /// for layout so the triad row can be stripped when none are unlocked.
    static let treeRows: [[Int]] = [
        [0, 11, 0],
        [21, 22],
        [0, 31, 32, 33],
        [41, 42],
        [0, 51, -5],
        [0, 61, 62],
        [71, 72, 73],
        [81, 82, 83],
        [91, 92, 93],
        [101, 102, 103],
        [-7, 111, 0],
        [121, 122, 123],
        [-6, 131, 132, 133, -8],
        [141, 142, 143],
        [0, -9, 151, 0, -4],
        [161, 162],
        [171],
        [-1, -2, -3],
        [181],
        [-10],
        [191, 192, 193],
        [201],
        [211, 212, 213, 214],
        [221, 222, 223, 224, 225, 226, 227, 228],
        [301, 302, 303, 304],
        [231, 232, 233, 234],
        [-11, 0, -12],
        [-100],
        [-105, -106],
        [-107, -108],
        [-200],
    ]

    /// Parent→child connections (from web time-study-connections.js)
    static let connections: [(from: Int, to: Int)] = [
        (11, 21), (11, 22),
        (21, 31), (22, 33), (22, 32),
        (31, 41), (32, 42),
        (41, 51), (42, 51), (42, -5),
        (51, 61),
        (-5, 62),  // EC5 → 62 (alt path)
        (61, 71), (61, 72), (61, 73),
        (71, 81), (72, 82), (73, 83),
        (81, 91), (82, 92), (83, 93),
        (91, 101), (92, 102), (93, 103),
        (101, 111), (102, 111), (103, 111),
        (111, -7),
        (111, 121), (111, 122), (111, 123),
        (121, 131), (122, 132), (123, 133),
        (121, -6), (123, -8),
        (131, 141), (132, 142), (133, 143),
        (141, 151), (142, 151), (143, 151),
        (143, -4),
        (151, -9),
        (151, 161), (151, 162),
        (161, 171), (162, 171),
        (171, -1), (171, -2), (171, -3),
        (171, 181),
        (181, -10),
        (-10, 191), (-10, 192), (-10, 193),
        (192, 201),
        (191, 211), (191, 212), (193, 213), (193, 214),
        (211, 221), (211, 222), (212, 223), (212, 224),
        (213, 225), (213, 226), (214, 227), (214, 228),
        (221, 231), (222, 231), (223, 232), (224, 232),
        (225, 233), (226, 233), (227, 234), (228, 234),
        // Triad Studies (Ra V pet lv 6 → 1 triad per Hard V-Achievement tier).
        // Each triad needs two adjacent 22x studies + the matching 23x study.
        (221, 301), (222, 301), (231, 301),
        (223, 302), (224, 302), (232, 302),
        (225, 303), (226, 303), (233, 303),
        (227, 304), (228, 304), (234, 304),
        (231, -11), (232, -11), (233, -12), (234, -12),
        (-11, -100), (-12, -100),
        (-100, -105),
        (-105, -106), (-106, -107), (-107, -108),
        (-108, -200),
    ]

    /// Computed positions for each study ID
    let positions: [Int: CGPoint]
    let totalWidth: CGFloat
    let totalHeight: CGFloat

    static let sharedCardWidth: CGFloat = 200
    static let sharedCardHeightEstimate: CGFloat = 100
    static let compactCardWidth: CGFloat = 90
    // 72 (not 60) so a 4-line non-triad description (the bumped line
    // limit in `StudyDescriptionText`) fits inside the row pitch
    // (cardHeightEstimate + vSpacing = 96pt) without overlapping the
    // next row. Was 60 when the description was capped at 3 lines.
    static let compactCardHeightEstimate: CGFloat = 72

    /// iPad layout — 200pt cards, matches web. `showTriads` collapses the
    /// 301-304 row when no Hard V-Achievement tiers are completed yet.
    static func shared(showTriads: Bool, dilationBought: Bool) -> StudyTreeLayout {
        StudyTreeLayout(cardWidth: sharedCardWidth, cardHeightEstimate: sharedCardHeightEstimate,
                        hSpacing: 16, vSpacing: 40, showTriads: showTriads, dilationBought: dilationBought)
    }

    /// iPhone layout — smaller cards so the tree fits at 0.5x zoom.
    static func compact(showTriads: Bool, dilationBought: Bool) -> StudyTreeLayout {
        StudyTreeLayout(cardWidth: compactCardWidth, cardHeightEstimate: compactCardHeightEstimate,
                        hSpacing: 6, vSpacing: 24, showTriads: showTriads, dilationBought: dilationBought)
    }

    /// Wide-row card width — narrower than `cardWidth` so 8 cells fit within
    /// roughly the same span as a 4-cell normal row (matches web's 12/18 ratio).
    let wideCardWidth: CGFloat
    /// Wide-row inter-cell spacing — tighter than `hSpacing` (matches web's
    /// 0.6/3 ratio).
    let wideSpacing: CGFloat

    private init(cardWidth: CGFloat, cardHeightEstimate: CGFloat,
                 hSpacing: CGFloat, vSpacing: CGFloat, showTriads: Bool, dilationBought: Bool) {
        self.cardWidth = cardWidth
        self.cardHeightEstimate = cardHeightEstimate
        self.hSpacing = hSpacing
        self.vSpacing = vSpacing
        // Web ratios: itemWidth 12/18 = 2/3 for the card; spacing on web is
        // 0.6/3 = 0.2 of normal but at iOS's larger absolute pitch that
        // resolves to a near-zero gap (~1pt iPhone / ~3pt iPad) which reads
        // as "touching, no padding". Bumped the spacing factor to 0.5 of
        // normal hSpacing — 3pt iPhone / 8pt iPad — for clearly visible
        // breathing room between cells while keeping the row narrow enough
        // that it still feels like a single tight cluster (not as airy as
        // the 4-cell normal rows above and below).
        self.wideCardWidth = cardWidth * 2 / 3
        self.wideSpacing = hSpacing * 0.5

        let rows: [[Int]] = showTriads
            ? Self.treeRows
            : Self.treeRows.filter { row in !row.contains(where: { Self.triadIDs.contains($0) }) }

        // Per-row geometry: wide rows (containing any of 221-228) use the
        // narrower card width + tighter spacing; everything else uses the
        // normal geometry. Bound to locals (not `self.*`) because nested
        // functions in an `init` would implicitly capture `self`, which
        // Swift rejects while `self.positions` is still uninitialized.
        let normalCw = cardWidth
        let normalSp = hSpacing
        let wideCw = self.wideCardWidth
        let wideSp = self.wideSpacing
        let rowGeometry: ([Int]) -> (cw: CGFloat, sp: CGFloat) = { row in
            let isWide = row.contains(where: { Self.wideRowIDs.contains($0) })
            return (isWide ? wideCw : normalCw, isWide ? wideSp : normalSp)
        }
        let rowRenderedWidth: ([Int]) -> CGFloat = { row in
            let g = rowGeometry(row)
            let n = CGFloat(row.count)
            return n * g.cw + (n - 1) * g.sp
        }

        var positions: [Int: CGPoint] = [:]

        // Canvas width = the widest *actually rendered* row + a small pad.
        let maxRowWidth = rows.map(rowRenderedWidth).max() ?? 0
        let width = maxRowWidth + 40

        var y: CGFloat = 0
        for row in rows {
            let g = rowGeometry(row)
            let rowWidth = rowRenderedWidth(row)
            let startX = (width - rowWidth) / 2

            for (colIndex, id) in row.enumerated() {
                guard id != 0 else { continue }
                let x = startX + CGFloat(colIndex) * (g.cw + g.sp)
                positions[id] = CGPoint(x: x, y: y)
            }

            y += cardHeightEstimate + vSpacing
            // The Dilation node (-100) renders a multi-line requirement string
            // while unbought ("Requirement: 5 EC11 and EC12 completions and
            // X/12,900 total Time Theorems"), so its card grows past
            // `cardHeightEstimate` — especially on the narrow compact card where
            // the string wraps to several lines. Add clearance below it so it
            // doesn't crowd the TD5/TD6 row beneath. Only while unbought — once
            // purchased the requirement text disappears and the card shrinks
            // back, so the extra gap would just be dead space.
            if row.contains(-100) && !dilationBought { y += cardHeightEstimate * 0.6 }
        }

        self.positions = positions
        self.totalWidth = width
        self.totalHeight = y
    }
}

// MARK: - Enslaved Secret Study

/// The +100 TT "secret" Time Study that only exists inside The Nameless
/// Ones' Reality. Mirrors web `EnslavedTimeStudy.vue` — a genuinely hidden
/// easter egg: completely invisible (but tappable) until the player finds
/// it, at which point it reveals itself as a tan bought-state card with
/// the reward text. Sized to match the regular `StudyCard` so the hidden
/// hitbox occupies the right-of-TS-11 slot. No long-press, no connector.
private struct EnslavedSecretStudyCard: View, Equatable {
    let hasClaimed: Bool
    let isCompact: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let onTap: () -> Void

    /// All four inputs are transition-only — `hasClaimed` flips once on
    /// claim, dimensions only on rotation. Closure excluded (stable engine
    /// reference).
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hasClaimed == rhs.hasClaimed
            && lhs.isCompact == rhs.isCompact
            && lhs.cardWidth == rhs.cardWidth
            && lhs.cardHeight == rhs.cardHeight
    }

    var body: some View {
        Group {
            if hasClaimed {
                // Revealed — full bought-state card.
                VStack(spacing: 4) {
                    Text("Enslaved Secret Study")
                        .font(isCompact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                    Text("+100 Time Theorems")
                        .font(isCompact ? .caption2 : .caption)
                        .foregroundStyle(.black.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .frame(width: cardWidth, height: cardHeight)
                .padding(isCompact ? 4 : 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(GameColor.enslaved))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(GameColor.enslaved, lineWidth: 1))
            } else {
                // Hidden — invisible-but-tappable rectangle matching the
                // card footprint. `Color.clear.contentShape(Rectangle())`
                // gives us a touch target that draws absolutely nothing.
                Color.clear
                    .frame(width: cardWidth, height: cardHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }
            }
        }
    }
}


// MARK: - Secret Time Study card (SecretAchievement(21))

/// Phantom study card placed to the LEFT of TS 11 in the tree, mirroring
/// web `SecretTimeStudy.vue` (web pins it at row 0 col 0 via
/// `time-study-tree-layout.js:149-154`). When `player.secretUnlocks.
/// viewSecretTS` is false the card is rendered as an invisible-but-tappable
/// rectangle the same size as a real study card; tap reveals it AND fires
/// `SecretAchievement(21)`. Once visible, tapping is a no-op (web parity);
/// double-tap (< 0.5s window via SwiftUI's `count: 2`) hides it again.
private struct SecretTimeStudyCard: View {
    let isVisible: Bool
    let isCompact: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let onReveal: () -> Void
    let onHide: () -> Void

    var body: some View {
        Group {
            if isVisible {
                VStack(spacing: 4) {
                    Text("Unlock a Secret Achievement")
                        .font(isCompact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("(Double tap to hide)")
                        .font(isCompact ? .caption2 : .caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(width: cardWidth, height: cardHeight)
                .padding(isCompact ? 4 : 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(GameColor.eternity.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(GameColor.eternity, lineWidth: 1))
                // Web `SecretTimeStudy.vue` `handleClick()`: tapping while
                // already visible is a no-op; only double-tap hides. SwiftUI
                // discriminates double-tap from single-tap when both are
                // attached; the single-tap below is the deliberate no-op
                // that matches web behaviour.
                .onTapGesture(count: 2) { onHide() }
                .onTapGesture(count: 1) { /* no-op when visible, matching web */ }
            } else {
                // Hidden: invisible-but-tappable card-shaped target.
                Color.clear
                    .frame(width: cardWidth, height: cardHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { onReveal() }
            }
        }
    }
}
