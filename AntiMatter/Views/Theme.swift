//
//  Theme.swift
//  AntiMatter
//
//  Game colors backed by Xcode asset catalog color sets.
//  All values sourced from the web Modern UI dark theme (t-normal / new-ui-styles.css).
//  To add a theme variant, add appearance entries in the .colorset Contents.json.
//

import SwiftUI

// MARK: - Color(hex:) convenience

extension Color {
    /// Parse "#RRGGBB" or "RRGGBB" hex string into a Color.
    init(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let scanner = Scanner(string: h)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    /// Parse "rgb(R,G,B)" / "rgb(R, G, B)" / "rgb(R G B)" into a Color.
    /// Falls back to white if parsing fails. The Reality glyph color is
    /// emitted by JS as `rgb(...)` because it cycles through interpolated
    /// values; standard glyph types come through as `#rrggbb`.
    init(cssColor: String) {
        let trimmed = cssColor.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            self.init(hex: trimmed)
            return
        }
        if trimmed.lowercased().hasPrefix("rgb") {
            let inside = trimmed
                .replacingOccurrences(of: "rgba", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "rgb", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
            let parts = inside
                .replacingOccurrences(of: ",", with: " ")
                .split(separator: " ")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count >= 3 {
                self.init(
                    red:   max(0, min(parts[0] / 255, 1)),
                    green: max(0, min(parts[1] / 255, 1)),
                    blue:  max(0, min(parts[2] / 255, 1))
                )
                return
            }
        }
        self.init(hex: trimmed)
    }

    /// Returns a version of this color guaranteed to be readable on a dark
    /// background. If the color's perceived luminance is below `minLuminance`,
    /// blends it toward white until the threshold is met. Used for sacrifice
    /// totals + any other colored text laid over the dark game theme — some
    /// glyph type colors (notably the Reality glyph's animated interpolation)
    /// can land on muted hues that disappear against #111014.
    func readableOnDark(minLuminance: Double = 0.55) -> Color {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let ui = UIColor(self)
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        // Perceived luminance per ITU-R BT.601
        let lum = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        guard lum < minLuminance else { return self }
        // Blend with white by however much we need to clear the threshold
        let t = min(1, (minLuminance - lum) / (1 - lum))
        return Color(
            red:   Double(r) + (1 - Double(r)) * t,
            green: Double(g) + (1 - Double(g)) * t,
            blue:  Double(b) + (1 - Double(b)) * t
        )
        #else
        return self
        #endif
    }
}

enum GameColor {

    // MARK: - Core theme variables (--color-* in t-normal)

    /// #df5050 — --color-antimatter / --color-accent
    static let antimatter = Color("AntimatterRed")

    /// #b67f33 — --color-infinity
    static let infinity = Color("InfinityGold")

    /// #b341e0 — --color-eternity
    static let eternity = Color("EternityPurple")

    /// #0ba00e — --color-reality
    static let reality = Color(red: 0.043, green: 0.627, blue: 0.055)

    /// #9071e0 — Celestials accent
    static let celestials = Color(red: 0.565, green: 0.443, blue: 0.878)

    // MARK: - Per-celestial colors (from web CSS --color-* vars)

