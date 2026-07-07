//
//  CelestialNavigationTab.swift
//  AntiMatter
//
//  Pan/zoom map of all celestials. Rendered as a single SwiftUI Canvas
//  inside a ZoomableScrollView (mirrors PerksTab / TimeStudiesTab pattern).
//  Static geometry lives in CelestialNavigationData; per-tick completion
//  fractions and legend text come from GameEngine.gameState.celestials.navigation.
//

import SwiftUI

struct CelestialNavigationTab: View {
    let engine: GameEngine

    var body: some View {
        CelestialNavigationContent(engine: engine)
    }
}

/// Wraps the Celestial Navigation tab. Holds @State for legend toggling and
/// the "coming soon" toast, and reads `engine.gameState.celestials.navigation`
/// internally so the public `CelestialNavigationTab` doesn't re-evaluate on
/// per-tick state churn — important here because the Canvas redraws all
/// connectors + rings + nodes on every body invocation.
private struct CelestialNavigationContent: View {
    let engine: GameEngine

    @Environment(\.sidebarState) private var sidebar
    @Environment(\.layoutMetrics) private var metrics
    @State private var comingSoonMessage: String? = nil
    @State private var comingSoonDismissTask: Task<Void, Never>? = nil
    /// Toggle controlled by the "Show details" header button. When true, every
    /// node renders its leader-line legend (per-node detail labels). Replaces
    /// the previous long-press / double-tap gestures, which both fired
    /// alongside the single-tap node selection and were unreliable.
    @State private var showAllLabels: Bool = false

    private var navState: CelestialNavigationState { engine.gameState.celestials.navigation }

    /// Teresa's node in Canvas-local coordinates (matches CelestialNavigationCanvas.localize):
    ///   local = svgPos - bounds.origin + margin
    ///   Teresa svgPos (100, 100), bounds.origin (-100, -100), margin 120 → (320, 320)
    private static let teresaFocus = CGPoint(x: 320, y: 320)

    var body: some View {
        VStack(spacing: 8) {
            // Header
            VStack(spacing: 4) {
                Text("Celestial Navigation")
                    .font(.headline)
                    .foregroundStyle(GameColor.celestials)
                HStack(spacing: 12) {
                    Text("Tap a node to enter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showAllLabels.toggle()
                        }
                    } label: {
                        Label(showAllLabels ? "Hide details" : "Show details",
                              systemImage: showAllLabels ? "tag.slash" : "tag")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(showAllLabels
                                    ? GameColor.celestials.opacity(0.25)
                                    : Color.black.opacity(0.35))
                            )
                            .overlay(Capsule().stroke(GameColor.celestials, lineWidth: 1))
                            .foregroundStyle(GameColor.celestials)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)

            // First open (zoom == 0 sentinel) → focus Teresa at zoom 1.0.
            // Subsequent opens restore the last zoom/offset persisted on GameEngine.
            let _ = initializeDefaultsIfNeeded()

            ZoomableScrollView(
                // minZoom 0.3 (was 0.5) so a single pinch-out fits the entire
                // 1140×1140 logical map — at 0.5 the endgame nodes (V, Ra,
                // Lai'tela, Pelle) couldn't all share screen with Teresa/Effarig,
                // making the V hexagon's outgoing connectors look like they
                // dangle off-screen.
                minZoom: 0.3,
                maxZoom: 2.0,
                initialFocus: engine.celestialNavOffset == .zero ? Self.teresaFocus : nil,
                zoomScale: Binding(
                    get: { engine.celestialNavZoom > 0 ? engine.celestialNavZoom : 1.0 },
                    set: { engine.celestialNavZoom = $0 }
                ),
                contentOffset: Binding(
                    get: { engine.celestialNavOffset },
                    set: { engine.celestialNavOffset = $0 }
                )
            ) {
                CelestialNavigationCanvas(
                    navState: navState,
                    showAllLabels: showAllLabels,
                    onTap: handleTap
                )
            }
        }
        .overlay(alignment: .top) {
            if let msg = comingSoonMessage {
                Text(msg)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .overlay(Capsule().stroke(GameColor.celestials, lineWidth: 1))
                    .padding(.top, 40)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: comingSoonMessage)
    }

    /// Promote the zero sentinel to 1.0 on first open so the ZoomableScrollView
    /// uses a valid initial zoom. Offset stays at .zero, triggering initialFocus
    /// on Teresa.
    private func initializeDefaultsIfNeeded() {
        if engine.celestialNavZoom == 0 {
            engine.celestialNavZoom = 1.0
        }
    }

    private func handleTap(nodeId: String) {
        guard let node = CelestialNavigationData.nodesByID[nodeId],
              let target = node.targetSubtab,
              let sidebar else { return }
        if target.isAvailable(engine: engine) {
            sidebar.selectSubtab(target, in: .celestials, engine: engine)
            return
        }
        // Locked subtab — Laitela's node renders its own progress legend
        // (Reality Machines / antimatter goal) and Pelle's gate is
        // self-evident from context. A banner saying "complete Ra to
        // unlock" was redundant and misleading (Laitela's actual gate is
        // ImaginaryUpgrade(15), not Ra completion), so taps on locked
        // nav nodes are now silent no-ops.
        let msg: String
        switch target {
        case .laitela, .pelle:
            return
        default:
            msg = "\(target.displayName) — not yet available."
        }
        comingSoonMessage = msg
        comingSoonDismissTask?.cancel()
        comingSoonDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled { comingSoonMessage = nil }
        }
    }
}

