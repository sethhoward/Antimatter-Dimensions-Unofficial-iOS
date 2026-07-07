//
//  BlackHoleAnimationView.swift
//  AntiMatter
//
//  Particle animation for the Black Hole tab, ported from
//  black-hole-animation.js. Uses SwiftUI Canvas + TimelineView.
//

import SwiftUI

// MARK: - Constants (matching web)

private let canvasSize: CGFloat = 400
private let center: CGFloat = 200
private let particleCount = 120
private let particleSize: CGFloat = 0.5
private let planetSize: CGFloat = 1.5
private let semimajorAxis: Double = 100
private let activeThreshold: Double = 2

// MARK: - Kepler solver

/// Fixed-point iteration for eccentric anomaly from mean anomaly.
/// See https://en.wikipedia.org/wiki/Kepler%27s_equation
///
/// 8 iterations converge to ~1e-6 residual for the eccentricities we see
/// (`0 < e < ~0.95`), indistinguishable from the previous 20 visually while
/// running every frame for `dilationFactor`.
private func eccentricAnomaly(_ eccentricity: Double, _ meanAnomaly: Double) -> Double {
    var e0 = meanAnomaly
    for _ in 0..<8 {
        e0 = meanAnomaly + eccentricity * sin(e0)
    }
    return e0
}

// MARK: - Particle

private struct Particle {
    var distance: Double
    var lastDistance: Double
    var preLastDistance: Double
    var angle: Double        // 0..1 (fraction of full revolution)
    var lastAngle: Double
    var preLastAngle: Double
    var isInside: Bool
    var respawnTick: Bool

    init(holeSize: Double, areNegative: Bool, bh1IsActive: Bool) {
        let d = Self.randomDistance(holeSize: holeSize, areNegative: areNegative, bh1IsActive: bh1IsActive)
        distance = d
        lastDistance = d
        preLastDistance = d
        angle = Double.random(in: 0..<1)
        lastAngle = angle
        preLastAngle = angle
        isInside = areNegative
        respawnTick = true
    }

    static func randomDistance(holeSize: Double, areNegative: Bool, bh1IsActive: Bool) -> Double {
        if areNegative {
            return (1.97 * Double.random(in: 0..<1) + 0.03) * holeSize
        }
        return holeSize + 0.5 * semimajorAxis * Double.random(in: 0..<1) * (bh1IsActive ? 2 : 1)
    }

    mutating func respawn(holeSize: Double, areNegative: Bool, bh1IsActive: Bool) {
        distance = Self.randomDistance(holeSize: holeSize, areNegative: areNegative, bh1IsActive: bh1IsActive)
        lastDistance = distance
        preLastDistance = distance
        angle = Double.random(in: 0..<1)
        lastAngle = angle
        preLastAngle = angle
        isInside = areNegative
        respawnTick = true
    }

    mutating func update(delta: Double, dilationFactor: Double, holeSize: Double, areNegative: Bool, bh1IsActive: Bool) {
        let baseSpeed: Double = 1.5
        let speedFactor = min(pow(max(dilationFactor, 2) / 2, 3), 5)
        let particleSpeed = baseSpeed * speedFactor * min(delta, 16) / 1000

        if !isInside {
            preLastAngle = lastAngle
            lastAngle = angle
            angle = (angle + 20 * particleSpeed * .pi * pow(distance, -1.5)).truncatingRemainder(dividingBy: 1)
        }

        preLastDistance = lastDistance
        lastDistance = distance
        let distFactor = 1 + 0.3 * particleSpeed * pow(distance / holeSize, -2)
        if areNegative {
            distance *= distFactor
        } else {
            distance /= distFactor
        }

        if distance > 2.74645 * holeSize && areNegative {
            respawn(holeSize: holeSize, areNegative: areNegative, bh1IsActive: bh1IsActive)
        } else if distance < 0.01 * holeSize && !areNegative {
            respawn(holeSize: holeSize, areNegative: areNegative, bh1IsActive: bh1IsActive)
            return
        }

        isInside = distance <= holeSize * 0.865
        respawnTick = false
    }
}

// MARK: - Animation Model

@Observable
private final class BlackHoleAnimModel {
    var particles: [Particle] = []
    /// Used only for `dilationFactor` — planet itself is not rendered.
    var planetDistance: Double = 0

    private(set) var holeSize: Double = 20
    private(set) var eccentricity: Double = 0.5
    private(set) var period: Double = 3610

    private var lastTime: Date?
    private var configuredPower: Double = 0