    /// #5151ec — Teresa base
    static let teresa = Color(red: 0.318, green: 0.318, blue: 0.925)
    /// #d13737 — Effarig base
    static let effarig = Color(red: 0.820, green: 0.216, blue: 0.216)
    /// #f1aa7f — The Nameless Ones (Enslaved)
    static let enslaved = Color(red: 0.945, green: 0.667, blue: 0.498)
    /// #ead584 — V
    static let v = Color(red: 0.918, green: 0.835, blue: 0.518)
    /// #9063de — Ra
    static let ra = Color(red: 0.565, green: 0.388, blue: 0.871)
    /// #22aaff — Lai'tela (Dark Matter cyan)
    static let laitela = Color(red: 0.133, green: 0.667, blue: 1.0)
    /// #8c2020 — Pelle (doomed crimson)
    static let pelle = Color(red: 0.549, green: 0.125, blue: 0.125)
    /// #00bcd4 — `--color-pelle--secondary`. The cyan stop in Pelle's
    /// crimson→cyan gradient. Used by the Galaxy Generator card fills and
    /// the totals/value text gradient.
    static let pelleSecondary = Color(red: 0.0, green: 0.737, blue: 0.831)
    /// #004b55 — dark-mode background for Pelle gradient bars (web
    /// `.s-base--dark .c-increase-cap`). Galaxy Generator fill bar BG.
    static let pelleBarBg = Color(red: 0.0, green: 0.294, blue: 0.333)

    /// #1bbb36 — --color-good (enabled green, button hover, progress fill)
    static let good = Color("Good")

    /// #138626 — --color-good-dark (button border, progress fill background)
    static let goodDark = Color("GoodDark")

    /// #b84b5f — --color-bad (disabled border, error accent)
    static let disabledBorder = Color("DisabledBorder")

    /// #007308 — web `.c-achievement-grid__row--completed` background. Solid dark green
    /// fill rendered behind a fully-unlocked achievement row (normal + secret tabs).
    static let achievementRowCompleted = Color(red: 0.0, green: 0.451, blue: 0.031)

    // MARK: - Backgrounds

    /// #1d1b22 — --color-base (button bg, sidebar bg, modal bg, tooltip bg)
    static let sidebarBackground = Color("SidebarBackground")

    /// #111014 — body background (body.t-normal background-color)
    static let baseBackground = Color("BaseBackground")

    /// #2c2933 — active tab background
    static let activeTab = Color("ActiveTab")

    // MARK: - Button states

    /// #752626 — disabled button background (new-ui-styles.css .o-primary-btn--disabled)
    static let disabled = Color("DisabledButton")

    /// #37474f — locked/unavailable button (muted gray, visually distinct from vibrant disabled red)
    static let locked = Color("Locked")

    // MARK: - Borders

    /// #383232 — modal/autobuyer box border
    static let modalBorder = Color("ModalBorder")

    // MARK: - Infinity upgrade column accents

    /// #d50000 — infinity upgrade column 2 (red)
    static let infUpgradeCol2 = Color("InfUpgradeCol2")

    /// #ffd600 — infinity upgrade column 3 (gold/yellow)
    static let infUpgradeCol3 = Color("InfUpgradeCol3")

    /// #00e5ff — infinity upgrade column 4 (cyan)
    static let infUpgradeCol4 = Color("InfUpgradeCol4")

    /// Break Infinity multiplier row (rebuyable upgrades)
    static let multiplierCyan = Color("MultiplierCyan")    // #17b3b5 — border
    static let multiplierRed = Color("MultiplierRed")      // #c93a3a — text

    /// #2196f3 — Replicanti accent (c-replicanti-description__accent)
    static let replicanti = Color(red: 0.129, green: 0.588, blue: 0.953)

    /// #3aacd6 — Time Theorem buy button (c-tt-buy-button--unlocked in t-dark)
    static let timeTheorem = Color(red: 0.227, green: 0.675, blue: 0.839)

    /// #263238 — Time Theorem buy button locked bg (c-tt-buy-button--locked in t-dark)
    static let timeTheoremLocked = Color(red: 0.149, green: 0.196, blue: 0.220)

    // MARK: - Dilation

    /// #64dd17 — dilation text/accent (o-dilation-btn in t-dark)
    static let dilationGreen = Color(red: 0.392, green: 0.867, blue: 0.090)

    /// #3e8a0f — dilation border (o-dilation-btn border in t-dark)
    static let dilationBorder = Color(red: 0.243, green: 0.541, blue: 0.059)

