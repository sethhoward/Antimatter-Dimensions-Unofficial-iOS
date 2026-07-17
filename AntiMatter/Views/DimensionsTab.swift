//
//  AntimatterDimensionsTab.swift
//  AntiMatter
//
//  Antimatter Dimensions subtab — mirrors ModernAntimatterDimensionsTab.vue.
//  Composes header, tickspeed, dimension rows, boost/galaxy, and progress bar.
//

import SwiftUI

struct AntimatterDimensionsTab: View {
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    // SecretAchievement(41) "That dimension doesn't exist" —
                    // tappable easter egg. Web binds this to the "9" keystroke
                    // (`hotkeys.js:298`); iOS exposes it as an invisible
                    // 12pt-tall band at the very top of the AD tab. Curious
                    // tappers can stumble onto it.
                    Color.clear
                        .frame(height: 12)
                        .contentShape(Rectangle())
                        .onTapGesture { engine.tryPurchaseNinthDimension() }

                    DimensionsHeaderRow(engine: engine)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)

                    DimensionsInfoTextRow(engine: engine)
                        .padding(.horizontal)
                        .padding(.bottom, -2)
                        .padding(.top, -4)

                    DimensionsTickspeedSection(engine: engine)
                        .padding(.bottom, 2)

                    DimensionsRowsSection(engine: engine)

                    DimensionsPrestigeSection(engine: engine)
                       // .padding(.horizontal)
                        .padding(.vertical, metrics.isCompact ? 0 : 6)

                    // Progress bar — in flow below prestige rows (matches web layout)
                    if !metrics.isCompact {
                        DimensionsProgressBar(engine: engine)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }

                    PhoneTabBarSpacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Progress bar (30Hz isolation)

/// Isolates `engine.progressFill` so the parent body doesn't re-evaluate at 30Hz.
/// Mirrors the `PhoneProgressBar` pattern in `PhoneShell`.
private struct DimensionsProgressBar: View {
    let engine: GameEngine

    var body: some View {
        ProgressBarView(fill: engine.progressFill)
            .animation(.linear(duration: 0.1), value: engine.progressFill)
    }
}

// MARK: - Header row: Until 10 | [Sacrifice centered] | Max All

/// Thin reader: does the volatile `engine.gameState` read, then hands an
/// Equatable inner view a primitive snapshot. The reader's body re-runs
/// every tick (gameState reassigns), but its only work is constructing
/// the inner struct value — the inner's `body` (HStack, GameButton
/// constructors, .frame/.padding modifier chains) is skipped via
/// `.equatable()` when the primitives are unchanged.
private struct DimensionsHeaderRow: View {
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let state = engine.gameState
        let buyLabel: String
        if engine.continuumUnlocked && !engine.continuumDisabled {
            buyLabel = "Continuum"
        } else {
            buyLabel = state.buyUntil10 ? "Until 10" : "Buy 1"
        }
        return DimensionsHeaderRowInner(
            isCompact: metrics.isCompact,
            headerButtonWidth: metrics.headerButtonWidth,
            buyQuantityLabel: buyLabel,
            isSacrificeUnlocked: state.isSacrificeUnlocked,
            isAutomated: state.sacrificeIsAutomated,
            canSacrifice: state.canSacrifice,
            nextBoost: state.sacrificeNextBoost,
            disabledReason: state.sacrificeDisabledReason,
            engine: engine
        ).equatable()
    }
}

private struct DimensionsHeaderRowInner: View, Equatable {
    let isCompact: Bool
    let headerButtonWidth: CGFloat
    let buyQuantityLabel: String
    let isSacrificeUnlocked: Bool
    let isAutomated: Bool
    let canSacrifice: Bool
    let nextBoost: String?
    let disabledReason: String?
    /// Reference identity — singleton for the lifetime of the app. Excluded
    /// from `==` so it never blocks the skip.
    let engine: GameEngine