// MARK: - Canvas

struct CelestialNavigationCanvas: View {
    let navState: CelestialNavigationState
    /// When true, every node's legend renders (in addition to `alwaysShowLegend`
    /// nodes). When false, only `alwaysShowLegend` nodes show labels, keeping
    /// the map clean by default. Toggled by the parent's "Show details" button.
    var showAllLabels: Bool = false
    let onTap: (String) -> Void

    private var nodeStatesByID: [String: CelestialNavNodeState] {
        Dictionary(uniqueKeysWithValues: navState.nodes.map { ($0.id, $0) })
    }

    // Compute canvas bounds with padding so legends don't clip
    private static let bounds = CelestialNavigationData.canvasBounds
    private static let margin: CGFloat = 120

    private var totalSize: CGSize {
        CGSize(
            width: Self.bounds.width + Self.margin * 2,
            height: Self.bounds.height + Self.margin * 2
        )
    }

    /// Translates an SVG-space point into Canvas-local coordinates.
    private func localize(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: p.x - Self.bounds.origin.x + Self.margin,
            y: p.y - Self.bounds.origin.y + Self.margin
        )
    }

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
                drawBackground(ctx: ctx)
                drawConnectors(ctx: ctx)
                drawRings(ctx: ctx)
                drawNodes(ctx: ctx)
                drawLegends(ctx: ctx)
            }
            .frame(width: totalSize.width, height: totalSize.height)
            .contentShape(Rectangle())
            // Single-tap navigates. Detail labels are toggled by the parent's
            // header button (showAllLabels), not by gestures — long-press +
            // double-tap both fired alongside the single-tap selection in
            // earlier revisions, which the user found confusing.
            .onTapGesture { location in
                hitTest(at: location)
            }
        }
    }

    private func drawRings(ctx: GraphicsContext) {
        for ring in CelestialNavigationData.raRings {
            guard isVisible(ring.visibilityId ?? ring.id) else { continue }
            let c = localize(ring.center)
            let midR = (ring.rMajor + ring.rMinor) / 2
            let strokeWidth = ring.rMajor - ring.rMinor
            // gapDeg is the arc sector OMITTED from the ring. Draw the
            // complementary arc (360 - gap) centered at (gapCenter + 180).
            let drawCenterDeg = ring.gapCenterDeg + 180
            let drawSpanDeg = 360 - ring.gapDeg
            guard drawSpanDeg > 0 else { continue }
            let startAngle = (drawCenterDeg - drawSpanDeg / 2) * .pi / 180
            let endAngle   = (drawCenterDeg + drawSpanDeg / 2) * .pi / 180
            var path = Path()
            path.addArc(
                center: c, radius: midR,
                startAngle: Angle(radians: startAngle),
                endAngle: Angle(radians: endAngle),
                clockwise: false
            )
            let complete = nodeStatesByID[ring.id]?.completeFraction ?? 0
            let color = complete >= 1 ? ring.color.opacity(0.55) : ring.color.opacity(0.2)
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
        }
    }

    private func drawBackground(ctx: GraphicsContext) {
        let rect = CGRect(origin: .zero, size: totalSize)
        let gradient = Gradient(colors: [
            Color.black,
            Color(red: 0.03, green: 0.02, blue: 0.08),
            Color.black
        ])
        ctx.fill(
            Path(rect),
            with: .radialGradient(
                gradient,
                center: CGPoint(x: rect.midX, y: rect.midY),
                startRadius: 0,
                endRadius: max(rect.width, rect.height) * 0.6
            )
        )
    }

    /// Whether a node is visible this tick. Defaults to false when no state
    /// exists yet — the canvas is only reachable once teresaUnlocked is true,
    /// so a poll has already fired before the first render; a single blank
    /// frame (~33ms) is imperceptible.
    private func isVisible(_ nodeId: String) -> Bool {
        nodeStatesByID[nodeId]?.isVisible ?? false
    }

    private func drawConnectors(ctx: GraphicsContext) {
        for conn in CelestialNavigationData.connectors {
            // Skip connectors whose controlling node is hidden. Connectors with
            // a synthetic id (no matching node) use visibilityId to name the
            // node that controls their visibility (e.g. ra-pet-teresa-link gates
            // on ra-pet-teresa; laitela-3rd-dim-b gates on laitela-3rd-dim).
            guard isVisible(conn.visibilityId ?? conn.id) else { continue }

            let pts = CelestialNavigationData.samplePoints(conn.kind).map(localize)
            guard pts.count >= 2 else { continue }

            let complete = nodeStatesByID[conn.id]?.completeFraction ?? 0
            var path = Path()
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.addLine(to: p) }

            // Incomplete connector: dim gray
            let dimColor = Color.gray.opacity(0.25)
            ctx.stroke(path, with: .color(dimColor),
                       style: StrokeStyle(lineWidth: conn.incompleteWidth, lineCap: .round))

            // Complete portion: gradient along path, trimmed to `complete` fraction
            if complete > 0 {
                let trimmed = trimPath(points: pts, fraction: complete)
                let gradient = Gradient(colors: [conn.colorA, conn.colorB])
                let start = pts.first ?? .zero
                let end = pts.last ?? .zero
                ctx.stroke(
                    trimmed,
                    with: .linearGradient(
                        gradient,
                        startPoint: start,
                        endPoint: end
                    ),
                    style: StrokeStyle(lineWidth: conn.completeWidth, lineCap: .round)
                )
            }
        }
    }

    /// Build a path containing the first `fraction` (0..1) of the input polyline.
    private func trimPath(points: [CGPoint], fraction: Double) -> Path {
        guard points.count >= 2, fraction > 0 else { return Path() }
        let clamped = min(max(fraction, 0), 1)
        if clamped >= 1 {
            var p = Path()
            p.move(to: points[0])
            for pt in points.dropFirst() { p.addLine(to: pt) }
            return p
        }
        // Measure total length
        var lengths: [Double] = []
        var total: Double = 0
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            let seg = hypot(dx, dy)
            lengths.append(seg)
            total += seg
        }
        let target = total * clamped
        var traveled: Double = 0
        var path = Path()
        path.move(to: points[0])
        for i in 1..<points.count {
            let segLen = lengths[i - 1]
            if traveled + segLen >= target {
                let remain = target - traveled
                let t = segLen > 0 ? remain / segLen : 0
                let px = points[i - 1].x + (points[i].x - points[i - 1].x) * t
                let py = points[i - 1].y + (points[i].y - points[i - 1].y) * t
                path.addLine(to: CGPoint(x: px, y: py))
                return path
            } else {
                path.addLine(to: points[i])
                traveled += segLen
            }
        }
        return path
    }

    private func drawNodes(ctx: GraphicsContext) {
        for def in CelestialNavigationData.nodes {
            guard isVisible(def.id) else { continue }
            let c = localize(def.position)
            let state = nodeStatesByID[def.id]
            let complete = state?.completeFraction ?? 0
            let isActive = complete >= 1

            // Outer ring (rMajor): stroke only when ring-style node
            let ringRect = CGRect(x: c.x - def.rMajor, y: c.y - def.rMajor,
                                  width: def.rMajor * 2, height: def.rMajor * 2)
            let ringColor = isActive ? def.color : def.color.opacity(0.35)
            ctx.stroke(
                Path(ellipseIn: ringRect),
                with: .color(ringColor),
                lineWidth: 3
            )

            // Inner disk (rMinor) — filled
            if let r = def.rMinor, r > 0 {
                let diskRect = CGRect(x: c.x - r, y: c.y - r,
                                      width: r * 2, height: r * 2)
                let fill: Color = isActive
                    ? def.color
                    : def.color.opacity(0.15)
                ctx.fill(Path(ellipseIn: diskRect), with: .color(fill))
            }

            // Symbol (if any). `"sf:<name>"` routes through an SF Symbol image —
            // same escape hatch used by RaUnlockIcon. Everything else is a
            // Unicode glyph drawn via Text.
            if let sym = def.symbol {
                let weight: Font.Weight = isActive ? .bold : .regular
                let fg: Color = isActive ? Color.black : .white.opacity(0.7)
                if sym.hasPrefix("sf:") {
                    let name = String(sym.dropFirst(3))
                    let img = Image(systemName: name)
                    let text = Text(img)
                        .font(.system(size: def.rMajor * 0.9, weight: weight))
                        .foregroundStyle(fg)
                    ctx.draw(ctx.resolve(text), at: c, anchor: .center)
                } else {
                    let text = Text(sym)
                        .font(.system(size: def.rMajor * 0.9, weight: weight))
                        .foregroundStyle(fg)
                    ctx.draw(ctx.resolve(text), at: c, anchor: .center)
                }
            }
        }
    }

    private func drawLegends(ctx: GraphicsContext) {
        for def in CelestialNavigationData.nodes {
            guard isVisible(def.id) else { continue }
            // Only draw legends for nodes that either (a) force-show (rare —
            // primary celestial "X's Reality" labels on the web) or (b) the
            // user is currently long-pressing. Keeps the map uncluttered.
            // alwaysShowLegend is unconditional. showAllLabels (parent button)
            // gates participating nodes — V achievements / Ra pets are excluded
            // because their labels cluster on top of each other.
            guard def.alwaysShowLegend || (showAllLabels && def.participatesInBulkLegend) else { continue }
            guard let state = nodeStatesByID[def.id] else { continue }
            let legend = state.legendText.isEmpty ? def.fallbackLegend : state.legendText
            guard !legend.isEmpty else { continue }

            let nodeCenter = localize(def.position)
            let angleRad = def.legendAngleDeg * .pi / 180
            // Offset leader: diagonal + horizontal extension
            let diagX = cos(angleRad) * def.legendDiagonal
            let diagY = sin(angleRad) * def.legendDiagonal
            let legendStart = CGPoint(
                x: nodeCenter.x + cos(angleRad) * (def.rMajor + 4),
                y: nodeCenter.y + sin(angleRad) * (def.rMajor + 4)
            )
            let legendEnd = CGPoint(
                x: legendStart.x + diagX + (cos(angleRad) >= 0 ? def.legendHorizontal : -def.legendHorizontal),
                y: legendStart.y + diagY
            )

            var leader = Path()
            leader.move(to: legendStart)
            leader.addLine(to: CGPoint(x: legendStart.x + diagX, y: legendStart.y + diagY))
            leader.addLine(to: legendEnd)
            ctx.stroke(leader, with: .color(def.color.opacity(0.8)), lineWidth: 1.5)

            // Text — anchor depends on side
            let anchor: UnitPoint = cos(angleRad) >= 0 ? .leading : .trailing
            let text = Text(legend)
                .font(.caption.weight(.medium))
                .foregroundStyle(def.color)
            let labelPos = CGPoint(
                x: legendEnd.x + (cos(angleRad) >= 0 ? 4 : -4),
                y: legendEnd.y
            )
            ctx.draw(ctx.resolve(text), at: labelPos, anchor: anchor)
        }
    }

    // MARK: - Hit testing

    /// Resolves the node id nearest to `tap` within its hit radius. Returns nil
    /// if no visible node covers the point. Used by both tap and long-press.
    private func nodeID(at tap: CGPoint) -> String? {
        var bestID: String? = nil
        var bestDist: CGFloat = .greatestFiniteMagnitude
        for def in CelestialNavigationData.nodes {
            guard isVisible(def.id) else { continue }
            let c = localize(def.position)
            let d = hypot(tap.x - c.x, tap.y - c.y)
            if d < def.rMajor * 1.1 && d < bestDist {
                bestDist = d
                bestID = def.id
            }
        }
        return bestID
    }

    private func hitTest(at tap: CGPoint) {
        var bestID: String? = nil
        var bestDist: CGFloat = .greatestFiniteMagnitude
        for def in CelestialNavigationData.nodes {
            guard isVisible(def.id) else { continue }
            let c = localize(def.position)
            let d = hypot(tap.x - c.x, tap.y - c.y)
            if d < def.rMajor * 1.1 && d < bestDist {
                bestDist = d
                bestID = def.id
            }
        }
        if let id = bestID { onTap(id) }
    }
}