    /// #23292a — dilation disabled/unavailable bg (o-dilation-btn--disabled in t-dark)
    static let dilationDisabledBg = Color(red: 0.137, green: 0.161, blue: 0.165)

    // MARK: - Card states

    /// #5f5f5f — unavailable/disabled card background (shared across upgrade cards)
    static let unavailableBg = Color(red: 0.373, green: 0.373, blue: 0.373)

    /// #181818 — unavailable card text (dark text on gray bg)
    static let unavailableText = Color(red: 0.094, green: 0.094, blue: 0.094)

    /// #691fa5 — eternity upgrade dark purple border (t-dark unavailable/bought border)
    static let darkPurpleBorder = Color(red: 0.412, green: 0.122, blue: 0.647)

    /// ~#b34b59 — bad/warning pink (reset reality, glyph reminder bad state)
    static let badPink = Color(red: 0.7, green: 0.3, blue: 0.35)

    /// #094e0b — reality upgrade bought border (dark green)
    static let boughtBorderGreen = Color(red: 0.035, green: 0.306, blue: 0.043)

    /// #952020 — reality upgrade locked/impossible bg (dark red)
    static let lockedBgRed = Color(red: 0.584, green: 0.125, blue: 0.125)

    /// #A2A229 — reality upgrade possible bg (yellow-gold)
    static let possibleBg = Color(red: 0.635, green: 0.635, blue: 0.161)

    /// #e3e638 — autobuyer toggle on-state tint when autobuyers are globally
    /// paused (yellow signals "would be running but paused"). Mirrors web's
    /// `--color-good-paused`. Off toggles stay grey natively.
    static let pausedActive = Color(red: 0.890, green: 0.902, blue: 0.220)

    // MARK: - Automator

    /// Active toggle highlight for automator controls
    static let automatorActive = Color(hex: "#1a6b1a")

    /// Subtle green background for the currently-executing line
    static let automatorActiveLine = Color(red: 0.1, green: 0.3, blue: 0.1).opacity(0.35)

    /// Subtle red background for lines with errors
    static let automatorErrorLine = Color(red: 0.4, green: 0.1, blue: 0.1).opacity(0.35)

    // Syntax highlighting colors (matching VS Code / CodeMirror dark themes)
    /// #4ec9b0 — command keywords (wait, if, auto, studies, etc.)
    static let syntaxCommand = Color(hex: "#4ec9b0")
    /// #b5cea8 — numeric literals
    static let syntaxNumber = Color(hex: "#b5cea8")
    /// #6a9955 — comments (lines starting with # or //)
    static let syntaxComment = Color(hex: "#6a9955")
    /// #c586c0 — game values / currencies (am, ip, ep, rm, etc.)
    static let syntaxCurrency = Color(hex: "#c586c0")
    /// #d4d4aa — comparison operators
    static let syntaxComparison = Color(hex: "#d4d4aa")
    /// #ce9178 — string literals / study paths
    static let syntaxString = Color(hex: "#ce9178")
}

// MARK: - Button Themes

/// Bundles enabled/disabled colors for GameButton so each context
/// (standard, TT shop, eternity upgrades, dilation) gets correct styling.
struct ButtonTheme {
    let enabledBorder: Color
    let enabledBackground: Color
    let enabledText: Color
    let pressedBackground: Color     // web hover color — shown on tap
    let pressedText: Color           // web hover text — typically inverted
    let disabledBorder: Color
    let disabledBackground: Color
    let disabledText: Color

    /// Default green/red theme used by most game buttons.
    /// Web hover: t-dark .o-primary-btn:hover { background-color: #1b5e20 }
    static let standard = ButtonTheme(
        enabledBorder: .green,
        enabledBackground: GameColor.sidebarBackground,
        enabledText: .white,
        pressedBackground: Color(red: 0.106, green: 0.369, blue: 0.125),  // #1b5e20
        pressedText: .white,
        disabledBorder: GameColor.disabledBorder,
        disabledBackground: GameColor.disabled,
        disabledText: .white
    )

