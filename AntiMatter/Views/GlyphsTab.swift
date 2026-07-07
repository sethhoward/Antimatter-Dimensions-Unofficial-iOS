//
//  GlyphsTab.swift
//  AntiMatter
//
//  Glyphs — two-column layout matching web's GlyphsTab.vue.
//  Left column: peek, reset, reminder, level factors, controls.
//  Right column: equipped+effects (side-by-side), inventory below.
//
//  All glyph manipulation is drag & drop:
//  - Drag from inventory → equipped slot to equip
//  - Drag from inventory → sacrifice zone to sacrifice
//  - Drag from inventory → empty inventory slot to reorder
//  - Tap equipped area → shows equipped glyphs detail sheet
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drag State

struct GlyphDragInfo: Equatable {
    let glyphId: Int
    let isEquipped: Bool
    let slotIndex: Int
}

// MARK: - Tooltip Sheet Context
//
// Inventory-only context — equipped glyph taps now route to the all-equipped
// summary sheet (web parity), so `isEquipped` and `equippedSlot` are gone.
// The tooltip sheet exists solely to surface the inventory-actionable buttons
// (Equip / Sacrifice / Move to Protected Row) that web reaches via right-click.

private struct GlyphSheetContext: Identifiable {
    let glyph: GlyphInfo
    let sacrificeUnlocked: Bool
    let hasProtectedRows: Bool // protectedRows > 0
    var id: Int { glyph.id }
}

// MARK: - Main Tab

struct GlyphsTab: View {
    let engine: GameEngine

    var body: some View {
        GlyphsTabContent(engine: engine)
    }
}

/// Wraps the full Glyphs tab. Holds all @State for sheets, drag-and-drop,
/// inventory menu, and tooltip presentation; reads
/// `engine.gameState.glyphsState` internally. Splitting this off keeps the
/// public `GlyphsTab` body inert across per-tick state churn — important
/// here because the inventory grid + equipped slots + sacrifice totals all
/// re-evaluate at 30Hz under their own dependencies, but the parent shell
/// shouldn't drag the entire layout pipeline along with each one.
private struct GlyphsTabContent: View {
    let engine: GameEngine