    func configure(state: BlackHoleState) {
        guard state.isUnlocked else { return }
        let power = state.bh1Power
        // Only reconfigure orbital params when power changes (upgrade purchased)
        guard power != configuredPower else { return }
        configuredPower = power

        period = state.bh1CycleLength

        // Fixed-point iteration for eccentricity
        let y = (1 - pow(activeThreshold, -2)) / (1 - pow(power, -2))
        var ecc = 0.5
        let meanAnomaly = 2 * Double.pi * min(0.9, state.bh1Duration / period)
        for _ in 0..<1000 {
            let e0 = eccentricAnomaly(ecc, meanAnomaly)
            ecc = (y - 1) / (y * cos(e0) - 1)
        }
        eccentricity = ecc

        holeSize = semimajorAxis * (1 - ecc) * (1 - pow(power, -2))

        // Init particles if empty
        if particles.isEmpty {
            particles = (0..<particleCount).map { _ in
                Particle(holeSize: holeSize, areNegative: state.areNegative, bh1IsActive: state.bh1IsActive)
            }
        }
    }

    func totalPhase(state: BlackHoleState) -> Double {
        if state.bh1IsActive {
            return (state.bh1Phase - state.bh1Duration / 2 + period).truncatingRemainder(dividingBy: period)
        }
        return state.bh1Phase + state.bh1Duration / 2
    }

    /// Clears the wall-clock timestamp so the next `update` seeds fresh. Called
    /// when the view becomes active again after being off-screen.
    func resetClock() {
        lastTime = nil
    }

    func update(now: Date, state: BlackHoleState) {
        guard state.isUnlocked else { return }
        configure(state: state)

        let delta: Double
        if let last = lastTime {
            delta = now.timeIntervalSince(last) * 1000 // ms
        } else {
            lastTime = now
            return
        }
        lastTime = now

        // Planet orbit — only the radial distance is needed (for dilationFactor).
        // The angular component (theta/planetAngle) and drawPlanet are dead
        // code, so we skip the atan/tan/pow chain entirely.
        let phase = totalPhase(state: state)
        let e0 = eccentricAnomaly(eccentricity, 2 * .pi * phase / period)
        planetDistance = semimajorAxis * (1 - eccentricity * cos(e0))

        // Don't move particles when paused (unless negative)
        guard !state.isPaused || state.areNegative else { return }

        let dilationFactor = 1 / sqrt(max(1 - holeSize / planetDistance, 0.001))

        for i in particles.indices {
            particles[i].update(
                delta: delta,
                dilationFactor: dilationFactor,
                holeSize: holeSize,
                areNegative: state.areNegative,
                bh1IsActive: state.bh1IsActive
            )
        }
    }
}

// MARK: - Helper: polar → Cartesian

private func polarToXY(distance: Double, angle: Double) -> CGPoint {
    CGPoint(
        x: center + distance * sin(2 * .pi * angle),
        y: center + distance * cos(2 * .pi * angle)
    )
}

// MARK: - Cached hole symbol

/// Renders just the hole's radial-gradient disk at fixed 400×400 unscaled
/// canvas coordinates (the main Canvas applies `scaleBy` before drawing).
/// When used as a SwiftUI Canvas `symbols:` entry with a stable `.id`, the
/// rasterization is cached across frames — saves one radial-gradient
/// rasterization per frame (~1ms on iPhone) while holeSize/areNegative are
/// unchanged.
private struct HoleSymbol: View {
    let holeSize: Double
    let areNegative: Bool

    var body: some View {
        let displaySize = (holeSize - planetSize) / 2
        // Symbol frame is 4×displaySize so the glow halo (inset of -displaySize
        // on the Circle's bounding rect doubles its width) fits inside. The
        // Canvas's local coord origin is its top-left, so we center the hole
        // at (2*displaySize, 2*displaySize) in the symbol's frame. When the
        // main Canvas calls ctx.draw(symbol, at: center), the symbol's own
        // center aligns with `center` — so the hole lands at `center`.
        let frameSide = displaySize * 4
        let midpoint = frameSide / 2
        let innerRect = CGRect(
            x: midpoint - displaySize,
            y: midpoint - displaySize,
            width: displaySize * 2,
            height: displaySize * 2
        )
        let gradientCenter = CGPoint(x: midpoint, y: midpoint)
        Canvas { ctx, _ in
            if areNegative {
                let gradient = Gradient(stops: [
                    .init(color: Color(white: 1.0), location: 0),
                    .init(color: Color(white: 0.75), location: 0.85),
                    .init(color: Color(white: 0.67), location: 0.87),
                    .init(color: Color(white: 0.53, opacity: 0), location: 1),
                ])
                ctx.fill(
                    Circle().path(in: innerRect.insetBy(dx: -displaySize, dy: -displaySize)),
                    with: .radialGradient(gradient, center: gradientCenter,
                                          startRadius: 0, endRadius: displaySize * 2)
                )
            } else {
                let gradient = Gradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.9),
                    .init(color: Color(white: 0.39), location: 0.92),
                    .init(color: Color(white: 0.39, opacity: 0), location: 1),
                ])
                ctx.fill(
                    Circle().path(in: innerRect.insetBy(dx: -displaySize, dy: -displaySize)),
                    with: .radialGradient(gradient, center: gradientCenter,
                                          startRadius: 0, endRadius: displaySize * 2)
                )
            }
        }
        .frame(width: frameSide, height: frameSide)
    }
}

// MARK: - View

