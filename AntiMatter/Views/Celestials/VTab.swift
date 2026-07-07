//
//  VTab.swift
//  AntiMatter
//
//  Celestial V — "The Celestial of Achievements".
//  Pre-unlock: 6 requirement progress bars + unlock button.
//  Post-unlock: 9 V-Achievements in honeycomb hex grid, V's Reality run
//  button in center hex, 6 milestone unlocks, Space Theorems, goal reduction.
//

import SwiftUI

// MARK: - Hexagon Shape

/// Pointy-top regular hexagon. Width W, Height H = W * 2/√3 ≈ W * 1.1547.
/// Internal so `VRunButton` can share it.
struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cy = rect.midY
        // Pointy-top hex: 6 vertices starting from top center, going clockwise.
        // Top and bottom are at cy ± h/2; the 4 side vertices are at cy ± h/4.
        var path = Path()
        path.move(to: CGPoint(x: cx, y: cy - h / 2))                 // top
        path.addLine(to: CGPoint(x: cx + w / 2, y: cy - h / 4))      // top-right
        path.addLine(to: CGPoint(x: cx + w / 2, y: cy + h / 4))      // bottom-right
        path.addLine(to: CGPoint(x: cx, y: cy + h / 2))               // bottom
        path.addLine(to: CGPoint(x: cx - w / 2, y: cy + h / 4))      // bottom-left
        path.addLine(to: CGPoint(x: cx - w / 2, y: cy - h / 4))      // top-left
        path.closeSubpath()
        return path
    }
}

struct VTab: View {
    let engine: GameEngine

    var body: some View {
        VTabContent(engine: engine)
    }
}

private struct VTabContent: View {
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebar
    @Environment(\.layoutMetrics) private var metrics
    @Environment(\.scenePhase) private var scenePhase
    @State private var showHistory = false
    /// Actual available width of the honeycomb grid, measured via GeometryReader.
    /// Drives `honeycombHeight` so the reserved frame matches real hex sizes —
    /// without this, the height was estimated from a fixed 340pt (iPhone) /
    /// 650pt (iPad) which overflowed on wider devices (Pro Max) and caused the
    /// "V-Achievements can only be completed…" paragraph to overlap the bottom
    /// row of hexes.
    @State private var honeycombActualWidth: CGFloat = 0

    private var v: VState { engine.gameState.celestials.v }

