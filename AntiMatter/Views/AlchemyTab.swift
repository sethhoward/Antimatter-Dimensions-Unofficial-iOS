//
//  AlchemyTab.swift
//  AntiMatter
//
//  Glyph Alchemy — Ra-unlocked subtab (Effarig pet level 2).
//  Canvas-rendered circle of 20 alchemy resources with reaction arrows.
//  Tap a node to inspect and toggle its reaction.
//

import SwiftUI
import Combine

struct AlchemyTab: View {
    let engine: GameEngine

    @State private var selectedResourceId: Int? = nil
    @State private var showHelpSheet = false
    @State private var showRealityGlyphSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if engine.pelleDoomed {
                    PelleSimpleDisabledBanner(
                        text: "Glyph Alchemy is disabled while Doomed."
                    )
                    .padding(.horizontal, 12)
                }
                AlchemyControlsRow(engine: engine,
                                   showHelpSheet: $showHelpSheet,
                                   showRealityGlyphSheet: $showRealityGlyphSheet)
                AlchemyResourceInfoCard(engine: engine, selectedResourceId: $selectedResourceId)
                AlchemyInfoText(engine: engine)
                AlchemyCircleCanvas(engine: engine, selectedResourceId: $selectedResourceId)
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.horizontal, 12)
                #if DEBUG
                AlchemyDebugMaxAllButton(engine: engine)
                #endif
                PhoneTabBarSpacer()
            }
            .padding(.vertical, 12)
        }
        .pelleSilhouetteBackground(active: engine.pelleDoomed)
        .sheet(isPresented: $showHelpSheet) {
            AlchemyHelpSheet(engine: engine)
        }
        .sheet(isPresented: $showRealityGlyphSheet) {
            RealityGlyphCreationSheet(engine: engine)
        }
    }
}

// MARK: - Resource Info Card

private struct AlchemyResourceInfoCard: View {
    let engine: GameEngine
    @Binding var selectedResourceId: Int?

    /// Inline resource info, mirroring web `AlchemyResourceInfo`. Updates when
    /// the user taps a node; defaults to the first unlocked resource (Power)
    /// on first render.
    private func selectedResource(in alchemy: GlyphAlchemyState) -> AlchemyResourceInfo? {
        if let id = selectedResourceId,
           let r = alchemy.resources.first(where: { $0.id == id }) {
            return r
        }
        return alchemy.resources.first(where: { $0.isUnlocked })
            ?? alchemy.resources.first
    }