    /// Time Theorem shop buttons — eternity purple border/text.
    /// Web hover: t-dark .o-primary-btn:hover → #673ab7
    static let timeTheorem = ButtonTheme(
        enabledBorder: GameColor.eternity,
        enabledBackground: Color(red: 0.086, green: 0.086, blue: 0.086),  // #161616
        enabledText: GameColor.eternity,
        pressedBackground: Color(red: 0.404, green: 0.227, blue: 0.718),  // #673ab7
        pressedText: .white,
        disabledBorder: GameColor.eternity,
        disabledBackground: GameColor.timeTheoremLocked,                   // #263238
        disabledText: .black
    )

    /// #b341e0 — Eternity upgrade buttons (o-eternity-upgrade in t-dark).
    /// Web hover: t-dark → #673ab7
    static let eternityUpgrade = ButtonTheme(
        enabledBorder: GameColor.eternity,
        enabledBackground: .black,
        enabledText: GameColor.eternity,
        pressedBackground: Color(red: 0.404, green: 0.227, blue: 0.718),  // #673ab7
        pressedText: .white,
        disabledBorder: GameColor.darkPurpleBorder,
        disabledBackground: GameColor.timeTheoremLocked,                   // #263238
        disabledText: .black
    )

    /// #64dd17 / #3e8a0f — Dilation upgrade buttons (o-dilation-btn in t-dark).
    /// Web hover: white background
    static let dilation = ButtonTheme(
        enabledBorder: GameColor.dilationBorder,
        enabledBackground: .black,
        enabledText: GameColor.dilationGreen,
        pressedBackground: .white,
        pressedText: .black,
        disabledBorder: GameColor.dilationBorder,
        disabledBackground: GameColor.dilationDisabledBg,
        disabledText: .black
    )

    /// Teresa buttons — #5151ec border/text, near-black bg.
    static let teresa = ButtonTheme(
        enabledBorder: GameColor.teresa,
        enabledBackground: Color(red: 0.086, green: 0.086, blue: 0.086),  // #161616
        enabledText: GameColor.teresa,
        pressedBackground: GameColor.teresa,
        pressedText: .white,
        disabledBorder: GameColor.teresa.opacity(0.5),
        disabledBackground: GameColor.timeTheoremLocked,
        disabledText: .white.opacity(0.6)
    )

    /// Effarig shop / run buttons — #d13737 border/text, near-black bg.
    static let effarig = ButtonTheme(
        enabledBorder: GameColor.effarig,
        enabledBackground: Color(red: 0.086, green: 0.086, blue: 0.086),  // #161616
        enabledText: GameColor.effarig,
        pressedBackground: GameColor.effarig,
        pressedText: .white,
        disabledBorder: GameColor.effarig.opacity(0.5),
        disabledBackground: GameColor.unavailableBg,
        disabledText: .white.opacity(0.6)
    )

    /// The Nameless Ones (Enslaved) buttons — #f1aa7f border/text, near-black bg.
    static let enslaved = ButtonTheme(
        enabledBorder: GameColor.enslaved,
        enabledBackground: Color(red: 0.086, green: 0.086, blue: 0.086),  // #161616
        enabledText: GameColor.enslaved,
        pressedBackground: GameColor.enslaved,
        pressedText: .black,
        disabledBorder: GameColor.enslaved.opacity(0.5),
        disabledBackground: GameColor.unavailableBg,
        disabledText: .white.opacity(0.6)
    )

    /// V — gold accent (#ead584) matching GameColor.v.
    static let v = ButtonTheme(
        enabledBorder: GameColor.v,
        enabledBackground: Color(red: 0.086, green: 0.086, blue: 0.086),  // #161616
        enabledText: GameColor.v,
        pressedBackground: GameColor.v,
        pressedText: .black,
        disabledBorder: GameColor.unavailableBg,
        disabledBackground: Color(red: 0.149, green: 0.196, blue: 0.220),  // #263238
        disabledText: .black
    )

