//
//  CreditsOverlay.swift
//  AntiMatter
//
//  GameEnd credits roll. Presented as a full-screen `.fullScreenCover` from
//  ContentView (iPad) and PhoneShell (iPhone) when
//  `engine.gameEndCreditsActive` is true.
//
//  Mirrors:
//    src/components/tabs/celestial-pelle/CreditsContainer.vue
//    src/components/CreditsDisplay.vue
//    src/core/secret-formula/credits.js
//
//  **No audio.** Web's `credits.mp3` is intentionally not loaded — scroll
//  position is driven directly by `engine.endStateValue` (4.5..14.5 maps to
//  scroll progress 0..1). This gives us:
//    - Cold-launch fast-forward for free (high endState → terminal scroll).
//    - Spectate-rewind scroll-back for free (endState rewinds → scroll back).
//
//  **No X dismiss button.** After CREDITS_END (14.5) the overlay is locked
//  — the player must pick "New Game" (which routes through the speedrun
//  start modal) or "Spectate" (which rewinds endState back to playable
//  state). Web's reload-the-page escape doesn't exist on iOS.
//

import SwiftUI

// MARK: - Data model

struct CreditsRole: Identifiable {
    let id: Int
    let title: String
    var people: [CreditsPerson]
}

struct CreditsPerson: Identifiable {
    let id = UUID()
    let name: String
    let name2: String?
}

enum CreditsLoader {
    /// Load + group the bundled `credits.json` into roles ordered by index.
    /// `roles` in JSON is heterogeneous — string role names plus a numeric
    /// `"count": N` entry — so we cast through `[String: Any]` and pick out
    /// the integer-keyed string values, ignoring `count` and any other meta
    /// fields. (A direct `[String: String]` cast silently fails the whole
    /// load and leaves the user with just "Infinity Dimensions" → "Thanks
    /// for playing!" with no names in between.)
    static func load() -> [CreditsRole] {
        guard let url = Bundle.main.url(forResource: "credits", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rolesAny = obj["roles"] as? [String: Any],
              let people = obj["people"] as? [[String: Any]]
        else { return [] }

        // Build [roleId: [Person]]
        var byRole: [Int: [CreditsPerson]] = [:]
        for entry in people {
            guard let name = entry["name"] as? String else { continue }
            let name2 = entry["name2"] as? String
            let person = CreditsPerson(name: name, name2: name2)
            if let arr = entry["roles"] as? [Int] {
                for r in arr { byRole[r, default: []].append(person) }
            }
        }
        // Sort by role id (web order). Sort each role's people alphabetically.
        // Filter to entries whose key is parseable as Int and whose value is
        // a String — skips `"count"` and any future non-role metadata.
        return rolesAny.compactMap { (k, v) -> CreditsRole? in
            guard let roleId = Int(k), let title = v as? String else { return nil }
            let sorted = (byRole[roleId] ?? []).sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return CreditsRole(id: roleId, title: title, people: sorted)
        }
        .sorted { $0.id < $1.id }
    }
}

// MARK: - Overlay

struct CreditsOverlay: View {
    let engine: GameEngine
    @Environment(\.scenePhase) private var scenePhase
    /// Captured here so we can explicitly re-inject the env across the
    /// `.sheet` boundary below — SwiftUI does NOT propagate custom env
    /// keys automatically into sheets / fullScreenCovers. Without this,
    /// `SpeedrunStartModal`'s `@Environment(\.sidebarState)` falls back to
    /// nil → fresh `SidebarState()` → `selectSubtab` writes to a phantom
    /// object and the app's real sidebar stays on whatever tab the user
    /// was on. (Repro: start a Speedrun from credits → Reality tab still
    /// active; iPhone tab bar still on whichever page contained the
    /// pre-reset active tab.)
    @Environment(\.sidebarState) private var sidebarState
    /// Loaded eagerly at view-initialiser time so the modal's first frame
    /// already has the 154-name × 16-role roster ready. Loading inside
    /// `.onAppear` was visibly delayed — the modal slid in empty, then
    /// pollDirect would tick before content materialised.
    @State private var roles: [CreditsRole] = CreditsLoader.load()
    @State private var showSpeedrunStartModal = false