    var body: some View {
        let alchemy = engine.gameState.glyphAlchemy
        if let resource = selectedResource(in: alchemy) {
            VStack(alignment: .center, spacing: 6) {
                Text("\(resource.symbol) \(resource.name) \(resource.symbol)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(GameColor.ra.readableOnDark())

                if !resource.isUnlocked {
                    Text("Unlock requirement: \(resource.lockText.isEmpty ? "Not yet unlocked." : resource.lockText)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                } else if alchemy.isDoomed {
                    Text("Destroyed by Pelle")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                } else {
                    Text("\(resource.capped ? "Capped" : "Current"): \(Text("\(resource.amount)/\(resource.cap)").foregroundStyle(.white)) (Recent change: \(Text(resource.flowText).foregroundStyle(Self.flowColor(for: resource))))")
                        .foregroundStyle(.white.opacity(0.75))
                        .font(.caption.monospacedDigit())

                    if resource.isBaseResource {
                        Text("Base Resource")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                    } else if !resource.reactionText.isEmpty {
                        Text("Reaction: \(resource.reactionActive ? "Active" : "Inactive") (\(resource.reactionText))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }

                    if !resource.effectText.isEmpty {
                        Text("Effect: \(resource.effectText)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }

                    if !resource.isBaseResource {
                        Button {
                            engine.toggleAlchemyReaction(resource.id)
                        } label: {
                            Text(resource.reactionActive ? "Disable reaction" : "Enable reaction")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(resource.reactionActive ? .black : GameColor.ra)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(resource.reactionActive ? GameColor.ra : .black)
                                .roundedBorder(GameColor.ra, lineWidth: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(GameColor.ra.opacity(0.5), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 12)
        }
    }

    static func flowColor(for resource: AlchemyResourceInfo) -> Color {
        if resource.flow > 0.01 { return Color(red: 0.61, green: 0.8, blue: 0.4) }
        if resource.flow < -0.01 { return Color(red: 0.8, green: 0.4, blue: 0.4) }
        return .white.opacity(0.75)
    }
}

#if DEBUG
private struct AlchemyDebugMaxAllButton: View {
    let engine: GameEngine

    /// DEBUG-only: sets every alchemy resource to its cap in one tap. Mirrors
    /// the web `dev.*` cheats but scoped to the alchemy page so testing
    /// downstream content (Reality Glyph creation, Laitela reward tuning)
    /// doesn't require refining a full inventory.
    var body: some View {
        Button {
            engine.devMaxAllAlchemy()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "ladybug")
                Text("DEBUG: Max All Alchemy")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black)
            .roundedBorder(Color.orange.opacity(0.7), lineWidth: 1)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }
}
#endif

// MARK: - Controls / Info

private struct AlchemyControlsRow: View {
    let engine: GameEngine
    @Binding var showHelpSheet: Bool
    @Binding var showRealityGlyphSheet: Bool

    var body: some View {
        let alchemy = engine.gameState.glyphAlchemy
        // iPhone needs two rows when Reality-glyph creation is visible so
        // all three controls fit. iPad fits comfortably in one row.
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    showHelpSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                        Text("Alchemy info")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GameColor.ra)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black)
                    .roundedBorder(GameColor.ra, lineWidth: 1)
                }
                .buttonStyle(.plain)

                Button {
                    engine.toggleAllAlchemyReactions()
                } label: {
                    Text(alchemy.allReactionsDisabled ? "Enable all reactions" : "Disable all reactions")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(GameColor.ra)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black)
                        .roundedBorder(GameColor.ra, lineWidth: 1)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!alchemy.isDoomed)
                .opacity(alchemy.isDoomed ? 0.4 : 1)
            }

            // Reality-Glyph creation button appears once Effarig Ra pet
            // reaches level 25 (via `alchemy.realityCreationVisible`).
            // Matches `AlchemyTab.vue`'s `realityCreationVisible` button
            // — it subtly glows ("tutorial--glow") until the player has
            // created their first one.
            if alchemy.realityCreationVisible {
                Button {
                    showRealityGlyphSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("View Reality Glyph creation")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(GameColor.reality)
                    .roundedBorder(GameColor.reality, lineWidth: 1)
                    .shadow(
                        color: GameColor.reality.opacity(alchemy.createdRealityGlyph ? 0 : 0.6),
                        radius: alchemy.createdRealityGlyph ? 0 : 6
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct AlchemyInfoText: View {
    let engine: GameEngine

    var body: some View {
        let alchemy = engine.gameState.glyphAlchemy
        VStack(spacing: 4) {
            Text("Glyphs can be refined using your Glyph filter on the Glyphs tab.")
            Text("Refining caps each resource at \(Self.formatMultiplier(alchemy.capFactor))× its highest refinement value.")
            Text("Reactions trigger once per Reality, unaffected by stored real time.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
    }

    private static func formatMultiplier(_ v: Double) -> String {
        if v <= 0 { return "0" }
        return String(format: "%.2f", v)
    }
}

// MARK: - Circle Canvas

private struct AlchemyCircleCanvas: View {
    let engine: GameEngine
    @Binding var selectedResourceId: Int?

    /// Whether any active reaction exists — gates the TimelineView
    /// animation so we don't redraw at 30fps when nothing is flowing.
    private func hasActiveReactions(_ alchemy: GlyphAlchemyState) -> Bool {
        alchemy.arrows.contains(where: { $0.isActive && !$0.isCapped })
    }

    var body: some View {
        let alchemy = engine.gameState.glyphAlchemy
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let nodeRadius: CGFloat = size < 320 ? 16 : 22
            ZStack {
                // Orbit rings + arrows. When any reaction is actively
                // flowing, wrap in a TimelineView so we can animate the
                // inward-pulling dash pattern. Idle state uses a static
                // Canvas to avoid per-tick redraws.
                if hasActiveReactions(alchemy) {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                        arrowsCanvas(alchemy: alchemy, phase: tl.date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    arrowsCanvas(alchemy: alchemy, phase: 0)
                }

                // Node circles + symbols (first pass).
                ForEach(alchemy.resources) { resource in
                    alchemyNodeCircle(resource: resource, nodeRadius: nodeRadius)
                        .position(
                            x: CGFloat(resource.x / 100.0) * size + (geo.size.width - size) / 2,
                            y: CGFloat(resource.y / 100.0) * size + (geo.size.height - size) / 2
                        )
                }

                // Amount labels (second pass) — rendered above all node
                // circles so adjacent nodes can't paint over them.
                ForEach(alchemy.resources) { resource in
                    if resource.isUnlocked && !alchemy.isDoomed {
                        alchemyNodeLabel(resource: resource, nodeRadius: nodeRadius)
                            .position(
                                x: CGFloat(resource.x / 100.0) * size + (geo.size.width - size) / 2,
                                y: CGFloat(resource.y / 100.0) * size + (geo.size.height - size) / 2 + nodeRadius - 6
                            )
                    }
                }
            }
        }
    }

    /// Canvas pass for the orbit rings and reaction arrows. `phase` drives
    /// the `dashPhase` of active-reaction strokes so dashes scroll from the
    /// reagent toward the product (visual "pull inward"). For idle renders
    /// phase=0 gives a consistent static image.
    private func arrowsCanvas(alchemy: GlyphAlchemyState, phase: TimeInterval) -> some View {
        Canvas { context, canvasSize in
            let dim = min(canvasSize.width, canvasSize.height)
            let offset = CGPoint(x: (canvasSize.width - dim) / 2,
                                 y: (canvasSize.height - dim) / 2)

            // Orbit rings (tiers 1-5; radii 4,3,2,1,0 with size = 8)
            let ringRadii: [CGFloat] = [0.5, 0.375, 0.25, 0.125]
            for r in ringRadii {
                let diameter = dim * r * 2
                let rect = CGRect(
                    x: offset.x + (dim - diameter) / 2,
                    y: offset.y + (dim - diameter) / 2,
                    width: diameter, height: diameter
                )
                context.stroke(
                    Circle().path(in: rect),
                    with: .color(Color.white.opacity(0.12)),
                    lineWidth: 1
                )
            }

            // Reaction arrows — animated inward dashes for active, static
            // dashed/solid for other states.
            for arrow in alchemy.arrows where arrow.isUnlocked {
                let p1 = positionFor(x: arrow.reagentX, y: arrow.reagentY, in: dim, offset: offset)
                let p2 = positionFor(x: arrow.productX, y: arrow.productY, in: dim, offset: offset)
                let path = Path { p in
                    p.move(to: p1)
                    p.addLine(to: p2)
                }
                let color = arrowColor(for: arrow)
                let style: StrokeStyle
                if arrow.isActive && !arrow.isCapped {
                    // Short dashes marching from reagent → product.
                    // Negative dashPhase scrolls the pattern in the start-
                    // to-end direction (i.e. toward the product/center).
                    let segment: CGFloat = 6
                    let gap: CGFloat = 8
                    let scrollSpeed: CGFloat = 40 // points per second
                    let dashPhase = -CGFloat(phase.truncatingRemainder(dividingBy: 10)) * scrollSpeed
                    style = StrokeStyle(
                        lineWidth: 2.5, lineCap: .round,
                        dash: [segment, gap], dashPhase: dashPhase
                    )
                } else {
                    style = StrokeStyle(lineWidth: 1, lineCap: .round, dash: [4, 4])
                }
                context.stroke(path, with: .color(color), style: style)
            }
        }
    }

    private func positionFor(x: Double, y: Double, in dim: CGFloat, offset: CGPoint) -> CGPoint {
        CGPoint(
            x: offset.x + CGFloat(x / 100.0) * dim,
            y: offset.y + CGFloat(y / 100.0) * dim
        )
    }

    private func arrowColor(for arrow: AlchemyReactionArrow) -> Color {
        if arrow.isActive { return .yellow }
        if arrow.isCapped { return Color.gray.opacity(0.4) }
        if arrow.isLessThanRequired { return Color.orange.opacity(0.6) }
        return Color.white.opacity(0.3)
    }

    private func alchemyNodeCircle(resource: AlchemyResourceInfo, nodeRadius: CGFloat) -> some View {
        let fill = nodeFill(resource)
        let border = nodeBorder(resource)
        return ZStack {
            Circle()
                .fill(fill)
                .frame(width: nodeRadius * 2, height: nodeRadius * 2)
                .overlay(Circle().stroke(border, lineWidth: resource.reactionActive ? 2.5 : 1.8))
                .shadow(color: glowColor(resource), radius: resource.reactionActive ? 4 : 0)

            Text(resource.symbol)
                .font(.system(size: nodeRadius * 0.95, weight: .bold))
                .foregroundStyle(symbolColor(resource))
        }
        .contentShape(Circle())
        .onTapGesture {
            guard resource.isUnlocked else { return }
            // Mirrors web `AlchemyTab.vue:handleClick`: first tap selects
            // (info card below the controls updates). Tapping a node that's
            // ALREADY selected toggles its reaction — but only for non-base
            // resources (base resources have no reaction to toggle).
            if selectedResourceId == resource.id, !resource.isBaseResource {
                engine.toggleAlchemyReaction(resource.id)
            } else {
                selectedResourceId = resource.id
            }
        }
    }

    /// Amount label rendered as a separate pass so it always sits above
    /// every node circle. White text with a doubled black shadow halo so it
    /// reads clearly against yellow dashed reaction arrows, white sibling
    /// circles, and the dark theme background.
    private func alchemyNodeLabel(resource: AlchemyResourceInfo, nodeRadius: CGFloat) -> some View {
        Text(formatAmount(resource.amountNum))
            .font(.system(size: max(nodeRadius * 0.45, 9), weight: .medium).monospacedDigit())
            .foregroundStyle(Color.white)
            .shadow(color: .black.opacity(0.9), radius: 1.5)
            .shadow(color: .black.opacity(0.9), radius: 1.5)
            .lineLimit(1)
            .fixedSize()
            .allowsHitTesting(false)
    }

    /// Integer-style format for per-node amounts. Resources cap at 10,000
    /// at base — display as comma-separated integers for readability.
    /// For very small accumulations (< 1) show "0" to match web's
    /// `formatInt` rounding behavior on the label.
    private func formatAmount(_ v: Double) -> String {
        guard v.isFinite else { return "∞" }
        if v < 0.5 { return "0" }
        let n = Int(v.rounded())
        return Self.amountFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private static let amountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.maximumFractionDigits = 0
        return f
    }()

    private func nodeFill(_ resource: AlchemyResourceInfo) -> Color {
        if !resource.isUnlocked { return GameColor.unavailableBg.opacity(0.6) }
        // Matches web — filled white circle so the type-colored symbol
        // reads clearly at small sizes. Black fill at this scale turns
        // the symbol into a dim smudge on iPhone.
        return Color.white
    }

    private func nodeBorder(_ resource: AlchemyResourceInfo) -> Color {
        if !resource.isUnlocked { return Color.gray.opacity(0.3) }
        if resource.reactionActive { return GameColor.ra }
        // Base (tier 1) resources get an orange ring, non-base get green —
        // matches the web Alchemy tab palette.
        if resource.isBaseResource { return Color(red: 0.98, green: 0.62, blue: 0.23) }
        return Color(red: 0.42, green: 0.78, blue: 0.38)
    }

    /// Symbol color — type-tinted for unlocked, dim grey for locked.
    /// White fill circle makes the tint readable.
    private func symbolColor(_ resource: AlchemyResourceInfo) -> Color {
        if !resource.isUnlocked { return Color.white.opacity(0.3) }
        if resource.isBaseResource { return Color(red: 0.0, green: 0.55, blue: 0.85) }
        return Color(red: 0.15, green: 0.45, blue: 0.25)
    }

    private func glowColor(_ resource: AlchemyResourceInfo) -> Color {
        if resource.flow > 0.01 { return Color.green.opacity(0.5) }
        if resource.flow < -0.01 { return Color.red.opacity(0.5) }
        return .clear
    }
}

// MARK: - Help Sheet

/// Glyph Alchemy intro + resource/reaction help, pulled live from
/// `GameDatabase.h2p.tabs` so formatted values (refinement cap, rarity, etc.)
/// reflect the current save. Mirrors web `Modal.h2p` with the Alchemy tab.
private struct AlchemyHelpSheet: View {
    let engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    @State private var resourcesInfo: String = ""
    @State private var reactionsInfo: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section(title: "Glyph Alchemy Resources", body: resourcesInfo)
                    section(title: "Glyph Alchemy Reactions", body: reactionsInfo)
                }
                .padding(16)
            }
            .adaptiveSheetTitle("Glyph Alchemy")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(GameColor.ra)
                }
            }
        }
        .task { load() }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(GameColor.ra)
            Text(body.isEmpty ? "Loading…" : body)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load() {
        engine.fetchAlchemyHelpText { resources, reactions in
            self.resourcesInfo = resources
            self.reactionsInfo = reactions
        }
    }
}

// MARK: - Detail Sheet

// MARK: - Reality Glyph Creation Sheet

/// Mirrors web `RealityGlyphCreationModal.vue`. Shows the projected
/// Reality Glyph level (= `AlchemyResource.reality.effectValue`), the
/// list of possible effects (with level-gated previews), and a Create
/// button that consumes the Reality resource to generate the glyph.
private struct RealityGlyphCreationSheet: View {
    let engine: GameEngine
    @Environment(\.dismiss) private var dismiss
    @State private var preview: GameEngine.RealityGlyphCreationPreview?
    /// Poll signal — bumped every 500ms so the level + effect previews
    /// track the user's live Reality-resource balance without needing
    /// to close and reopen the sheet.
    @State private var refreshTick = 0

    private let refreshTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let p = preview {
                        intro(level: p.glyphLevel)
                        effectsSection(effects: p.effects)
                        actionButton(preview: p)
                    } else {
                        Text("Loading…")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .adaptiveSheetTitle("Reality Glyph Creation")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .tint(GameColor.reality)
                }
            }
        }
        .task { load() }
        .onReceive(refreshTimer) { _ in load() }
    }

    private func intro(level: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create a level \(Text("\(level)").foregroundStyle(GameColor.reality).fontWeight(.bold)) Reality Glyph.")
                .font(.callout)
            Text("Rarity will always be 100% and level scales on your current Reality Resource amount (which is all consumed). All other Alchemy Resources are unaffected. Reality Glyphs have unique effects, some only available at higher Glyph levels. Reality Glyphs can also be sacrificed to increase all Memory Chunk gain. Like Effarig Glyphs, you cannot equip more than one at the same time.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func effectsSection(effects: [GameEngine.RealityGlyphEffectPreview]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Available Effects:")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameColor.reality)
            ForEach(Array(effects.enumerated()), id: \.offset) { _, effect in
                Text(effect.text)
                    .font(.caption)
                    .foregroundStyle(effect.meetsLevel ? .white : .white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(GameColor.reality.opacity(0.4), lineWidth: 1))
        )
    }

    private func actionButton(preview p: GameEngine.RealityGlyphCreationPreview) -> some View {
        Button {
            engine.createRealityGlyph()
            dismiss()
        } label: {
            Text(buttonLabel(p))
                .font(.callout.weight(.semibold))
                .foregroundStyle(buttonEnabled(p) ? .black : .white.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(buttonEnabled(p) ? GameColor.reality : GameColor.unavailableBg)
                .roundedBorder(buttonEnabled(p) ? GameColor.reality : Color.gray.opacity(0.4), lineWidth: 1.5)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(buttonEnabled(p))
    }

    private func buttonEnabled(_ p: GameEngine.RealityGlyphCreationPreview) -> Bool {
        !p.isDoomed && p.glyphLevel > 0
    }

    private func buttonLabel(_ p: GameEngine.RealityGlyphCreationPreview) -> String {
        if p.isDoomed { return "You cannot create Reality Glyphs while Doomed" }
        if p.glyphLevel == 0 { return "Reality Glyph level must be higher than 0" }
        return "Create a Reality Glyph!"
    }

    private func load() {
        engine.fetchRealityGlyphPreview { self.preview = $0 }
    }
}

private struct AlchemyResourceDetailSheet: View {
    let resource: AlchemyResourceInfo
    let onToggleReaction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if !resource.isUnlocked {
                        unlockBlock
                    } else {
                        amountBlock
                        if !resource.isBaseResource {
                            reactionBlock
                        } else {
                            Text("Base Resource")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !resource.effectText.isEmpty {
                            effectBlock
                        }
                    }
                }
                .padding()
            }
            .adaptiveSheetTitle("\(resource.symbol) \(resource.name)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(resource.symbol)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(GameColor.ra)
            VStack(alignment: .leading, spacing: 2) {
                Text(resource.name)
                    .font(.title2.weight(.bold))
                Text(resource.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unlockBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Unlock requirement")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(resource.lockText.isEmpty ? "Not yet unlocked." : resource.lockText)
                .font(.callout)
        }
    }

    private var amountBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(resource.capped ? "Capped" : "Current")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(resource.amount) / \(resource.cap)")
                    .monospacedDigit()
            }
            .font(.callout)
            HStack {
                Text("Recent change")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(resource.flowText)
                    .foregroundStyle(flowColor)
            }
            .font(.caption.monospacedDigit())
        }
    }

    private var flowColor: Color {
        if resource.flow > 0.01 { return Color(red: 0.61, green: 0.8, blue: 0.4) }
        if resource.flow < -0.01 { return Color(red: 0.8, green: 0.4, blue: 0.4) }
        return .secondary
    }

    private var reactionBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reaction")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(resource.reactionText)
                .font(.callout.monospacedDigit())
            Button {
                onToggleReaction()
            } label: {
                Text(resource.reactionActive ? "Reaction: Active — Disable" : "Reaction: Inactive — Enable")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(resource.reactionActive ? GameColor.ra : Color.black)
                    .foregroundStyle(resource.reactionActive ? Color.black : GameColor.ra)
                    .roundedBorder(GameColor.ra, lineWidth: 1)
            }
            .buttonStyle(.plain)
        }
    }

    private var effectBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Effect")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(resource.effectText)
                .font(.callout)
        }
    }
}