    static func == (lhs: Self, rhs: Self) -> Bool {
        // Layout-affecting primitives must always match.
        let layoutMatches = lhs.isCompact == rhs.isCompact
            && lhs.headerButtonWidth == rhs.headerButtonWidth
            && lhs.buyQuantityLabel == rhs.buyQuantityLabel
            && lhs.isSacrificeUnlocked == rhs.isSacrificeUnlocked
        if !layoutMatches { return false }
        // Sacrifice subtree is fully visually stable when both sides are
        // automated — `nextBoost` still churns at 30Hz on the JS side, but
        // the manual button is informational only and never repaints.
        // Without this short-circuit, naïve field equality always fails
        // and the row's body rebuilds every tick.
        if lhs.isAutomated && rhs.isAutomated { return true }
        return lhs.isAutomated == rhs.isAutomated
            && lhs.canSacrifice == rhs.canSacrifice
            && lhs.nextBoost == rhs.nextBoost
            && lhs.disabledReason == rhs.disabledReason
    }

    var body: some View {
        Group {
            if isCompact {
                // iPhone: sacrifice gets 2x flex width; buy/max shrink to fit
                HStack(spacing: 8) {
                    GameButton(borderColor: .green) {
                        engine.cycleBuyQuantity()
                    } label: {
                        Text(buyQuantityLabel)
                            .font(.caption.weight(.medium))
                            .padding(.vertical, 6)
                    }
                    .frame(minWidth: 60, maxWidth: .infinity, minHeight: 30)

                    if isSacrificeUnlocked {
                        SacrificeButton(
                            isCompact: true,
                            isAutomated: isAutomated,
                            canSacrifice: canSacrifice,
                            nextBoost: nextBoost,
                            disabledReason: disabledReason,
                            engine: engine
                        )
                        .equatable()
                        .frame(maxWidth: .infinity, minHeight: 0)
                        .frame(height: 24)
                        .layoutPriority(1)
                    }

                    GameButton(borderColor: .green) {
                        engine.maxAll()
                    } label: {
                        Text("Max All")
                            .font(.caption.weight(.medium))
                            .padding(.vertical, 6)
                    }
                    .frame(minWidth: 60, maxWidth: .infinity, minHeight: 30)
                    .onHoldRepeat { engine.maxAll() }
                }
            } else {
                // iPad: ZStack overlay layout (unchanged)
                ZStack {
                    HStack {
                        GameButton(borderColor: .green) {
                            engine.cycleBuyQuantity()
                        } label: {
                            Text(buyQuantityLabel)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 6)
                        }
                        .frame(width: headerButtonWidth, height: 30)

                        Spacer()

                        GameButton(borderColor: .green) {
                            engine.maxAll()
                        } label: {
                            Text("Max All")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 6)
                        }
                        .frame(width: headerButtonWidth, height: 30)
                        .onHoldRepeat { engine.maxAll() }
                    }

                    if isSacrificeUnlocked {
                        SacrificeButton(
                            isCompact: false,
                            isAutomated: isAutomated,
                            canSacrifice: canSacrifice,
                            nextBoost: nextBoost,
                            disabledReason: disabledReason,
                            engine: engine
                        )
                        .equatable()
                        .frame(maxWidth: 480)
                    }
                }
            }
        }
    }

    // Sacrifice button is extracted to `SacrificeButton` (Equatable). See
    // that struct's `==` for the automated-state short-circuit that lets
    // SwiftUI skip body re-eval on every tick once Ach 118 + autobuyer have
    // taken over the manual button.
}

// MARK: - Dimensional Sacrifice button (Equatable)

/// Equatable so SwiftUI can skip body re-eval when the button's visual state
/// is unchanged. Custom `==` short-circuits to `true` whenever both sides
/// are in the automated state — once Achievement 118 + the sacrifice
/// autobuyer are active, the button is informational only and never
/// changes its visual, but `sacrificeNextBoost` still churns at 30Hz on
/// the JS side. Without the short-circuit, naïve field-by-field equality
/// would always fail and body would rebuild every poll.
private struct SacrificeButton: View, Equatable {
    let isCompact: Bool
    let isAutomated: Bool
    let canSacrifice: Bool
    let nextBoost: String?
    let disabledReason: String?
    /// Reference identity — singleton for app lifetime, not factored into ==.
    let engine: GameEngine