    var body: some View {
        ZStack {
            // Pelle silhouette + dark backdrop.
            Color.black.ignoresSafeArea()
            celestialBackdrop
                .ignoresSafeArea()
            scrollColumn
            controls
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSpeedrunStartModal) {
            // Credits "New Game" routes through the shared modal so the
            // player can pick Speedrun Mode (default) or Fresh Save. Both
            // paths hard-reset and dismiss the credits overlay via the
            // engine's lifecycle (resetUnlockFlags + tab navigation).
            //
            // CRITICAL: re-inject `.sidebarState` so the modal's tab
            // navigation lands on the REAL `SidebarState` — see the
            // property comment above.
            SpeedrunStartModal(engine: engine, mode: .offerBoth)
                .environment(\.sidebarState, sidebarState)
        }
    }

    // MARK: Backdrop animations

    private var celestialBackdrop: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                paused: scenePhase != .active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                celestialSigil("teresa",   size: 240, time: t,
                               offset: CGSize(width: -100, height: -180),
                               style: .teresa)
                celestialSigil("effarig",  size: 220, time: t,
                               offset: CGSize(width: 110, height: -160),
                               style: .effarig)
                celestialSigil("enslaved", size: 240, time: t,
                               offset: CGSize(width: -120, height: 0),
                               style: .enslaved)
                celestialSigil("v",        size: 200, time: t,
                               offset: CGSize(width: 130, height: 30),
                               style: .v)
                celestialSigil("ra",       size: 220, time: t,
                               offset: CGSize(width: -90, height: 200),
                               style: .ra)
                celestialSigil("laitela",  size: 200, time: t,
                               offset: CGSize(width: 100, height: 220),
                               style: .laitela)
                celestialSigil("pelle",    size: 280, time: t,
                               offset: .zero, style: .pelle)
            }
        }
    }

    private enum SigilStyle { case teresa, effarig, enslaved, v, ra, laitela, pelle }

    @ViewBuilder
    private func celestialSigil(_ key: String, size: CGFloat, time: TimeInterval,
                                offset: CGSize, style: SigilStyle) -> some View {
        let glyph = CelestialPalette.symbol(for: key)
        let color = CelestialPalette.color(for: key)
        let sf = CelestialPalette.sfSymbol(for: key)
        let base = Group {
            if let sf {
                Image(systemName: sf)
                    .resizable().scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Text(glyph)
                    .font(.system(size: size, weight: .heavy))
            }
        }
        .foregroundStyle(color.opacity(0.18))

        // Per-celestial keyframes adapted from CreditsContainer.vue
        switch style {
        case .teresa:
            // 10s rotation cycle (61° → 322° → 61°)
            let phase = (time.truncatingRemainder(dividingBy: 10)) / 10
            let angle = 61 + sin(phase * 2 * .pi) * 130
            base
                .rotationEffect(.degrees(angle))
                .offset(offset)
        case .effarig:
            // 4s opacity pulse
            let phase = (time.truncatingRemainder(dividingBy: 4)) / 4
            base
                .opacity(0.4 + 0.6 * (0.5 - 0.5 * cos(phase * 2 * .pi)))
                .offset(offset)
        case .enslaved:
            // 10s full rotation
            let phase = (time.truncatingRemainder(dividingBy: 10)) / 10
            base
                .rotationEffect(.degrees(phase * 360))
                .offset(offset)
        case .v:
            // 15s scale breathing 0.8 ↔ 1.2
            let phase = (time.truncatingRemainder(dividingBy: 15)) / 15
            let scale = 0.8 + 0.4 * (0.5 - 0.5 * cos(phase * 2 * .pi))
            base
                .scaleEffect(scale)
                .offset(offset)
        case .ra:
            // 10s opacity + scale pulse
            let phase = (time.truncatingRemainder(dividingBy: 10)) / 10
            let pulse = 0.5 - 0.5 * cos(phase * 2 * .pi)
            base
                .opacity(0.4 + 0.5 * pulse)
                .scaleEffect(0.9 + 0.2 * pulse)
                .offset(offset)
        case .laitela:
            // 5s translate animation (vertical bob)
            let phase = (time.truncatingRemainder(dividingBy: 5)) / 5
            let dy = sin(phase * 2 * .pi) * 20
            base
                .offset(CGSize(width: offset.width, height: offset.height + dy))
        case .pelle:
            // 5s 3D Y-axis rotation (full 360)
            let phase = (time.truncatingRemainder(dividingBy: 5)) / 5
            base
                .rotation3DEffect(.degrees(phase * 360), axis: (x: 0, y: 1, z: 0))
                .offset(offset)
        }
    }

    // MARK: Scroll column

    /// Scroll progress 0..1.05 derived from `endStateValue`. Maps the
    /// CREDITS_START (4.5) → CREDITS_END (14.5) window onto a 0..1 sweep,
    /// allowing a slight 5% overscroll past the end so the "Thank you"
    /// closer settles fully above the bottom edge. Cold-launch fast-forward
    /// (high endState on first poll) and Spectate rewind (endState
    /// decreasing) both work for free because the same single source —
    /// endStateValue — drives every scroll position.
    private var scrollProgress: Double {
        let span = GameEndMarker.creditsEnd - GameEndMarker.creditsStart
        let raw = (engine.endStateValue - GameEndMarker.creditsStart) / span
        return max(0, min(raw, 1.05))
    }

    private var scrollColumn: some View {
        GeometryReader { geo in
            // Estimate content height — 80pt per role header + ~26pt per
            // person row, plus a screen-height of leading + trailing space
            // so the credits start fully below and finish fully above.
            let approxHeight = roles.reduce(0) { acc, r in
                acc + 80 + Double(r.people.count) * 26
            } + Double(geo.size.height) * 2
            let offsetY = geo.size.height - CGFloat(scrollProgress) * CGFloat(approxHeight)

            VStack(spacing: 28) {
                Text("Infinity\nDimensions")
                    .font(.system(size: 36, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)
                ForEach(roles) { role in
                    creditsRoleBlock(role)
                }
                Text("Thank you so much\nfor playing!")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(GameColor.pelle.readableOnDark())
                    .multilineTextAlignment(.center)
                    .padding(.top, 60)
            }
            .frame(maxWidth: .infinity)
            .offset(y: offsetY)
            // Smooth between endState ticks (~30Hz) so scrolling reads as
            // continuous rather than stepping.
            .animation(.linear(duration: 0.1), value: scrollProgress)
        }
    }

    @ViewBuilder
    private func creditsRoleBlock(_ role: CreditsRole) -> some View {
        VStack(spacing: 6) {
            Text(role.title.uppercased())
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            if role.people.count > 10 {
                // Two-column grid for large role groups (matches web layout).
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: 4) {
                    ForEach(role.people) { person in personRow(person) }
                }
                .frame(maxWidth: 480)
            } else {
                ForEach(role.people) { person in personRow(person) }
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func personRow(_ person: CreditsPerson) -> some View {
        if let n2 = person.name2 {
            Text("\(person.name) (\(n2))")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
        } else {
            Text(person.name)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack {
            // No X dismiss affordance, no Spectate button. The credits
            // overlay is locked — the only exit is "New Game", which
            // routes through the speedrun start modal (Speedrun Mode or
            // Fresh Save). Without audio there's no narrative arc to time
            // a late button reveal to, so the button is available from
            // the instant credits begin (endState >= 4.5).
            //
            // (Web shows New Game at 13.5 and Spectate at 13.9 to coincide
            // with the song's climax. Iaudio + Spectate are both removed
            // on iOS; doomed-reality save is intentionally not preserved.)
            Spacer()
            Button {
                showSpeedrunStartModal = true
            } label: {
                Text("New Game")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(GameColor.pelle, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 40)
        }
    }
}