    /// True only when V is the visible subtab AND the scene is active.
    /// Drives `VRunButton.isActive` so the running-state line-burst
    /// KeyframeAnimators tear down on backgrounding or subtab navigation.
    private var isVisible: Bool {
        sidebar?.activeSubtab == .v && scenePhase == .active
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Title row with quote-history button (matches Teresa/Effarig/
                // Enslaved/Ra pattern so every celestial surfaces its quote log).
                HStack {
                    Spacer()
                    Text("V — The Celestial of Achievements")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(GameColor.v)
                    Spacer()
                    Button {
                        engine.loadQuoteHistory(for: "v")
                        showHistory = true
                    } label: {
                        Image(systemName: "quote.bubble")
                            .font(.callout)
                            .foregroundStyle(GameColor.v)
                            .padding(8)
                            .background(GameColor.v.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                if !v.isUnlocked {
                    preUnlockView
                } else {
                    postUnlockView
                }

                #if DEBUG
                debugSection
                #endif
            }
            .padding()
        }
        .sheet(isPresented: $showHistory) {
            CelestialQuoteHistoryView(celestialKey: "v", engine: engine)
        }
    }

    // MARK: - Pre-unlock

    private var preUnlockView: some View {
        VStack(spacing: 12) {
            Text("Meet all of the following requirements simultaneously to unlock V")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            ForEach(v.unlockRequirements) { req in
                VUnlockRequirementRow(req: req)
                    .equatable()
            }

            GameButton(theme: .v, isEnabled: v.canUnlockCelestial) {
                engine.unlockV()
            } label: {
                // Web VTab.vue:179-180 pulls these from the unlock config.
                VStack(spacing: 2) {
                    Text(v.unlockButtonDescription.isEmpty
                         ? "Unlock V, The Celestial of Achievements"
                         : v.unlockButtonDescription)
                        .font(.subheadline.weight(.bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if !v.unlockButtonReward.isEmpty {
                        Text(v.unlockButtonReward)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Post-unlock

    private var postUnlockView: some View {
        VStack(spacing: 16) {
            // Hard V toggle + info (when Ra unlocked V.isFlipped)
            if v.isFlipped {
                hardVControls
                cursedGlyphButton
            }

            // Perk Points (for goal reduction)
            if v.showReduction {
                Text("You have \(v.ppAvailable) Perk Points")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            // V-Achievements honeycomb
            honeycombGrid

            // Static info paragraph (VTab.vue:299-301) — explains permanence.
            Text("V-Achievements can only be completed within V's Reality, but are permanent and do not reset upon leaving and re-entering the Reality.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Space Theorems readout — Vue VTab.vue:302-310 ties the gain
            // description into the same paragraph; gates the extra Time-Study
            // / Automator copy on `!isDoomed`.
            VStack(spacing: 2) {
                Text("You have \(v.spaceTheorems) V-Achievements done.")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(GameColor.v)
                if !engine.pelleDoomed {
                    Text("You gain 1 Space Theorem for each completion, allowing you to purchase Time Studies which are normally locked.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Space Theorems can also be used as a Currency in the Automator.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Milestones
            milestonesSection
        }
    }

    // MARK: - Honeycomb grid

    /// Cells for the 9-position honeycomb. Ordering matches web hex layout.
    private enum GridCell {
        case achievement(VAchievementInfo)
        case runButton
        case empty
    }

    private var gridCells: [GridCell] {
        let achs = v.achievements
        let showHard = v.isFlipped && v.wantsFlipped

        if showHard {
            let hardAchs = achs.filter { $0.isHard }
            return [
                hardAchs.count > 0 ? .achievement(hardAchs[0]) : .empty,
                .empty, .empty,
                .empty, .runButton,
                hardAchs.count > 1 ? .achievement(hardAchs[1]) : .empty,
                hardAchs.count > 2 ? .achievement(hardAchs[2]) : .empty,
                .empty, .empty
            ]
        } else {
            let normalAchs = achs.filter { !$0.isHard }
            return [
                normalAchs.count > 0 ? .achievement(normalAchs[0]) : .empty,
                normalAchs.count > 1 ? .achievement(normalAchs[1]) : .empty,
                .empty,
                normalAchs.count > 5 ? .achievement(normalAchs[5]) : .empty,
                .runButton,
                normalAchs.count > 2 ? .achievement(normalAchs[2]) : .empty,
                normalAchs.count > 4 ? .achievement(normalAchs[4]) : .empty,
                normalAchs.count > 3 ? .achievement(normalAchs[3]) : .empty,
                .empty
            ]
        }
    }

    /// Compute hex dimensions from available width.
    /// iPhone: divides by 3.6 (larger hexes, tighter margins — the empty cells
    /// in positions 2 and 8 absorb the overhang so visible content stays on screen).
    /// iPad: capped at 160pt per hex.
    private static func hexLayout(availableWidth: CGFloat, spacing: CGFloat, isCompact: Bool)
        -> (hexWidth: CGFloat, hexHeight: CGFloat, colStep: CGFloat, rowStep: CGFloat, stagger: CGFloat, row1X: CGFloat) {
        // Divisor 3.6 on iPhone gives ~95pt hexes on a 360pt-wide area — enough
        // for readable text while keeping the visible 2-3-2 pattern on screen.
        // The invisible empty cells in the top-right and bottom-right may extend
        // slightly beyond bounds, which is fine since they're Color.clear.
        let divisor: CGFloat = isCompact ? 2.8 : 4
        let maxHex = (availableWidth - 3 * spacing) / divisor
        let hexWidth = isCompact ? maxHex : min(maxHex, 160)
        // Pointy-top hex tiles flush at h = w * 2/√3 ≈ 1.155. iPhone stretches
        // the hex vertically (~1.5×) so the description + reduction + record +
        // reward + Reduce button stack fits without minimumScaleFactor clipping
        // the bottom rows. The tiling math (rowStep = 0.75 × h, side vertices
        // at cy ± h/4) couples row spacing to h alone, so adjacent rows still
        // touch exactly at the side vertices regardless of the h:w ratio.
        let heightRatio: CGFloat = isCompact ? 1.5 : 2 / sqrt(3)
        let hexHeight = hexWidth * heightRatio
        let colStep = hexWidth + spacing
        let rowStep = hexHeight * 0.75
        let stagger = colStep / 2
        // Center the middle row; staggered rows start half a colStep to the right.
        let row1X = (availableWidth - (3 * hexWidth + 2 * spacing)) / 2
        return (hexWidth, hexHeight, colStep, rowStep, stagger, row1X)
    }

    private var honeycombGrid: some View {
        GeometryReader { geo in
            let spacing: CGFloat = metrics.isCompact ? 4 : 6
            let layout = Self.hexLayout(availableWidth: geo.size.width, spacing: spacing, isCompact: metrics.isCompact)
            let cells = gridCells

            ZStack(alignment: .topLeading) {
                // Row 0 (cells 0-2) — staggered right
                ForEach(0..<3, id: \.self) { col in
                    honeycombCell(cells[col], hexWidth: layout.hexWidth, hexHeight: layout.hexHeight)
                        .offset(x: layout.row1X + layout.stagger + CGFloat(col) * layout.colStep, y: 0)
                }
                // Row 1 (cells 3-5) — centered
                ForEach(0..<3, id: \.self) { col in
                    honeycombCell(cells[3 + col], hexWidth: layout.hexWidth, hexHeight: layout.hexHeight)
                        .offset(x: layout.row1X + CGFloat(col) * layout.colStep, y: layout.rowStep)
                }
                // Row 2 (cells 6-8) — staggered right
                ForEach(0..<3, id: \.self) { col in
                    honeycombCell(cells[6 + col], hexWidth: layout.hexWidth, hexHeight: layout.hexHeight)
                        .offset(x: layout.row1X + layout.stagger + CGFloat(col) * layout.colStep, y: 2 * layout.rowStep)
                }
            }
            .frame(width: geo.size.width, height: 2 * layout.rowStep + layout.hexHeight, alignment: .topLeading)
            .onAppear {
                if abs(honeycombActualWidth - geo.size.width) > 0.5 {
                    honeycombActualWidth = geo.size.width
                }
            }
            .onChange(of: geo.size.width) { _, newWidth in
                if abs(honeycombActualWidth - newWidth) > 0.5 {
                    honeycombActualWidth = newWidth
                }
            }
        }
        .frame(height: honeycombHeight)
    }

    /// Honeycomb height computed from the actual measured width when available,
    /// falling back to a conservative estimate before first layout.
    private var honeycombHeight: CGFloat {
        let width: CGFloat
        if honeycombActualWidth > 0 {
            width = honeycombActualWidth
        } else {
            width = metrics.isCompact ? 340 : 650
        }
        let spacing: CGFloat = metrics.isCompact ? 4 : 6
        let layout = Self.hexLayout(availableWidth: width, spacing: spacing, isCompact: metrics.isCompact)
        return 2 * layout.rowStep + layout.hexHeight
    }

    @ViewBuilder
    private func honeycombCell(_ cell: GridCell, hexWidth: CGFloat, hexHeight: CGFloat) -> some View {
        switch cell {
        case .achievement(let ach):
            VHexAchievementCard(ach: ach, showReduction: v.showReduction, engine: engine,
                                hexWidth: hexWidth, hexHeight: hexHeight,
                                isPelleDoomed: engine.pelleDoomed)
                .equatable()
        case .runButton:
            vRunButtonHex(hexWidth: hexWidth, hexHeight: hexHeight)
        case .empty:
            Color.clear
                .frame(width: hexWidth, height: hexHeight)
        }
    }

    // MARK: - V Run button (hexagonal, inside honeycomb)

    private func vRunButtonHex(hexWidth: CGFloat, hexHeight: CGFloat) -> some View {
        // Live in `VRunButton.swift` — adds the running-state line burst +
        // indianred bg flip per the web `c-v-run-button--running` rules.
        VRunButton(
            isRunning: v.isRunning,
            isActive: isVisible,
            isEnabled: !engine.pelleDoomed,
            hexWidth: hexWidth,
            hexHeight: hexHeight,
            isCompact: metrics.isCompact
        ) {
            guard !engine.pelleDoomed else { return }
            engine.requestVRun()
        }
    }

    // MARK: - Hard V controls

    private var hardVControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                GameButton(theme: .v, isEnabled: true) {
                    engine.toggleVFlipped()
                } label: {
                    Text(v.wantsFlipped ? "Hide Hard V" : "Show Hard V")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
            }

            if v.wantsFlipped {
                VStack(spacing: 2) {
                    Text("Each Hard V-Achievement counts as two V-Achievements and will award 2 Space Theorems instead of 1.")
                    Text("Goal reduction is significantly more expensive for Hard V-Achievements.")
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Cursed glyph easter egg (V.isFlipped only)

    private var cursedGlyphButton: some View {
        VStack(spacing: 8) {
            Button {
                engine.giveCursedGlyph()
            } label: {
                Text("Get a Cursed Glyph…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GameColor.v)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black)
                    .roundedBorder(GameColor.v, lineWidth: 1.5)
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                Text("Cursed Glyphs can be created here or in the Effarig tab.")
                Text("Cursed Glyphs count as −3 Glyphs for the purposes of all requirements related to Glyph count.")
                // Web VTab.vue:208 gates this on `!isDoomed`.
                if !engine.pelleDoomed {
                    Text("The Black Hole can now be used to slow down time if they are both permanent.")
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.75))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Milestones

    private var milestonesSection: some View {
        let doomed = engine.pelleDoomed
        return VStack(spacing: 8) {
            Text("V-Unlock Milestones")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(GameColor.v)
                .strikethrough(doomed)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(v.milestones) { mile in
                    VMilestoneCard(milestone: mile, currentST: v.spaceTheorems, isPelleDoomed: doomed)
                        .equatable()
                }
            }
            // Negate the parent ScrollView VStack's default `.padding()`
            // (16pt) so the milestone cards run edge-to-edge while the
            // section title stays aligned with the rest of the content.
            .padding(.horizontal, -16)
        }
    }

    // MARK: - Debug

    #if DEBUG
    private var debugSection: some View {
        VStack(spacing: 8) {
            Divider().background(.white.opacity(0.3))
            Text("DEBUG")
                .font(.caption.weight(.bold))
                .foregroundStyle(.red)

            HStack(spacing: 8) {
                GameButton(borderColor: .red, isEnabled: true) {
                    engine.devForceVRequirements()
                } label: {
                    Text("Force V\nRequirements")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .padding(6)
                }

                GameButton(borderColor: .red, isEnabled: true) {
                    engine.devCompleteAllNormalVAchievements()
                } label: {
                    Text("Complete All\nNormal (6)")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .padding(6)
                }

                GameButton(borderColor: .red, isEnabled: true) {
                    engine.devCompleteAllVAchievements()
                } label: {
                    Text("Complete All\n(incl. Hard)")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .padding(6)
                }
            }
        }
    }
    #endif
}

// MARK: - V Unlock Requirement Row

private struct VUnlockRequirementRow: View, Equatable {
    let req: VUnlockRequirement

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(req.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(req.isMet ? .green : .white)
                Spacer()
                Text("\(req.current) / \(req.goal)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(req.isMet ? .green : .white.opacity(0.7))
                if req.isMet {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(req.isMet ? .green : GameColor.v)
                        .frame(width: geo.size.width * req.progress)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .modifier(RoundedBorderModifier(
            color: req.isMet ? .green.opacity(0.5) : GameColor.v.opacity(0.3),
            cornerRadius: 8, lineWidth: 1
        ))
    }
}

// MARK: - V Hex Achievement Card

/// Achievement card shaped as a hexagon for the honeycomb grid.
private struct VHexAchievementCard: View, Equatable {
    let ach: VAchievementInfo
    let showReduction: Bool
    let engine: GameEngine
    let hexWidth: CGFloat
    let hexHeight: CGFloat
    var isPelleDoomed: Bool = false

    @State private var showGlyphSet = false

    static func == (lhs: VHexAchievementCard, rhs: VHexAchievementCard) -> Bool {
        lhs.ach == rhs.ach
            && lhs.showReduction == rhs.showReduction
            && lhs.hexWidth == rhs.hexWidth
            && lhs.hexHeight == rhs.hexHeight
            && lhs.isPelleDoomed == rhs.isPelleDoomed
        // engine excluded (identity-stable). @State excluded (SwiftUI storage).
    }

    /// Mirrors web `showRecord(hex)` (VTab.vue:127-129): card shows the
    /// record / reduction button only after the player has either set a
    /// run record or completed at least one tier.
    private var showRecord: Bool { !ach.record.isEmpty || ach.completions > 0 }

    var body: some View {
        // Explicit ZStack so z-order is unambiguous:
        //   back  → hex fill
        //   mid   → hex stroke (the gold outline)
        //   front → VStack content, including the Reduce pill's opaque-black
        //           Capsule background which covers the stroke wherever they
        //           overlap.
        // Earlier `.background(stroke).background(fill)` chaining read as
        // correct on paper but the user-visible bleed-through persisted —
        // ZStack removes any ambiguity about how SwiftUI composes the layers.
        ZStack {
            Hexagon()
                .fill(ach.isFullyCompleted ? GameColor.v.opacity(0.25) : .black)
            Hexagon()
                .stroke(ach.hexColor.isEmpty ? GameColor.v : Color(cssColor: ach.hexColor), lineWidth: 1.5)
            VStack(spacing: 3) {
                // Tier badge
                Text("\(ach.completions)/\(ach.maxCompletions)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(ach.isFullyCompleted ? .black : .white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(ach.isFullyCompleted ? GameColor.v : .white.opacity(0.2))
                    )

                // Name
                Text(ach.name)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .strikethrough(isPelleDoomed)

                // Description — centered for hex shape. lineLimit 6 paired with
                // tighter horizontal padding (below) — the JS bridge now strips
                // hard line breaks from source-code multi-line template literals
                // (e.g. "Post-destination") so iOS gets to natural-wrap to the
                // hex width.
                Text(ach.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(6)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .strikethrough(isPelleDoomed)

                // Goal reduction status (web VTab.vue:240-244 — visible when
                // shardReduction is unlocked and reduction steps have been spent).
                if showReduction && ach.isReduced && !ach.reductionMode.isEmpty && !ach.reductionValue.isEmpty {
                    Text("Goal has been \(ach.reductionMode) by \(ach.reductionValue)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(GameColor.v.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }

                // Record
                if !ach.record.isEmpty {
                    Text("Best: \(ach.record)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }

                // Reward
                Text(ach.isHard ? "2 ST" : "1 ST")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(GameColor.v.opacity(0.7))
                    .strikethrough(isPelleDoomed)

                // Goal reduction button — web gates on `showRecord(hex)` so the
                // button only appears for achievements with a record or completions.
                if showReduction && ach.canReduce && showRecord {
                    Button {
                        Haptics.tap()
                        engine.reduceVGoal(ach.id)
                    } label: {
                        Text("Reduce (\(ach.reductionCost) PP)")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(GameColor.v)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            // Opaque black fill so the hex stroke (drawn
                            // behind this in the ZStack) is hidden under
                            // the pill in their overlap region.
                            .background(
                                Capsule()
                                    .fill(.black)
                                    .overlay(Capsule().strokeBorder(GameColor.v.opacity(0.5), lineWidth: 0.5))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            // Tighter horizontal padding gives the description ~8% more line
            // width. The hex's sloped sides only narrow noticeably near the
            // top/bottom points, so the middle rows easily render against the
            // reduced inset without clipping.
            .padding(.horizontal, hexWidth * 0.02)
            .padding(.vertical, hexHeight * 0.08)
        }
        .frame(width: hexWidth, height: hexHeight)
        // No `.clipShape(Hexagon())` — the hex's bottom-tapered region is
        // narrower than the "Reduce (X PP)" pill, so clipping to the hex
        // outline truncated the label. Hex fill + stroke live inside the
        // ZStack; the bleeding pill draws on top of both and its opaque
        // Capsule background hides the stroke line in the overlap. The
        // bleed-over outside the pill still shows the stroke as expected.
        // Long-press → per-achievement glyph set sheet (mirrors web's
        // GlyphSetPreview embedded in the hex; bridged via
        // `ach.glyphSet`). No-op when the achievement has no record yet.
        .onLongPressGesture(minimumDuration: 0.4) {
            guard !ach.glyphSet.isEmpty else { return }
            showGlyphSet = true
        }
        #if DEBUG
        .contextMenu {
            Button("Complete 1 Tier") { engine.devCompleteVAchievement(ach.id) }
            Button("Max All Tiers") { engine.devMaxVAchievement(ach.id) }
        }
        #endif
        .sheet(isPresented: $showGlyphSet) {
            VAchievementGlyphSetSheet(achievement: ach)
        }
    }
}

// MARK: - V Achievement Glyph Set Sheet
//
// Long-press an achievement hex → opens this sheet showing the Glyph Set
// the player used to set the run record for that achievement. Mirrors
// web `VTab.vue:253` `<GlyphSetPreview :glyphs="runGlyphs[hex.id]" />`,
// scaled up to use the shared `GlyphRichCard`.

private struct VAchievementGlyphSetSheet: View {
    let achievement: VAchievementInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(achievement.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(GameColor.v)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if !achievement.record.isEmpty {
                        Text("Best: \(achievement.record)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    if achievement.glyphSet.isEmpty {
                        Text("No record yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 32)
                    } else {
                        Text("Glyph Set used")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        ForEach(achievement.glyphSet) { g in
                            GlyphRichCard(glyph: g.asGlyphInfo)
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

// MARK: - V Milestone Card

private struct VMilestoneCard: View, Equatable {
    let milestone: VMilestoneInfo
    let currentST: Int
    var isPelleDoomed: Bool = false

    static func == (lhs: VMilestoneCard, rhs: VMilestoneCard) -> Bool {
        lhs.milestone == rhs.milestone
            && lhs.currentST == rhs.currentST
            && lhs.isPelleDoomed == rhs.isPelleDoomed
    }

    var body: some View {
        // Web `VTab.vue:325-330` renders only description / reward /
        // currently — no ST badge. iOS previously surfaced a "X ST"
        // requirement badge here but the bridge was pulling
        // `VUnlocks[k].requirement`, which for the 6 post-unlock
        // milestones is a function (`() => V.spaceTheorems >= 2`, …),
        // not a number — `JSON.stringify` drops functions, so the field
        // arrived as 0 on every card. Removed for web parity and to free
        // vertical room for the description/reward to render in full.
        VStack(spacing: 8) {
            Text(milestone.description)
                .font(.subheadline)
                .foregroundStyle(milestone.isReached ? .white : .white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .minimumScaleFactor(0.8)
                .strikethrough(isPelleDoomed)

            if !milestone.reward.isEmpty {
                Text("Reward: \(milestone.reward)")
                    .font(.caption)
                    .foregroundStyle(milestone.isReached ? GameColor.v : .white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .minimumScaleFactor(0.8)
                    .strikethrough(isPelleDoomed)
            }

            // Web VTab.vue:328-330 — "Currently: <effect>" only when the
            // milestone has a numeric formattedEffect (e.g. shardReduction's
            // active goal discount).
            if !milestone.formattedEffect.isEmpty {
                Text("\(Text("Currently: ").foregroundStyle(milestone.isReached ? .white : .white.opacity(0.6)))\(Text(milestone.formattedEffect).fontWeight(.bold).foregroundStyle(milestone.isReached ? GameColor.v : .white.opacity(0.6)))")
                    .font(.caption.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .strikethrough(isPelleDoomed)
            }
        }
        // Tight horizontal inset so multi-line "Reward: …" and "Reduce
        // the Space Theorem cost of Time Studies by 2. Unlock Ra, Celes…"
        // copy gets the full card width before truncating.
        .padding(.horizontal, 6)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(milestone.isReached ? GameColor.v.opacity(0.15) : Color(hex: "#161616"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(milestone.isReached ? GameColor.v.opacity(0.5) : .white.opacity(0.15), lineWidth: 1)
        )
    }
}