    static func == (lhs: Self, rhs: Self) -> Bool {
        // Both automated → fully visually stable, skip every other input.
        if lhs.isAutomated && rhs.isAutomated && lhs.isCompact == rhs.isCompact {
            return true
        }
        return lhs.isCompact == rhs.isCompact
            && lhs.isAutomated == rhs.isAutomated
            && lhs.canSacrifice == rhs.canSacrifice
            && lhs.nextBoost == rhs.nextBoost
            && lhs.disabledReason == rhs.disabledReason
    }

    private var canManually: Bool { canSacrifice && !isAutomated }

    private var compactText: String {
        if isAutomated { return "Automated (Ach 118)" }
        if canSacrifice, let boost = nextBoost {
            return "Dimensional Sacrifice (\(boost))"
        }
        return "Dimensional Sacrifice"
    }

    private var compactFont: UIFont {
        canSacrifice
            ? UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            : UIFont.systemFont(ofSize: 12, weight: .regular)
    }

    var body: some View {
        Button {
            engine.sacrifice()
        } label: {
            Group {
                if isCompact {
                    CATextLeaf(
                        text: compactText,
                        font: compactFont,
                        color: canManually ? UIColor.orange : UIColor.white,
                        stretchHorizontally: true
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    if canSacrifice, let boost = nextBoost {
                        Text("Dimensional Sacrifice (\(boost))")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    } else if isAutomated {
                        Text("Dimensional Sacrifice is Automated (Achievement 118)")
                            .font(.subheadline)
                    } else if let reason = disabledReason {
                        Text("Dimensional Sacrifice Disabled (\(reason))")
                            .font(.subheadline)
                    } else {
                        Text("Dimensional Sacrifice")
                            .font(.subheadline)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .background(
            canManually ? Color.orange.opacity(0.25) : GameColor.disabled,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(canManually ? Color.orange.opacity(0.6) : GameColor.disabledBorder, lineWidth: 1)
        )
        .foregroundStyle(canManually ? .orange : .white)
        .buttonStyle(.plain)
        .allowsHitTesting(canManually)
    }
}

// MARK: - Info text row

private struct DimensionsInfoTextRow: View {
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let state = engine.gameState
        DimensionInfoText(
            buy10Mult: state.buy10Mult,
            sacrificeMultiplier: state.sacrificeMultiplier,
            isSacrificeUnlocked: state.isSacrificeUnlocked,
            isCompact: metrics.isCompact
        )
        .equatable()
    }
}

// MARK: - Tickspeed row

private struct DimensionsTickspeedSection: View {
    let engine: GameEngine

    var body: some View {
        let state = engine.gameState
        // Once the Reality time study is bought, web relocates the tickspeed
        // info (total / per-upgrade multiplier) out of the header and into a
        // labels row below the tickspeed button. See TickspeedRow.vue:110-115.
        let showLabels = state.infinity.showRealityButton
        Group {
            if engine.continuumUnlocked && !engine.continuumDisabled {
                TickspeedContinuumRow(
                    value: state.tickspeed.continuumValue,
                    tickspeedPerSecond: state.tickspeed.perSecond,
                    tickspeedMultiplier: state.tickspeed.multiplier,
                    showLabels: showLabels
                )
                .opacity(state.tickspeed.isUnlocked ? 1 : 0)
            } else {
                TickspeedRow(
                    tickspeed: state.tickspeed,
                    onBuy: { engine.buyTickSpeed() },
                    onBuyMax: { engine.buyMaxTickSpeed() },
                    showLabels: showLabels
                )
                .opacity(state.tickspeed.isUnlocked ? 1 : 0)
            }
        }
    }
}

// MARK: - Dimension rows (visible ones rendered, locked ones grayed out)

private struct DimensionsRowsSection: View {
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let state = engine.gameState
        if metrics.isCompact {
            // iPhone: CALayer-based renderer — eliminates per-frame text resolution
            // and layout measurement for 8 rows × 4-5 text fields at 30Hz.
            DimensionRowsRenderer(engine: engine)
                .frame(height: CGFloat(state.dimensions.filter(\.isVisible).count) * 44)
        } else {
            // iPad: keep SwiftUI rows (has CPU headroom)
            VStack(spacing: 0) {
                ForEach(state.dimensions) { dim in
                    if dim.isVisible {
                        DimensionRow(
                            dimension: dim,
                            buyUntil10: state.buyUntil10,
                            isEvenRow: dim.tier % 2 == 0,
                            continuumActive: engine.continuumUnlocked && !engine.continuumDisabled,
                            onBuy: {
                                if dim.howManyCanBuy <= 1 {
                                    engine.buyDimension(dim.tier)
                                } else {
                                    engine.buyAsManyAsYouCanBuy(dim.tier)
                                }
                            }
                        )
                        // Onboarding: anchor the first dimension's row so the
                        // "Buy a Dimension" callout points at it (iPad only —
                        // iPhone's CALayer rows can't take an anchorPreference).
                        .onboardingAnchor(.dimensionBuyButton,
                                          active: engine.onboarding != nil && dim.tier == 1)
                    }
                }
            }
        }
    }
}

// MARK: - Prestige rows (Dim Boost + Galaxy)

/// Outer wrapper — re-evaluates at 30Hz because `engine.gameState` is
/// reassigned every tick, but its only job is to forward the small
/// equatable slice of state to `PrestigeSectionContent`. SwiftUI's
/// `EquatableView` then diffs the inputs and skips re-rendering the
/// inner body when nothing relevant has changed.
private struct DimensionsPrestigeSection: View {
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        let state = engine.gameState
        PrestigeSectionContent(
            dimBoost: state.dimBoost,
            galaxy: state.galaxy,
            quickResetAvailable: engine.quickResetAvailable,
            quickResetHasBoosts: engine.quickResetHasBoosts,
            isCompact: metrics.isCompact,
            onBuyBoost: { engine.buyDimensionBoost() },
            onBuyGalaxy: { engine.buyGalaxy() },
            onQuickReset: { engine.quickReset() }
        )
        .equatable()
    }
}

/// Inner equatable subview — body only re-evaluates when one of the
/// declared fields actually changes. Closures are intentionally excluded
/// from `==` because they capture a stable engine reference and have no
/// observable behavior change between ticks.
private struct PrestigeSectionContent: View, Equatable {
    let dimBoost: DimBoostState
    let galaxy: GalaxyState
    let quickResetAvailable: Bool
    let quickResetHasBoosts: Bool
    let isCompact: Bool
    let onBuyBoost: () -> Void
    let onBuyGalaxy: () -> Void
    let onQuickReset: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.dimBoost == rhs.dimBoost
            && lhs.galaxy == rhs.galaxy
            && lhs.quickResetAvailable == rhs.quickResetAvailable
            && lhs.quickResetHasBoosts == rhs.quickResetHasBoosts
            && lhs.isCompact == rhs.isCompact
    }

    var body: some View {
        // iPhone, with quick-reset visible: split the row into two
        // parts so the Reset button only competes for horizontal space
        // with the LABELS, not with the action buttons.
        //
        //   ┌──────────────┬──────┬──────────────┐
        //   │ Boost label  │Reset │ Galaxy label │
        //   ├──────────────┴──────┴──────────────┤
        //   │ Boost button (50%)│Galaxy btn (50%)│
        //   └─────────────────────────────────────┘
        //
        // Boost + Galaxy buttons stay side-by-side at full half-width
        // each, while Reset sits between the two labels at the top.
        // Reset is taller than the labels (HIG-friendly tap target);
        // the headers stay top-aligned, leaving a small gap below
        // them next to Reset. Acceptable tradeoff for a touch-sized
        // button on a destructive action.
        //
        // When quick-reset isn't visible, fall through to the simple
        // 2-col HStack (no top split needed).
        // iPad keeps the 3-col HStack always; documented divergence
        // from web (Known iPad Layout Divergences #5).
        if isCompact && quickResetAvailable {
            VStack(spacing: 2) {
                HStack(alignment: .top, spacing: 8) {
                    DimBoostHeader(dimBoost: dimBoost)
                        .equatable()
                        .frame(maxWidth: .infinity)
                    quickResetButton
                    GalaxyHeader(galaxy: galaxy)
                        .equatable()
                        .frame(maxWidth: .infinity)
                }
                HStack(alignment: .top, spacing: 12) {
                    DimBoostActionButton(
                        dimBoost: dimBoost,
                        onBuy: onBuyBoost
                    )
                    .equatable()
                    .frame(maxWidth: .infinity)
                    GalaxyActionButton(
                        galaxy: galaxy,
                        onBuy: onBuyGalaxy
                    )
                    .equatable()
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 2)
        } else {
            HStack(alignment: .top, spacing: isCompact ? 8 : 24) {
                DimBoostRow(
                    dimBoost: dimBoost,
                    onBuy: onBuyBoost
                )
                if quickResetAvailable {
                    quickResetButton
                }
                GalaxyRow(
                    galaxy: galaxy,
                    onBuy: onBuyGalaxy
                )
            }
        }
    }

    @ViewBuilder
    private var quickResetButton: some View {
        GameButton(borderColor: .green) {
            onQuickReset()
        } label: {
            Text(isCompact
                 ? (quickResetHasBoosts ? "Reset\n(lose a Boost)" : "Reset\n(no gain)")
                 : (quickResetHasBoosts
                    ? "Perform a Dimension Boost reset but lose a Dimension Boost"
                    : "Perform a Dimension Boost reset for no gain"))
                .font(.system(size: isCompact ? 11 : 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(isCompact ? 0.8 : 1.0)
                .padding(.horizontal, isCompact ? 6 : 16)
                .padding(.vertical, isCompact ? 6 : 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // iPhone: fixed 110pt × 50pt — wider than 1-line "Reset" so the
        // 2-line label fits at 11pt monospace, taller than the previous
        // 29pt so taps don't graze the labels above. The HStack(.top)
        // pinning the headers leaves a small gap below header text on
        // Reset's flanks; accepted as the tradeoff for a HIG-friendly
        // tap target on a destructive action.
        .frame(width: isCompact ? 110 : nil,
               height: isCompact ? 50 : nil)
    }
}

// MARK: - Dimension info text (30Hz isolation)

/// Isolated subview for buy-10 multiplier and sacrifice text that updates every tick.
/// Prevents parent VStack (header, dimension rows, tickspeed) from re-evaluating on tick.
private struct DimensionInfoText: View, Equatable {
    let buy10Mult: String
    let sacrificeMultiplier: String?
    let isSacrificeUnlocked: Bool
    let isCompact: Bool

    var body: some View {
        if isCompact {
            let text = isSacrificeUnlocked
                ? "Buy 10 Dimension purchase: \(buy10Mult) | Sacrifice: \(sacrificeMultiplier ?? "×1.00")"
                : "Buy 10 Dimension purchase: \(buy10Mult)"
            CATextLeaf(
                text: text,
                font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                color: UIColor.white.withAlphaComponent(0.6),
                stretchHorizontally: true
            )
            .frame(maxWidth: .infinity)
        } else {
            if isSacrificeUnlocked {
                Text("Buy 10 Dimension purchase multiplier: \(buy10Mult) | Dimensional Sacrifice multiplier: \(sacrificeMultiplier ?? "×1.00")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Buy 10 Dimension purchase multiplier: \(buy10Mult)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