struct BlackHoleAnimationView: View {
    let state: BlackHoleState
    /// When false, the `TimelineView` is removed from the view hierarchy so the
    /// 120-particle sim stops running. Required on iPhone because `SubtabPager`
    /// keeps cached `UIHostingController`s alive for adjacent subtabs — without
    /// this gate, the animation keeps burning CPU even when the user has
    /// navigated away from the Black Hole subtab.
    let isActive: Bool

    /// Scene-phase pause — the TimelineView keeps invoking `model.update` at
    /// 30Hz even when the app is backgrounded (lock screen / home) because
    /// TimelineView's schedule runs on the render server independently of
    /// the display link. Collapsing this flag to false on `.inactive` /
    /// `.background` removes the `TimelineView` branch from the hierarchy
    /// entirely, freezing the particle sim until foreground return.
    @Environment(\.scenePhase) private var scenePhase
    private var isAnimating: Bool { isActive && scenePhase == .active }

    @State private var model = BlackHoleAnimModel()

    var body: some View {
        Group {
            if isAnimating {
                // Capped to ~30Hz: `pollDirect` and the JS game loop run at 30Hz,
                // and visual smoothness of this particle sim is indistinguishable
                // at 30Hz vs. display refresh. On a 120Hz ProMotion device this
                // is a 4x reduction in model.update + Canvas invocations.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    animatedCanvas
                        .onChange(of: timeline.date) { _, newDate in
                            model.update(now: newDate, state: state)
                        }
                }
            } else {
                // Static frame of last-known particle positions. No TimelineView,
                // no model.update — zero CPU while off-screen.
                animatedCanvas
            }
        }
        .onAppear {
            model.configure(state: state)
        }
        .onChange(of: isAnimating) { _, nowAnimating in
            // Reset the delta clock so the first tick after re-activating uses
            // a ~frame-sized delta, not the wall-clock elapsed since we stopped.
            if nowAnimating { model.resetClock() }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Canvas body (shared between active and static branches)

    /// Main Canvas. The hole is declared as a symbol so SwiftUI caches its
    /// radial-gradient raster and only re-rasterizes when `holeSize` /
    /// `areNegative` change. Particles are drawn per-frame (colors vary).
    private var animatedCanvas: some View {
        Canvas { ctx, size in
            let scale = size.width / canvasSize
            ctx.scaleBy(x: scale, y: scale)

            // Draw the cached hole symbol at the canvas center.
            if let symbol = ctx.resolveSymbol(id: holeSymbolID) {
                ctx.draw(symbol, at: CGPoint(x: center, y: center))
            }

            drawParticles(ctx: &ctx)
        } symbols: {
            // SwiftUI keys the rasterization on the subview's identity. `.id(...)`
            // bumps the identity when holeSize/areNegative change, invalidating
            // the cache only then; otherwise the symbol is a cache hit every frame.
            HoleSymbol(holeSize: model.holeSize, areNegative: state.areNegative)
                .id(holeSymbolCacheKey)
                .tag(holeSymbolID)
        }
    }

    /// Stable integer tag used to look the symbol up each frame.
    private var holeSymbolID: Int { 0 }

    /// View-identity key — when holeSize or areNegative changes, SwiftUI
    /// treats the HoleSymbol as a new view and re-rasterizes it.
    private var holeSymbolCacheKey: String {
        // Quantize holeSize to avoid tiny float noise churning the cache.
        let q = (model.holeSize * 100).rounded()
        return "\(state.areNegative ? "n" : "p")-\(q)"
    }

    // MARK: - Draw particles

    private func drawParticles(ctx: inout GraphicsContext) {
        let hs = model.holeSize

        for p in model.particles {
            let pos = polarToXY(distance: p.distance, angle: p.angle)

            // Determine color
            let color: Color
            if !state.bh1IsActive {
                color = Color(white: 0.5)
            } else if p.distance > hs {
                let dist = min(floor(127 * (p.distance - hs) / semimajorAxis), 127)
                let r = (135 - dist) / 255
                let g = dist / 255
                let b = dist / 255
                color = Color(red: r, green: g, blue: b)
            } else {
                let dist = floor(255 * sqrt(p.distance / hs))
                color = Color(red: dist / 255, green: 0, blue: 0)
            }

            // Draw trail or dot
            if p.respawnTick || !state.bh1IsActive {
                // Just a dot
                let dotRect = CGRect(x: pos.x - particleSize, y: pos.y - particleSize,
                                     width: particleSize * 2, height: particleSize * 2)
                ctx.fill(Circle().path(in: dotRect), with: .color(color))
            } else if p.isInside && !state.bh2IsActive {
                // Skip trail for inside particles when BH2 inactive
                continue
            } else {
                // Trail line
                let trailAngle = p.isInside ? p.angle : p.preLastAngle
                let lastPos = polarToXY(distance: p.preLastDistance, angle: trailAngle)
                var path = Path()
                path.move(to: pos)
                path.addLine(to: lastPos)
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: particleSize * 2, lineCap: .round))
            }
        }
    }

}