    /// Lai'tela — light-blue accent matching GameColor.laitela.
    static let laitela = ButtonTheme(
        enabledBorder: GameColor.laitela,
        enabledBackground: Color(red: 0.086, green: 0.086, blue: 0.086),  // #161616
        enabledText: GameColor.laitela,
        pressedBackground: GameColor.laitela,
        pressedText: .black,
        disabledBorder: GameColor.laitela.opacity(0.4),
        disabledBackground: GameColor.unavailableBg,
        disabledText: .white.opacity(0.6)
    )

    /// Pelle — doomed crimson (#8c2020). White text on tap (high contrast against
    /// the dark crimson). Disabled background uses the muted unavailable gray
    /// rather than vivid red, since "disabled" inside Pelle's tab usually means
    /// "locked behind another upgrade", not "this is broken".
    static let pelle = ButtonTheme(
        enabledBorder: GameColor.pelle,
        enabledBackground: Color(red: 0.086, green: 0.086, blue: 0.086),  // #161616
        enabledText: GameColor.pelle,
        pressedBackground: GameColor.pelle,
        pressedText: .white,
        disabledBorder: GameColor.pelle.opacity(0.5),
        disabledBackground: GameColor.unavailableBg,
        disabledText: .white.opacity(0.6)
    )

    /// Automator controls — reality-green accent for active toggles.
    static let automator = ButtonTheme(
        enabledBorder: GameColor.reality,
        enabledBackground: GameColor.sidebarBackground,
        enabledText: GameColor.reality,
        pressedBackground: GameColor.automatorActive,
        pressedText: .white,
        disabledBorder: GameColor.disabledBorder,
        disabledBackground: GameColor.disabled,
        disabledText: .white
    )
}

// MARK: - Rounded Border Modifier

/// Clips to a rounded rectangle and overlays a stroke border in one call.
/// Replaces the repeated `.clipShape(RoundedRectangle(...)).overlay(RoundedRectangle(...).stroke(...))` pattern.
struct RoundedBorderModifier: ViewModifier {
    let color: Color
    let cornerRadius: CGFloat
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(color, lineWidth: lineWidth)
            )
    }
}

extension View {
    func roundedBorder(_ color: Color, cornerRadius: CGFloat = 6, lineWidth: CGFloat = 1) -> some View {
        modifier(RoundedBorderModifier(color: color, cornerRadius: cornerRadius, lineWidth: lineWidth))
    }
}

// MARK: - Pelle disabled banner (shared)

/// Pelle-red advisory banner used by tabs that are nullified or partially
/// disabled while Doomed. Single line of explanatory text, framed in
/// `GameColor.pelle`. Reused across Eternity Upgrades, Imaginary Upgrades,
/// Time Dilation, EC, BH, etc.
struct PelleSimpleDisabledBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(GameColor.pelle.readableOnDark())
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

// MARK: - Pelle silhouette background

/// Giant `♅` watermark drawn faintly behind a tab's content while Doomed.
/// Mirrors the web "disabled tab" treatment where the celestial sigil fills
/// the viewport, signaling "this whole feature is sealed by Doom."
/// Apply via `.modifier(PelleSilhouetteBackground(active: engine.pelleDoomed))`
/// or the convenience `View.pelleSilhouetteBackground(active:)`.
struct PelleSilhouetteBackground: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .background(silhouette)
    }

    @ViewBuilder
    private var silhouette: some View {
        if active {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height) * 0.95
                Text("♅")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(GameColor.pelle.opacity(0.18))
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Adds a faint giant `♅` silhouette behind the view's content when
    /// `active` is true (Pelle is Doomed). No-op otherwise.
    func pelleSilhouetteBackground(active: Bool) -> some View {
        modifier(PelleSilhouetteBackground(active: active))
    }
}