    @State private var showSacrifice = false  // iPad segmented picker state
    @AppStorage("glyphSacrificeExpanded") private var sacrificeExpanded = true  // iPhone DG state
    @State private var showEquippedModal = false
    @State private var showPeekDetail = false
    @State private var showReminderExpanded = false
    @State private var showLevelFactors = false
    @State private var showEffarigWeights = false
    @State private var showGlyphPresets = false
    @AppStorage("glyphEffectsExpanded") private var showEffects = true
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.pagingGestureCoordinator) private var pagingCoordinator
    @State private var draggedGlyph: GlyphDragInfo?
    @State private var sacrificeDropTargeted = false
    @State private var tooltipGlyph: GlyphSheetContext?
    @State private var showInventoryMenu = false

    private var state: GlyphsTabState { engine.gameState.glyphsState }

    private func beginDragSession(_ info: GlyphDragInfo) -> NSItemProvider {
        // NOTE: we intentionally do NOT toggle
        // `pagingCoordinator?.isPagingEnabled` any more. Doing so requires
        // a reliable "drag ended" callback that SwiftUI's `.onDrag` simply
        // doesn't provide — cancelled drops never fire `.onDrop`, the
        // screen-level catch-all doesn't fire when inner handlers reject,
        // and safety timers either cancel active drags too early or leave
        // paging locked too long. Every attempt to work around this
        // created new edge cases (stuck paging on drop cancel, blank
        // Reality tab, subtab swipe blocked).
        //
        // Trade-off: the user may occasionally page-flip if they drag a
        // glyph near the pager edge and UIKit auto-scrolls. This is
        // normal iOS drag-and-drop behaviour and recoverable (swipe
        // back). The alternative — paging silently broken — is not.
        draggedGlyph = info
        return NSItemProvider(object: "glyph:\(info.glyphId)" as NSString)
    }

    private func endDragSession() {
        draggedGlyph = nil
    }

    var body: some View {
        // GeometryReader proposes its size to its content during the layout
        // pass, so `proxy.size.width` is the width OFFERED by the parent —
        // not the final post-overflow width reported by `.onGeometryChange`
        // or `.background(GeometryReader)`. Rigid content inside wideLayout
        // (fixed-width left column, fixed-size inventory grid) was inflating
        // the measured width via a feedback loop: content renders at N →
        // contentColumn grows to N → probe reports N → layout uses N again.
        // Reading the proposed width from a wrapping GeometryReader breaks
        // that loop cleanly.
        //
        // Perf: the GeometryReader's closure only builds a ScrollView +
        // layout — no heavy subviews are conditional on `proxy.size.width`
        // beyond the narrow/wide branch (which SwiftUI diffs cheaply). Body
        // re-evaluates at 30Hz from gameState ticks whether or not the
        // GeometryReader is present, so the wrapping adds no meaningful
        // cost vs. the old `@State viewportWidth` approach.
        GeometryReader { proxy in
            let width = proxy.size.width
            ScrollView {
                VStack(spacing: 12) {
                    // Effarig's Reality stage banner — only shown during the run;
                    // explains the Glyph level cap players would otherwise see
                    // take silent effect on generated Glyphs.
                    if state.effarigRunning {
                        EffarigStageBanner(
                            stageName: state.effarigStageName,
                            glyphLevelCap: state.effarigGlyphLevelCap
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }

                    // Pelle's Doomed Reality strips glyph equipping until
                    // the player buys `PelleUpgrade.glyphEquipping`. Surface
                    // a banner so the disabled equip buttons make sense.
                    if engine.pelleGlyphEquippingDisabled {
                        PelleGlyphsDisabledBanner()
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    // Glyph instability flavor — fires once `bestReality.glyphLevel`
                    // exceeds 800. Mirrors web `GlyphsTab.vue.showInstability`.
                    if state.showInstability {
                        GlyphInstabilityNotice(
                            instabilityThreshold: state.instabilityThreshold,
                            hyperInstabilityThreshold: state.hyperInstabilityThreshold
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }

                    // Switch to the single-column narrow layout when the viewport
                    // is too cramped for equipped + effects + inventory side-by-
                    // side (iPad portrait on 9.7"/10.9"/11"). Threshold ≈ left
                    // column + equipped (240) + gap + effects minimum.
                    let useWide = width >= 700
                    if metrics.isCompact || !useWide {
                        narrowLayout(width: width)
                    } else {
                        wideLayout(width: width)
                    }

                    PhoneTabBarSpacer()
                }
            }
        }
        // Catch-all drop target — clears the in-flight drag state if the
        // user releases inside the ScrollView but outside the grid.
        .onDrop(of: [.text], isTargeted: nil) { _ in
            endDragSession()
            return false
        }
        .onDisappear { endDragSession() }
        .sheet(isPresented: $showEquippedModal) {
            EquippedGlyphsSheet(
                glyphs: state.equippedSortedGlyphs,
                setName: state.setName
            )
        }
        .sheet(isPresented: $showPeekDetail) {
            PeekGlyphsSheet(glyphs: state.peekGlyphs, level: state.peekLevel)
        }
        .sheet(item: $tooltipGlyph) { ctx in
            // Equip is suppressed when Pelle has disabled it — clears the
            // tooltip's primary action so the user gets the banner-driven
            // signal instead of a button that does nothing.
            let canEquip = !engine.pelleGlyphEquippingDisabled
            GlyphTooltipSheet(
                glyph: ctx.glyph,
                onEquip: canEquip ? { [id = ctx.glyph.id] in engine.equipGlyph(id) } : nil,
                onSacrifice: ctx.sacrificeUnlocked ? { [id = ctx.glyph.id] in engine.sacrificeGlyph(id) } : nil,
                onProtect: ctx.hasProtectedRows ? { [id = ctx.glyph.id] in engine.moveGlyphToProtectedRow(id) } : nil,
                // Music Glyph cosmetic (Teresa shop). Offer "Set" when the cosmetic
                // is unlocked and this glyph isn't already customized or locked;
                // offer "Reset" when it currently has a (non-fixed) custom appearance.
                onSetMusicGlyph: (state.musicCosmeticUnlocked && !ctx.glyph.isFixedCosmetic && !ctx.glyph.hasCustomCosmetic)
                    ? { [id = ctx.glyph.id] in engine.setGlyphCosmetic(id, "music") } : nil,
                onResetCosmetic: (ctx.glyph.hasCustomCosmetic && !ctx.glyph.isFixedCosmetic)
                    ? { [id = ctx.glyph.id] in engine.setGlyphCosmetic(id, nil) } : nil
            )
        }
        .sheet(isPresented: $showEffarigWeights) {
            EffarigGlyphWeightsSheet(engine: engine)
        }
        .sheet(isPresented: $showGlyphPresets) {
            GlyphPresetsSheet(engine: engine)
        }
    }

    // MARK: - Wide Layout (iPad — Two Columns)

    private func wideLayout(width: CGFloat) -> some View {
        // Before the first onGeometryChange measurement, assume a generous
        // iPad-landscape default so tiles don't pop in at a wrong size.
        let effective = width > 0 ? width : 1024
        // Shrink the left sidebar on narrower widths (iPad portrait, split
        // view, slide-over) so the inventory grid has room to fit without
        // clipping the whole layout.
        let leftColWidth: CGFloat = effective < 900 ? 240 : 280
        // Equipped column holds a 230pt circular ring — don't shrink below 240.
        let equippedWidth: CGFloat = 240
        // Drop the old min-width/min-tile floors — they forced the grid wider
        // than the viewport in iPad portrait, clipping both sides.
        let rightWidth = max(effective - leftColWidth - 16 - 32, 280)
        // 10 fixed columns + 9 gaps of 4pt. Keep a finger-sized minimum so the
        // grid is still tappable on a very narrow split view.
        let tileSize = max(floor((rightWidth - 9 * 4) / 10), 32)

        return HStack(alignment: .top, spacing: 16) {
            // LEFT COLUMN: controls sidebar
            leftColumn
                .frame(width: leftColWidth)

            // RIGHT COLUMN: equipped+effects, then inventory
            VStack(spacing: 16) {
                enslavedHintBanner
                HStack(alignment: .top, spacing: 16) {
                    equippedSection(isWide: true, availableWidth: equippedWidth)
                    effectsSection(isWide: true)
                }

                inventorySection(tileSize: tileSize, columnCount: 10)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding()
    }

    // MARK: - Narrow Layout (iPhone — Single Column)

    private func narrowLayout(width: CGFloat) -> some View {
        // Fall back to a small positive width before first measurement.
        // `width` is the ScrollView's content width captured via
        // onGeometryChange — used only for tile/slot sizing, NOT as the
        // VStack's fixed frame. A fixed frame here would feed back into
        // the measurement and lock the layout at the fallback value.
        let w = max(width, 320)
        let contentWidth = w - 32 // subtract horizontal padding
        return VStack(spacing: 14) {
            // Action buttons
            glyphPeekSection
            resetRealityButton
            realityAmplifyButton
            retryCelestialToggle
            realityReminderSection

            // Active effects — collapsible, open by default
            narrowEffectsSection

            // Sacrifice totals — own collapsible section on iPhone so the
            // drop zone + per-type totals are discoverable. iPad shows this
            // inline inside the effects panel via a segmented picker; iPhone
            // previously buried it behind that same picker one level deeper
            // inside the effects DisclosureGroup (users missed it).
            if state.sacrificeUnlocked {
                narrowSacrificeSection
            }

            // Equipped glyphs
            enslavedHintBanner
            equippedSection(isWide: false, availableWidth: contentWidth)

            // Controls (respec toggle)
            controlsSection

            // Inventory grid — 5 columns on iPhone (larger tap targets),
            // 10 columns on iPad narrow portrait (matches wide-layout density).
            let colCount = metrics.isCompact ? 5 : 10
            let phoneTileSize = max(floor((contentWidth - CGFloat(colCount - 1) * 4) / CGFloat(colCount)), 36)
            inventorySection(tileSize: phoneTileSize, columnCount: colCount)

            // Inventory management (sort, protected rows)
            inventoryManagementCard

            // Auto Glyph Arrangement + Remove weaker Glyphs
            autoArrangementCard
            if state.sacrificeUnlocked { removeWeakerCard }

            // Level factors
            glyphLevelFactorsSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Left Column (Wide Only)

    private var leftColumn: some View {
        VStack(spacing: 12) {
            glyphPeekSection
            resetRealityButton
            realityAmplifyButton
            retryCelestialToggle
            realityReminderSection
            glyphLevelFactorsSection
            controlsSection
            inventoryManagementCard
            autoArrangementCard
            if state.sacrificeUnlocked { removeWeakerCard }
        }
    }

    // MARK: - Glyph Peek

    @ViewBuilder
    private var glyphPeekSection: some View {
        // Post-first-Reality, always render the peek branch — the cached
        // upcoming-glyph snapshot on GameEngine fills the brief gap when an
        // automator-driven Reality resets Time Studies and `canPeek` flips
        // false for a few polls. The legitimate "Purchase the Reality study"
        // prompt is preserved for pre-first-Reality players who haven't
        // bought the study yet.
        if state.canPeek || engine.realityUnlocked {
            VStack(spacing: 6) {
                Text("Upcoming Glyph selection:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !state.peekGlyphs.isEmpty {
                    // LazyVGrid wraps into multiple rows when Ra's
                    // `extraGlyphChoicesAndRelicShardRarityAlwaysMax` unlock
                    // doubles peek choices (5 → 10). The old HStack overflowed
                    // off the right edge of the tab on iPhone.
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 56), spacing: 8, alignment: .top)],
                        alignment: .center,
                        spacing: 8
                    ) {
                        ForEach(state.peekGlyphs) { glyph in
                            GlyphComponent(glyph: glyph, size: 44, isCircular: true)
                                .equatable()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 8)

                    if state.peekLevel > 0 {
                        Text("Level \(state.peekLevel)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text("(Tap to see details)")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !state.peekGlyphs.isEmpty {
                    showPeekDetail = true
                }
            }
        } else {
            Text("Purchase the Reality study to see\nthis Reality's Glyph choices")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.1))
                .roundedBorder(.gray, lineWidth: 1)
        }
    }

    // MARK: - Reset Reality

    private var resetRealityButton: some View {
        // While Doomed, this same button restarts the current Armageddon
        // (Pelle's only "reset" affordance) — relabel to match.
        let label = engine.pelleDoomed ? "Start this Armageddon over" : "Start this Reality over"
        return GameButton(borderColor: GameColor.badPink, isEnabled: true) {
            engine.resetReality()
        } label: {
            Text(label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(GameColor.badPink)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Repeat Celestial Reality toggle
    //
    // Web `GlyphsTab.vue:128-146` renders this checkbox under the prestige
    // buttons whenever `isInCelestialReality()`. Toggles `player.options.retryCelestial`
    // — drives auto-restart of the current Celestial run on next prestige.
    @ViewBuilder
    private var retryCelestialToggle: some View {
        if state.inCelestialReality {
            Toggle(isOn: Binding(
                get: { state.retryCelestialEnabled },
                set: { engine.setRetryCelestial($0) }
            )) {
                Text("Repeat this Celestial's Reality")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .toggleStyle(SwitchToggleStyle(tint: GameColor.celestials))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Enslaved hint
    //
    // Web `GlyphsTab.vue:71-75` shows this flavor line above the equipped
    // glyphs whenever Enslaved is running AND any non-companion glyph was
    // level-boosted by `Enslaved.glyphLevelMin`.
    @ViewBuilder
    private var enslavedHintBanner: some View {
        if state.showEnslavedHint {
            Text("done... what little... I can... with Glyphs...")
                .font(.subheadline.italic())
                .foregroundStyle(GameColor.enslaved)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(GameColor.enslaved.opacity(0.45), lineWidth: 1)
                )
        }
    }

    // MARK: - Reality Amplify (Enslaved)

    /// Web `RealityAmplifyButton.vue`. Visible whenever Enslaved is unlocked.
    /// Toggles `Enslaved.boostReality` so the next Reality's rewards are
    /// multiplied by `realityBoostRatio`, in exchange for stored real time.
    @ViewBuilder
    private var realityAmplifyButton: some View {
        let enslaved = engine.gameState.celestials.enslaved
        if enslaved.isUnlocked {
            let copy = amplifyCopy(enslaved)
            GameButton(
                theme: copy.theme,
                isEnabled: copy.isEnabled
            ) {
                engine.toggleEnslavedAmplify()
            } label: {
                Text(copy.text)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
    }

    private struct AmplifyCopy {
        let text: String
        let theme: ButtonTheme
        let isEnabled: Bool
    }

    private func amplifyCopy(_ e: EnslavedState) -> AmplifyCopy {
        if engine.pelleDoomed {
            // Pelle-themed (red) for visual consistency with the rest of the
            // doomed UI surface (banners, struck-through milestones, etc).
            return AmplifyCopy(
                text: "You cannot amplify Doomed Realities.",
                theme: .pelle, isEnabled: false
            )
        }
        if e.amplifyIsInCelestialReality {
            return AmplifyCopy(
                text: "You cannot amplify Celestial Realities.",
                theme: .enslaved, isEnabled: false
            )
        }
        if !e.amplifyCanAmplify && !e.amplifyIsActive {
            return AmplifyCopy(
                text: "Not enough stored real time to amplify.",
                theme: .enslaved, isEnabled: false
            )
        }
        if e.amplifyIsActive {
            return AmplifyCopy(
                text: "Will be amplified — All rewards ×\(e.amplifyRatio)",
                theme: .enslaved, isEnabled: true
            )
        }
        return AmplifyCopy(
            text: "Amplify this Reality — All rewards ×\(e.amplifyRatio)",
            theme: .enslaved, isEnabled: true
        )
    }

    // MARK: - Reality Reminder

    @ViewBuilder
    private var realityReminderSection: some View {
        if !state.reminderText.isEmpty {
            let borderColor: Color = state.reminderIsGood ? .green : GameColor.badPink
            let textColor: Color = state.reminderIsGood ? .green : GameColor.badPink

            VStack(spacing: 6) {
                Button {
                    if !state.reminderSuggestions.isEmpty {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showReminderExpanded.toggle()
                        }
                    }
                } label: {
                    HStack {
                        Text(state.reminderText)
                            .font(.subheadline)
                            .foregroundStyle(textColor)
                            .multilineTextAlignment(.center)

                        if !state.reminderSuggestions.isEmpty {
                            Image(systemName: showReminderExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(textColor.opacity(0.7))
                        }
                    }
                    // Stable minHeight prevents the Glyphs tab from bouncing
                    // when `reminderText` flips between its 3 variants. The
                    // "You still need to unlock Reality in the Time Study
                    // Tree." string wraps to 2 lines on iPhone; the other
                    // two ("Ready to Reality!", "N things to do before
                    // Reality") fit on 1. Without a reserved height, the
                    // section pops up/down on every Reality reset because
                    // `canPeek` (= `TimeStudy.reality.isBought`) flips false
                    // for a few polls while the automator re-buys studies,
                    // which selects the long unlock-prompt variant. Pairs
                    // with the sticky peek cache in `GameEngine.pollGlyphs`
                    // — both are part of the anti-bounce fix for
                    // automator-driven Realities. 44pt covers the 2-line
                    // case with subheadline + 8pt vertical padding.
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                if showReminderExpanded && !state.reminderSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(state.reminderSuggestions.enumerated()), id: \.offset) { _, suggestion in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\u{2022}")
                                    .foregroundStyle(GameColor.badPink)
                                Text(suggestion)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
            .background(Color(white: 0.1))
            .roundedBorder(borderColor, lineWidth: 1)
        }
    }

    // MARK: - Glyph Level Factors

    @ViewBuilder
    private var glyphLevelFactorsSection: some View {
        GlyphLevelFactorsCard(
            state: state.levelFactors,
            isExpanded: $showLevelFactors,
            trailingAction: state.hasGlyphWeights ? AnyView(
                Button {
                    showEffarigWeights = true
                } label: {
                    Label("Adjust Weights", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GameColor.effarig)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(GameColor.effarig.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            ) : nil
        )
    }

    // MARK: - Equipped Glyphs

    @ViewBuilder
    private func equippedSection(isWide: Bool, availableWidth: CGFloat) -> some View {
        VStack(spacing: 8) {
            // Glyph Presets entry — opens the loadout modal. Web parity:
            // matches `GlyphSetSavePanel.vue`. Sits above the "Equipped
            // Glyphs" header so it reads as a primary affordance.
            GameButton(borderColor: GameColor.reality, isEnabled: true) {
                showGlyphPresets = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.caption)
                    Text("Glyph Presets")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            // Header — tap to show equipped list
            VStack(spacing: 4) {
                Text("Equipped Glyphs")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                if !state.setName.isEmpty {
                    Text(state.setName)
                        .font(.caption)
                        .foregroundStyle(Color(hex: state.equippedGlyphs.compactMap { $0 }.first?.typeColor ?? "#888"))
                        .italic()
                }
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                showEquippedModal = true
            }

            if isWide {
                circularEquippedView
            } else {
                horizontalEquippedView(availableWidth: availableWidth)
            }

        }
        .frame(width: isWide ? availableWidth : nil)
    }

    private var circularEquippedView: some View {
        let count = state.activeSlotCount
        let radius: CGFloat = 75
        let ringSize: CGFloat = 230

        return ZStack {
            ForEach(0..<count, id: \.self) { idx in
                let angle = 2 * Double.pi * Double(idx) / Double(count) - Double.pi / 2
                let x = radius * cos(angle)
                let y = radius * sin(angle)

                equippedSlotView(idx: idx, size: 50)
                    .offset(x: x, y: y)
            }
        }
        .frame(width: ringSize, height: ringSize)
    }

    private func horizontalEquippedView(availableWidth: CGFloat) -> some View {
        let count = max(CGFloat(state.activeSlotCount), 1)
        // Each slot's drop target is size * 1.6; account for spacing between slots
        let slotSize = min(55, (availableWidth - (count - 1) * 10) / (count * 1.6))
        return HStack(spacing: 10) {
            ForEach(0..<state.activeSlotCount, id: \.self) { idx in
                equippedSlotView(idx: idx, size: slotSize)
            }
        }
    }

    @ViewBuilder
    private func equippedSlotView(idx: Int, size: CGFloat) -> some View {
        let dropSize = size * 1.6  // larger drop target around the glyph
        if let glyph = state.equippedGlyphs.indices.contains(idx) ? state.equippedGlyphs[idx] : nil {
            GlyphComponent(glyph: glyph, size: size, isCircular: true)
                .equatable()
                .onTapGesture {
                    // Web parity: tapping any equipped slot opens the all-equipped
                    // summary modal (`Modal.glyphShowcasePanel`) — not a per-glyph
                    // detail. Per-glyph unequip isn't a player action; respec/undo
                    // live in the main GlyphsTab controls.
                    showEquippedModal = true
                }
                .onDrag {
                    beginDragSession(GlyphDragInfo(glyphId: glyph.id, isEquipped: true, slotIndex: idx))
                }
                .frame(width: dropSize, height: dropSize)
                .contentShape(Rectangle())
                .onDrop(of: [.text], isTargeted: nil) { _ in
                    handleEquipDrop(toSlot: idx)
                }
        } else {
            emptySlotCircle(size: size)
                .frame(width: dropSize, height: dropSize)
                .contentShape(Rectangle())
                .onDrop(of: [.text], isTargeted: nil) { _ in
                    handleEquipDrop(toSlot: idx)
                }
        }
    }

    private func handleEquipDrop(toSlot: Int) -> Bool {
        guard let drag = draggedGlyph, !drag.isEquipped else {
            endDragSession()
            return false
        }
        // Pelle blocks equipping until `PelleUpgrade.glyphEquipping` is bought.
        guard !engine.pelleGlyphEquippingDisabled else {
            endDragSession()
            return false
        }
        engine.equipGlyphToSlot(drag.glyphId, slot: toSlot)
        endDragSession()
        return true
    }

    private func emptySlotCircle(size: CGFloat) -> some View {
        Circle()
            .strokeBorder(Color.gray.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .frame(width: size, height: size)
    }

    // MARK: - Narrow Effects (Collapsible)

    private var narrowEffectsSection: some View {
        // iPhone-only: effects live in their own collapsible section.
        // Sacrifice totals are surfaced as a sibling `narrowSacrificeSection`
        // (see body) so users don't have to drill into a picker to find them.
        DisclosureGroup(isExpanded: $showEffects) {
            effectsListView(isWide: false)
                .padding(.top, 4)
        } label: {
            Text("Currently active Glyph effects")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Narrow Sacrifice Section (iPhone)

    private var narrowSacrificeSection: some View {
        DisclosureGroup(isExpanded: $sacrificeExpanded) {
            sacrificeTotalsView
                .padding(.top, 4)
        } label: {
            Text("Glyph Sacrifice Boosts")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Effects Section

    @ViewBuilder
    private func effectsSection(isWide: Bool) -> some View {
        // iPad-specific divergence — see "Known iPad Layout Divergences" in
        // the design notes. Web shows both panels stacked; iPad uses a segmented
        // picker so each panel gets the full column height.
        VStack(alignment: .leading, spacing: 8) {
            if state.sacrificeUnlocked {
                Picker("Display", selection: $showSacrifice) {
                    Text("Current Effects").tag(false)
                    Text("Sacrifice Boosts").tag(true)
                }
                .pickerStyle(.segmented)
            }

            if showSacrifice && state.sacrificeUnlocked {
                sacrificeTotalsView
            } else {
                effectsListView(isWide: isWide)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func effectsListView(isWide: Bool) -> some View {
        // Web `CurrentGlyphEffects.vue` renders all content centered, single
        // column, with same-type effects grouped consecutively (sort applied
        // JS-side via `glyphEffectsOrder`). iOS mirrors the centered single-
        // column flow regardless of how many effects there are.
        let pelle = engine.gameState.celestials.pelle
        let levelText = pelle.glyphMaxLevel > 0 ? "\(pelle.glyphMaxLevel)" : "1"
        let colorsOn = state.glyphTextColors
        let content = VStack(alignment: .center, spacing: 6) {
            if engine.pelleDoomed {
                Text("Glyph Rarity is set to \(pelle.glyphRarityText) and Level is capped at \(levelText).")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(GameColor.pelle.readableOnDark())
            }

            Text("Currently active Glyph effects:")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            // GlyphSetName line — type-colored + halo. Hidden when no glyphs
            // (set name == "Void") and there's nothing useful to convey.
            if !state.setName.isEmpty {
                let setColor = Color(cssColor: state.setNameColor).readableOnDark()
                Text(state.setName)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(colorsOn ? setColor : .white)
                    .glyphTextHalo(color: setColor, enabled: colorsOn)
            }

            // Unique-glyph notice — "You cannot have more than one X or Y..."
            if state.hasEffarig || state.hasReality {
                uniqueGlyphNotice(hasEffarig: state.hasEffarig,
                                  hasReality: state.hasReality,
                                  colorsOn: colorsOn)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.currentEffects.contains(where: { $0.isCapped }) {
                // Only the word "Italic" is itself italic — it demonstrates
                // the style applied to capped effects below. Web
                // `CurrentGlyphEffects.vue:108`.
                Text("\(Text("Italic").italic()) effects have been slightly reduced due to a softcap")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if state.currentEffects.isEmpty {
                Text("None (equip Glyphs to get their effects)")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.currentEffects) { effect in
                    let effColor = Color(cssColor: effect.typeColor).readableOnDark()
                    // Web `CurrentGlyphEffect.vue` colors the WHOLE line in
                    // the type color with a halo. § markers from JS carry
                    // no per-run color any more (we dropped the green value
                    // highlight) — strip them before rendering.
                    Text(effect.description.replacingOccurrences(of: "§", with: ""))
                        .font(.caption.monospacedDigit())
                        .italic(effect.isCapped)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(colorsOn ? effColor : .white)
                        .glyphTextHalo(color: effColor, enabled: colorsOn)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            // Pelle chaos line — only when special-effect milestone unlocked
            // AND there are equipped glyphs (otherwise the description is
            // just the generic placeholder).
            if engine.pelleDoomed
                && pelle.specialGlyphEffectUnlocked
                && !state.currentEffects.isEmpty
                && !pelle.specialGlyphEffectText.isEmpty {
                Text(pelle.specialGlyphEffectText)
                    .font(.caption.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(GameColor.pelle.readableOnDark())
                    .padding(.top, 2)
            }
        }

        if isWide {
            ScrollView {
                content.frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxHeight: 260)
        } else {
            content.frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Web `CurrentGlyphEffects.uniqueGlyphText` — singular/plural form, with
    /// each glyph-type name colored in its border color. Reality color
    /// animation deferred (we use the static `GameColor.reality`).
    private func uniqueGlyphNotice(hasEffarig: Bool, hasReality: Bool, colorsOn: Bool) -> Text {
        var parts: [Text] = []
        if hasEffarig {
            let c = GameColor.effarig.readableOnDark()
            parts.append(Text("Effarig").foregroundStyle(colorsOn ? c : .white))
        }
        if hasReality {
            let c = GameColor.reality.readableOnDark()
            parts.append(Text("Reality").foregroundStyle(colorsOn ? c : .white))
        }
        let pluralSuffix = parts.count > 1 ? " each." : "."
        var result = Text("You cannot have more than one ")
        for (i, p) in parts.enumerated() {
            if i > 0 { result = Text("\(result)\(Text(" or "))") }
            result = Text("\(result)\(p)")
        }
        result = Text("\(result)\(Text(" Glyph equipped" + pluralSuffix))")
        return result
    }

    private var sacrificeTotalsView: some View {
        VStack(alignment: .center, spacing: 8) {
            if engine.pelleDoomed {
                // Web `SacrificedGlyphs.vue` lines 121-125 + 178-183 — under
                // doom we replace the drop-zone help with the disabled notice,
                // suppress the Altered Glyphs section (per Q6b), and show the
                // "all boosts disabled" footer beneath the header.
                Text("You cannot sacrifice Glyphs while Doomed.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GameColor.pelle.readableOnDark())
                    .fixedSize(horizontal: false, vertical: true)

                Text("Glyph Sacrifice Boosts:")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Text("All boosts from Glyph Sacrifice are disabled while Doomed, including changes to effects due to Altered Glyphs.")
                    .font(.caption)
                    .foregroundStyle(GameColor.pelle.readableOnDark())
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Drop-zone help text (web `SacrificedGlyphs.vue:126-130`,
                // shortened — iOS has no shift-click/Ctrl ergonomics).
                Text("Drag Glyphs here to Sacrifice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if state.sacrificeUnlocked {
                    sacrificeDropZone
                }

                // Altered Glyphs section — only when Ra-unlocked and not doomed.
                if state.alterationsUnlocked {
                    alteredGlyphsCard
                }

                Text("Glyph Sacrifice Boosts:")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                if state.sacrificeTotals.isEmpty {
                    Text("You haven't Sacrificed any Glyphs yet!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Teresa multiplier line — web gates on
                    // `anySacrifices && teresaMult > 1 && !doomed`.
                    if state.teresaMult > 1 && !state.lastMachinesText.isEmpty {
                        // Pre-formatted JS-side via `formatX(teresaMult, 2, 2)` —
                        // a Double `5.15e46` rendered by Swift's `%.2f` would
                        // produce the raw 47-digit string.
                        Text("Glyph sacrifice values are multiplied by \(state.teresaMultText); Teresa was last done at \(state.lastMachinesText).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if state.realityGlyphSeen {
                            Text("Reality Glyphs are unaffected by this multiplier and have no altered effects.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    sacrificeRowsView
                }
            }
        }
    }

    @ViewBuilder
    private var sacrificeRowsView: some View {
        let colorsOn = state.glyphTextColors
        ForEach(state.sacrificeTotals) { sac in
            // Glyph colors come from JS as either #hex or rgb(...) (the
            // Reality glyph's color is animated via interpolated rgb).
            // `readableOnDark` brightens any hue that would otherwise
            // disappear against the dark panel background.
            let baseColor = Color(cssColor: sac.color).readableOnDark()
            let fg: Color = colorsOn ? baseColor : .white
            VStack(alignment: .center, spacing: 2) {
                // Web `TypeSacrifice.vue:95-108` — symbol + amount sit on one
                // centered line, description directly below in the same color.
                Text("\(Text(sac.symbol).font(.body.weight(.semibold)))\(Text(" \(sac.amount)").font(.callout.monospacedDigit()))")
                    .foregroundStyle(fg)
                    .glyphTextHalo(color: baseColor, enabled: colorsOn)
                if !sac.boost.isEmpty {
                    Text(sac.boost)
                        .font(.caption.monospacedDigit())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(fg)
                        .glyphTextHalo(color: baseColor, enabled: colorsOn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
        }
    }

    /// Altered Glyphs collapsible card — mirrors web `SacrificedGlyphs.vue:131-157`.
    /// Header toggles `player.options.hideAlterationEffects`; collapsed state
    /// shows just the italic "Details hidden, click to unhide" hint.
    @ViewBuilder
    private var alteredGlyphsCard: some View {
        let isHidden = state.hideAlteration
        let addColor = Color(cssColor: state.additionThresholdColor).readableOnDark()
        let empColor = Color(cssColor: state.empowermentThresholdColor).readableOnDark()
        let bstColor = Color(cssColor: state.boostingThresholdColor).readableOnDark()
        let colorsOn = state.glyphTextColors
        VStack(alignment: .leading, spacing: 6) {
            Button {
                engine.toggleAlteredGlyphDetails()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isHidden ? "plus.square" : "minus.square")
                        .imageScale(.small)
                    Text("Altered Glyphs").fontWeight(.semibold)
                    Spacer()
                }
                .foregroundStyle(.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.caption)

            if isHidden {
                Text("(Details hidden, tap to unhide)")
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(.secondary)
            } else {
                Text("Glyph types will have one of their effects improved when their Glyph type's total sacrifice value is above:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(state.additionThresholdText) - an additional secondary effect")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(colorsOn ? addColor : .white)
                    .glyphTextHalo(color: addColor, enabled: colorsOn)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(state.empowermentThresholdText) - formula drastically improved")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(colorsOn ? empColor : .white)
                    .glyphTextHalo(color: empColor, enabled: colorsOn)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(state.boostingThresholdText) - a boost depending on Glyph Sacrifice")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(colorsOn ? bstColor : .white)
                    .glyphTextHalo(color: bstColor, enabled: colorsOn)
                    .fixedSize(horizontal: false, vertical: true)

                if !state.maxSacrificeText.isEmpty {
                    Text("All effects from Glyph Sacrifice can no longer be increased once they reach \(state.maxSacrificeText).")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var sacrificeDropZone: some View {
        // NOTE: previous version attached `.onDrop` directly to
        // `RoundedRectangle().strokeBorder(...)` — the stroked shape only
        // renders its outline, so the transparent interior rejected drops
        // even though the frame looked clickable. Wrapping in a ZStack with
        // a filled rectangle + explicit `.contentShape(Rectangle())` makes
        // the whole 44pt frame a valid drop target (same pattern as the
        // equip slots).
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(sacrificeDropTargeted ? Color.orange.opacity(0.15) : Color.orange.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            sacrificeDropTargeted ? Color.orange : Color.orange.opacity(0.5),
                            style: StrokeStyle(lineWidth: 2, dash: sacrificeDropTargeted ? [] : [8, 4])
                        )
                )
            Text("Drag Glyphs here to Sacrifice")
                .font(.caption)
                .foregroundStyle(.orange.opacity(sacrificeDropTargeted ? 1 : 0.75))
        }
        .frame(height: 44)
        .contentShape(Rectangle())
        .onDrop(of: [.text], isTargeted: $sacrificeDropTargeted) { _ in
            guard let drag = draggedGlyph, !drag.isEquipped else {
                endDragSession()
                return false
            }
            engine.sacrificeGlyph(drag.glyphId)
            endDragSession()
            return true
        }
    }

    // MARK: - Controls

    @State private var showUndoConfirm = false

    private var controlsSection: some View {
        VStack(spacing: 8) {
            // Undo last equip — gated on TeresaUnlocks.undo + undo stack + free slot
            if state.canUndoGlyph {
                GameButton(borderColor: GameColor.badPink, isEnabled: true) {
                    showUndoConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Undo Last Equipped Glyph")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GameColor.badPink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .alert("Undo Equipped Glyph", isPresented: $showUndoConfirm) {
                    Button("Undo", role: .destructive) { engine.undoGlyph() }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("The last equipped Glyph will be removed. Reality will be reset, but Antimatter, IP, EP, Dilation Upgrades, Time Theorems, and EC completions will be restored to when it was equipped.")
                }
            }

            // Respec toggle
            GameButton(
                borderColor: state.respec ? .orange : GameColor.reality,
                isEnabled: true
            ) {
                engine.toggleGlyphRespec()
            } label: {
                Text(state.respec ? "Glyphs will unequip on Reality" : "Unequip Glyphs on Reality")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(state.respec ? .orange : GameColor.reality)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            // Unequip destination toggle (web `EquippedGlyphs.vue`
            // "Unequip Glyphs to:" button). Controls where unequipped/respec'd
            // glyphs land — protected rows vs main inventory.
            GameButton(borderColor: GameColor.reality, isEnabled: true) {
                engine.toggleRespecIntoProtected()
            } label: {
                VStack(spacing: 1) {
                    Text("Unequip Glyphs to:")
                    Text(state.respecIntoProtected ? "Protected slots" : "Main inventory")
                        .fontWeight(.semibold)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(GameColor.reality)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            // Sacrifice Type — Ra Effarig pet lv 2 unlocks Glyph Alchemy,
            // which makes the trash mode meaningful (refining yields alchemy
            // resources instead of raw sacrifice). Mirrors web's
            // `GlyphRejectionPanel` sidebar tab.
            if engine.glyphAlchemyUnlocked {
                sacrificeTypeCard
            }
        }
    }

    /// Three-way picker for `player.reality.glyphs.filter.trash`:
    /// 0 = Sacrifice, 1 = Refine, 2 = Refine to cap, then sacrifice.
    private var sacrificeTypeCard: some View {
        let options: [(Int, String, String)] = [
            (0, "Always sacrifice",        "flame.fill"),
            (1, "Always refine",           "flask.fill"),
            (2, "Refine to cap,\nthen sacrifice", "arrow.triangle.branch")
        ]
        let current = engine.effarigGlyphFilter?.trashMode ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Text("Sacrifice Type")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameColor.reality)
            Text("Behavior for deleted and filtered Glyphs:")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 8) {
                ForEach(options, id: \.0) { (value, label, icon) in
                    let isSelected = current == value
                    Button {
                        engine.setGlyphFilterMode(which: "trash", value: value)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: icon)
                                .font(.system(size: 16))
                            Text(label)
                                .font(.caption2.weight(.medium))
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(isSelected ? Color.black : GameColor.reality)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color(red: 0.82, green: 0.95, blue: 0.78) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(GameColor.reality, lineWidth: 1.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(GameColor.reality.opacity(0.5), lineWidth: 1)
                )
        )
        .onAppear { engine.loadGlyphFilter() }
    }

    // MARK: - Inventory Management Card

    private var inventoryManagementCard: some View {
        let compact = metrics.isCompact
        let buttonFont: Font = compact ? .subheadline.weight(.medium) : .caption.weight(.medium)
        let buttonPadV: CGFloat = compact ? 10 : 10
        let stepperSize: CGFloat = compact ? 36 : 34
        let stepperWidth: CGFloat = compact ? 44 : 40
        let stepperFont: Font = compact ? .body.weight(.bold) : .subheadline.weight(.bold)

        return VStack(alignment: .leading, spacing: compact ? 10 : 8) {
            Text("Inventory")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            VStack(spacing: compact ? 8 : 6) {
                if compact {
                    // Full-width stacked buttons on iPhone
                    sortButton("Sort by Level", font: buttonFont, padV: buttonPadV) { engine.sortGlyphsByLevel() }
                    sortButton("Sort by Power", font: buttonFont, padV: buttonPadV) { engine.sortGlyphsByPower() }
                    sortButton("Sort by Effect", font: buttonFont, padV: buttonPadV) { engine.sortGlyphsByEffect() }
                    if state.hasGlyphFilter {
                        sortButton("Sort by Score", font: buttonFont, padV: buttonPadV) { engine.sortGlyphsByScore() }
                    }
                    sortButton("Collapse Empty Slots", font: buttonFont, padV: buttonPadV) { engine.collapseEmptyGlyphSlots() }
                } else {
                    // 2×2 (or 3×2 with filter) grid on iPad
                    HStack(spacing: 6) {
                        sortButton("Sort by Level", font: buttonFont, padV: buttonPadV) { engine.sortGlyphsByLevel() }
                        sortButton("Sort by Power", font: buttonFont, padV: buttonPadV) { engine.sortGlyphsByPower() }
                    }
                    if state.hasGlyphFilter {
                        HStack(spacing: 6) {
                            sortButton("Sort by Effect", font: buttonFont, padV: buttonPadV) { engine.sortGlyphsByEffect() }
                            sortButton("Sort by Score", font: buttonFont, padV: buttonPadV) { engine.sortGlyphsByScore() }
                        }
                        sortButton("Collapse Empty", font: buttonFont, padV: buttonPadV) { engine.collapseEmptyGlyphSlots() }
                    } else {
                        HStack(spacing: 6) {
                            sortButton("Sort by Effect", font: buttonFont, padV: buttonPadV) { engine.sortGlyphsByEffect() }
                            sortButton("Collapse Empty", font: buttonFont, padV: buttonPadV) { engine.collapseEmptyGlyphSlots() }
                        }
                    }
                }

                // Protected rows
                HStack(spacing: compact ? 10 : 6) {
                    Text("Protected: \(state.protectedRows) row\(state.protectedRows == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        engine.removeGlyphProtectedRow()
                    } label: {
                        Image(systemName: "minus")
                            .font(stepperFont)
                            .foregroundStyle(state.protectedRows > 0 ? .white : .gray.opacity(0.4))
                            .frame(width: stepperWidth, height: stepperSize)
                            .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: compact ? 8 : 4))
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(state.protectedRows > 0)

                    Button {
                        engine.addGlyphProtectedRow()
                    } label: {
                        Image(systemName: "plus")
                            .font(stepperFont)
                            .foregroundStyle(state.protectedRows < state.totalSlots / 10 - 1 ? .white : .gray.opacity(0.4))
                            .frame(width: stepperWidth, height: stepperSize)
                            .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: compact ? 8 : 4))
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(state.protectedRows < state.totalSlots / 10 - 1)
                }
                #if DEBUG
                sortButton("Give 4× Each Type (Lvl 10000, Max Rarity)", font: buttonFont, padV: buttonPadV) {
                    // Single eval handles all types — cheaper than 24 separate
                    // jsAsync hops, and lets the type list be conditional on
                    // whether Effarig Glyphs are unlocked. For each glyph we
                    // crank strength to 3.5 (100% rarity per
                    // strengthToRarity(x) = (x-1)*100/2.5) and OR all valid
                    // effect bits for that type so every effect is active.
                    engine.devCommand("""
                        (function() {
                            var types = ["power","infinity","replication","time","dilation"];
                            // Effarig Glyphs unlock after completing Effarig's
                            // Reality stage (EffarigUnlock.reality).
                            if (typeof EffarigUnlock !== 'undefined'
                                && EffarigUnlock.reality
                                && EffarigUnlock.reality.isUnlocked) {
                                types.push("effarig");
                            }
                            types.forEach(function(t) {
                                var glyphType = GlyphTypes[t];
                                if (!glyphType) return;
                                var allEffects = 0;
                                for (var i = 0; i < glyphType.effects.length; i++) {
                                    allEffects |= (1 << glyphType.effects[i].bitmaskIndex);
                                }
                                for (var n = 0; n < 4; n++) {
                                    if (GameCache.glyphInventorySpace.value <= 0) return;
                                    var g = GlyphGenerator.randomGlyph(
                                        { actualLevel: 50000, rawLevel: 50000 },
                                        undefined,
                                        t
                                    );
                                    g.strength = 3.5;
                                    g.effects = allEffects;
                                    Glyphs.addToInventory(g);
                                }
                            });
                        })();
                        """)
                }
                #endif
            }
        }
        .padding(compact ? 14 : 10)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Auto Glyph Arrangement Card

    private var autoArrangementCard: some View {
        let compact = metrics.isCompact
        let buttonFont: Font = compact ? .subheadline.weight(.medium) : .caption.weight(.medium)
        let buttonPadV: CGFloat = compact ? 10 : 10
        let headerFont: Font = compact ? .subheadline.weight(.bold) : .subheadline.weight(.bold)
        let toggleFont: Font = compact ? .subheadline : .subheadline

        let modes: [String] = {
            var m = ["None", "Level", "Power", "Effect"]
            if state.hasGlyphFilter { m.append("Score") }
            return m
        }()
        let modeIdx = min(max(state.autoSortMode, 0), modes.count - 1)

        return VStack(alignment: .leading, spacing: compact ? 10 : 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto Glyph Arrangement")
                    .font(headerFont)
                    .foregroundStyle(.secondary)
                Text("Applies after every Reality")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(.bottom, 2)

            VStack(spacing: compact ? 8 : 6) {
                sortButton("Auto-sort Mode: \(modes[modeIdx])", font: buttonFont, padV: buttonPadV) {
                    let next = (modeIdx + 1) % modes.count
                    engine.setGlyphAutoSort(next)
                }

                Toggle(isOn: Binding(
                    get: { state.autoCollapse },
                    set: { engine.setGlyphAutoCollapse($0) }
                )) {
                    Text("Auto-collapse space")
                        .font(toggleFont)
                        .foregroundStyle(.white)
                }
                .tint(GameColor.reality)

                if state.autoAutoCleanUnlocked {
                    Toggle(isOn: Binding(
                        get: { state.autoAutoClean },
                        set: { engine.setGlyphAutoAutoClean($0) }
                    )) {
                        Text("Auto-purge on Realities")
                            .font(toggleFont)
                            .foregroundStyle(.white)
                    }
                    .tint(GameColor.reality)

                    Toggle(isOn: Binding(
                        get: { state.applyFilterToPurge },
                        set: { engine.setGlyphApplyFilterToPurge($0) }
                    )) {
                        Text("Never Auto-purge Glyphs accepted by filter")
                            .font(toggleFont)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tint(GameColor.reality)
                }
            }
        }
        .padding(compact ? 14 : 10)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Remove Weaker Glyphs Card

    private var removeWeakerCard: some View {
        let compact = metrics.isCompact
        let buttonFont: Font = compact ? .subheadline.weight(.medium) : .caption.weight(.medium)
        let buttonPadV: CGFloat = compact ? 10 : 10
        let headerFont: Font = compact ? .subheadline.weight(.bold) : .subheadline.weight(.bold)
        let verb = state.isRefining ? "Refine" : (state.sacrificeUnlocked ? "Sacrifice" : "Delete")

        return VStack(alignment: .leading, spacing: compact ? 10 : 8) {
            Text("Remove weaker Glyphs")
                .font(headerFont)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            VStack(spacing: compact ? 8 : 6) {
                sortButton("Purge Glyphs", font: buttonFont, padV: buttonPadV) { engine.purgeGlyphs() }
                sortButton("Harsh Purge Glyphs", font: buttonFont, padV: buttonPadV) { engine.harshPurgeGlyphs() }
                sortButton("\(verb) all unprotected Glyphs", font: buttonFont, padV: buttonPadV) { engine.deleteAllUnprotectedGlyphs() }
                if state.hasGlyphFilter {
                    sortButton("\(verb) all Glyphs rejected by filtering", font: buttonFont, padV: buttonPadV) { engine.deleteAllRejectedGlyphs() }
                }
            }
        }
        .padding(compact ? 14 : 10)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sortButton(_ label: String, font: Font, padV: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, padV)
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: metrics.isCompact ? 8 : 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inventory Grid

    @ViewBuilder
    private func inventorySection(tileSize: CGFloat, columnCount: Int = 10) -> some View {
        GlyphInventoryGrid(
            tileSize: tileSize,
            columnCount: columnCount,
            isCompact: metrics.isCompact,
            inventory: state.inventory,
            totalSlots: state.totalSlots,
            protectedRows: state.protectedRows,
            sacrificeUnlocked: state.sacrificeUnlocked,
            hasGlyphFilter: state.hasGlyphFilter,
            engine: engine,
            draggedGlyph: $draggedGlyph,
            tooltipGlyph: $tooltipGlyph,
            showInventoryMenu: $showInventoryMenu,
            onBeginDrag: beginDragSession,
            onEndDrag: endDragSession
        )
        .equatable()
    }
}

// MARK: - Inventory Grid (Equatable)

/// 120-cell `LazyVGrid` extracted from `GlyphsTabContent.inventorySection`
/// so the parent's per-tick body re-eval doesn't rebuild the grid + 120
/// `GlyphComponent` modifier chains. Equatable on the visible-state inputs;
/// bindings (drag state, tooltip target, menu flag) are excluded — they
/// drive sheet/dialog presentation handled by the parent and don't affect
/// what this grid renders.
private struct GlyphInventoryGrid: View, Equatable {
    let tileSize: CGFloat
    let columnCount: Int
    let isCompact: Bool
    let inventory: [GlyphInfo]
    let totalSlots: Int
    let protectedRows: Int
    let sacrificeUnlocked: Bool
    let hasGlyphFilter: Bool
    let engine: GameEngine
    @Binding var draggedGlyph: GlyphDragInfo?
    @Binding var tooltipGlyph: GlyphSheetContext?
    @Binding var showInventoryMenu: Bool
    let onBeginDrag: (GlyphDragInfo) -> NSItemProvider
    let onEndDrag: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.tileSize == rhs.tileSize
            && lhs.columnCount == rhs.columnCount
            && lhs.isCompact == rhs.isCompact
            && lhs.inventory == rhs.inventory
            && lhs.totalSlots == rhs.totalSlots
            && lhs.protectedRows == rhs.protectedRows
            && lhs.sacrificeUnlocked == rhs.sacrificeUnlocked
            && lhs.hasGlyphFilter == rhs.hasGlyphFilter
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(tileSize), spacing: 4), count: columnCount)
        let protectedSlots = protectedRows * 10
        // Pre-index by slot once per body eval — the grid does 120 lookups per
        // body re-eval; `first(where:)` would make that O(N²).
        let bySlot: [Int: GlyphInfo] = Dictionary(
            uniqueKeysWithValues: inventory.map { ($0.idx, $0) }
        )

        VStack(spacing: 6) {
            Text(isCompact ? "Tap glyph for actions · Hold empty slot for options" : "Drag to equip, sacrifice, or rearrange")
                .font(.caption2)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<totalSlots, id: \.self) { slotIdx in
                    let glyph = bySlot[slotIdx]
                    let isProtected = slotIdx < protectedSlots

                    if let glyph {
                        GlyphComponent(glyph: glyph, size: tileSize)
                            .equatable()
                            .onTapGesture {
                                tooltipGlyph = GlyphSheetContext(glyph: glyph, sacrificeUnlocked: sacrificeUnlocked, hasProtectedRows: protectedRows > 0)
                            }
                            .onDrag {
                                onBeginDrag(GlyphDragInfo(glyphId: glyph.id, isEquipped: false, slotIndex: slotIdx))
                            }
                    } else {
                        // Empty slot — long-press for inventory menu
                        RoundedRectangle(cornerRadius: tileSize * 0.12)
                            .fill(isProtected ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
                            .frame(width: tileSize, height: tileSize)
                            .contentShape(Rectangle())
                            .onLongPressGesture {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                showInventoryMenu = true
                            }
                    }
                }
            }
            .contentShape(Rectangle())  // include inter-cell spacing gaps in drop target
            .onDrop(of: [.text], delegate: InventoryGridDropDelegate(
                tileSize: tileSize,
                columnCount: columnCount,
                totalSlots: totalSlots,
                inventory: inventory,
                draggedGlyph: draggedGlyph,
                moveAction: { glyphId, slot in engine.moveGlyphToSlot(glyphId, targetSlot: slot) },
                endDrag: onEndDrag
            ))
        }
        .confirmationDialog("Inventory", isPresented: $showInventoryMenu) {
            Button("Sort by Level") { engine.sortGlyphsByLevel() }
            Button("Sort by Power") { engine.sortGlyphsByPower() }
            Button("Sort by Effect") { engine.sortGlyphsByEffect() }
            if hasGlyphFilter {
                Button("Sort by Score") { engine.sortGlyphsByScore() }
            }
            Button("Collapse Empty Slots") { engine.collapseEmptyGlyphSlots() }
            if protectedRows < totalSlots / 10 - 1 {
                Button("Add Protected Rows") { engine.addGlyphProtectedRow() }
            }
            if protectedRows > 0 {
                Button("Remove Protected Rows") { engine.removeGlyphProtectedRow() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Inventory Grid Drop Delegate

/// Handles drops anywhere on the inventory grid. Uses the grid cell directly
/// under the drop point as the target — `Glyphs.moveToSlot` on the JS side
/// swaps with the occupant if the target is already full, so we don't need
/// to redirect to an empty slot.
private struct InventoryGridDropDelegate: DropDelegate {
    let tileSize: CGFloat
    let columnCount: Int
    let totalSlots: Int
    let inventory: [GlyphInfo]
    let draggedGlyph: GlyphDragInfo?
    let moveAction: (Int, Int) -> Void   // (glyphId, targetSlot)
    let endDrag: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let drag = draggedGlyph, !drag.isEquipped else {
            endDrag()
            return false
        }

        guard let target = targetSlot(at: info.location), target != drag.slotIndex else {
            endDrag()
            return false
        }

        moveAction(drag.glyphId, target)
        endDrag()
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    /// Maps a drop point to the grid slot directly under it. Occupancy
    /// doesn't matter — the JS `Glyphs.moveToSlot` swaps when needed.
    private func targetSlot(at point: CGPoint) -> Int? {
        let cellSpan = tileSize + 4  // tile width + grid spacing
        guard point.x >= 0, point.y >= 0 else { return nil }
        let col = min(max(Int(point.x / cellSpan), 0), columnCount - 1)
        let row = max(Int(point.y / cellSpan), 0)
        let maxRow = (totalSlots - 1) / columnCount
        let clampedRow = min(row, maxRow)
        let slot = clampedRow * columnCount + col
        guard slot >= 0, slot < totalSlots else { return nil }
        return slot
    }
}

// MARK: - Equipped Glyphs Sheet
//
// All-equipped summary opened by tapping any equipped glyph slot. Web parity
// with `Modal.glyphShowcasePanel` ([EquippedGlyphs.vue:139-143] showEquippedModal).
// Cards now use the shared `GlyphRichCard` (mirroring web's `GlyphTooltip.vue`)
// instead of the previous bespoke `equippedGlyphCard`.

private struct EquippedGlyphsSheet: View {
    let glyphs: [GlyphInfo]
    let setName: String
    @Environment(\.dismiss) private var dismiss

    private var mainColor: Color {
        guard let first = glyphs.first else { return .secondary }
        var counts: [String: (count: Int, color: String)] = [:]
        for g in glyphs {
            let entry = counts[g.type] ?? (0, g.typeColor)
            counts[g.type] = (entry.count + 1, g.typeColor)
        }
        let top = counts.max(by: { $0.value.count < $1.value.count })
        return Color(hex: top?.value.color ?? first.typeColor)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Equipped Glyphs")
                        .font(.title2.weight(.bold))

                    if !setName.isEmpty {
                        Text(setName)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(mainColor)
                            .italic()
                    }

                    if glyphs.isEmpty {
                        Text("No glyphs equipped")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 32)
                    } else {
                        ForEach(glyphs) { glyph in
                            GlyphRichCard(glyph: glyph)
                                .equatable()
                        }
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Peek Glyphs Detail Sheet
//
// Upcoming-glyph preview, opened from `glyphPeekSection` in the main tab.
// Cards use the shared `GlyphRichCard`, same layout as the equipped summary.
// Header label takes web's "Projected" qualifier (`gainedGlyphLevel().actualLevel`
// can shift before Reality fires).

private struct PeekGlyphsSheet: View {
    let glyphs: [GlyphInfo]
    let level: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Potential Glyphs for this Reality")
                        .font(.title2.weight(.bold))

                    if level > 0 {
                        Text("Projected Glyph Level: \(level)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(GameColor.reality)
                    }

                    ForEach(glyphs) { glyph in
                        GlyphRichCard(glyph: glyph)
                            .equatable()
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Glyph Tooltip Sheet (inventory glyph tap → detail + actions)
//
// Single-glyph view shown on inventory tap (`tooltipGlyph` state in main tab).
// Body uses the shared `GlyphRichCard`; action buttons (Equip / Sacrifice /
// Move to Protected Row) sit pinned below. Equipped glyphs no longer route
// here — they open `EquippedGlyphsSheet` instead, matching web parity.

private struct GlyphTooltipSheet: View {
    let glyph: GlyphInfo
    var onEquip: (() -> Void)? = nil
    var onSacrifice: (() -> Void)? = nil
    var onProtect: (() -> Void)? = nil
    var onSetMusicGlyph: (() -> Void)? = nil
    var onResetCosmetic: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Outer split: scrollable card on top, action buttons pinned at the
        // bottom outside the scroll region so they're always reachable on
        // glyphs with long effect lists (Effarig post-Ra `glyphEffectCount`).
        VStack(spacing: 12) {
            ScrollView {
                GlyphRichCard(glyph: glyph)
                    .equatable()
                    .padding(.bottom, 4)
            }

            actionButtons
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Action buttons pinned at the bottom (outside the ScrollView so they
    /// stay reachable regardless of how long the effect list is).
    @ViewBuilder
    private var actionButtons: some View {
            // Action buttons — always shown so tap works on both iPhone and iPad
            if onEquip != nil || onSacrifice != nil || onProtect != nil
                || onSetMusicGlyph != nil || onResetCosmetic != nil {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        if let onEquip {
                            GameButton(borderColor: GameColor.reality, isEnabled: true) {
                                onEquip()
                                dismiss()
                            } label: {
                                Text("Equip")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(GameColor.reality)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                        }
                        if let onSacrifice {
                            GameButton(borderColor: .orange, isEnabled: true) {
                                onSacrifice()
                                dismiss()
                            } label: {
                                Text("Sacrifice")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                        }
                    }
                    if let onProtect {
                        GameButton(borderColor: .white.opacity(0.6), isEnabled: true) {
                            onProtect()
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.shield")
                                Text("Move to Protected Row")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                    }
                    // Appearance (Teresa Music Glyph cosmetic). Set marks the glyph
                    // with the ♫ symbol + pink tint; Reset reverts to the default.
                    if onSetMusicGlyph != nil || onResetCosmetic != nil {
                        HStack(spacing: 10) {
                            if let onSetMusicGlyph {
                                GameButton(borderColor: Color(hex: "#FF80AB"), isEnabled: true) {
                                    onSetMusicGlyph()
                                    dismiss()
                                } label: {
                                    Text("♫ Music Glyph")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color(hex: "#FF80AB"))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                            }
                            if let onResetCosmetic {
                                GameButton(borderColor: .white.opacity(0.6), isEnabled: true) {
                                    onResetCosmetic()
                                    dismiss()
                                } label: {
                                    Text("Reset Appearance")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.8))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                }
                            }
                        }
                    }
                }
            }
    }
}

// MARK: - Glyph instability notice

/// Quiet flavor banner shown once the best Reality glyph level exceeds 800
/// (mirrors web `GlyphsTab.vue` v-if="showInstability"). Two soft thresholds
/// at `instabilityThreshold` (default 1000) and `hyperInstabilityThreshold`
/// (instability + 3000) — the cost of pushing levels higher.
private struct GlyphInstabilityNotice: View {
    let instabilityThreshold: Int
    let hyperInstabilityThreshold: Int

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
    private func fmt(_ n: Int) -> String { Self.formatter.string(from: NSNumber(value: n)) ?? String(n) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Glyphs are becoming unstable.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Glyph levels higher than \(fmt(instabilityThreshold)) are harder to reach.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("This effect is even stronger above level \(fmt(hyperInstabilityThreshold)).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pelle Glyphs disabled banner

/// Crimson banner explaining that glyph equipping is locked while doomed,
/// pointing the player at the Pelle upgrade that re-enables it.
private struct PelleGlyphsDisabledBanner: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Glyph equipping is disabled while Doomed.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameColor.pelle.readableOnDark())
            Text("Buy the \"Re-enable Glyph equipping\" Pelle upgrade to restore it.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10).padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(GameColor.pelle, lineWidth: 1))
        )
    }
}
