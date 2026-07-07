//
//  KeyboardShortcuts.swift
//  AntiMatter
//
//  Source of truth for hardware-keyboard support: the binding table consumed
//  by `KeyCommandHost` (for `UIKeyCommand` registration) and by
//  `KeyboardShortcutsSheet` (for the Options-tab listing).
//
//  Conventions mirror web `src/core/hotkeys.js`:
//    - Bare letters / digits for primary actions.
//    - `shift+` for single-buy / toggle variants.
//    - `alt+` (Option) for autobuyer toggles.
//    - `shift+alt+` for autobuyer buy-singles toggles.
//    - `mod+` (Cmd on Mac/iPad) for save / export / sheet utilities.
//
//  Bindings are always registered. Visibility predicates only gate the
//  Options sheet display — pressing a hidden binding still works.
//
//  Out of scope for v1 (documented):
//    - `f`, `9`, `shift+d`, `shift+g`, `cmd+opt+a`, `F10`, electron-zoom
//    - Modifier-state UI relabel (no shift-held button label flipping)
//    - `cmd+z` / `cmd+y` Automator script-revision undo (UITextView native
//      undo wins; reintroduce if/when a revision-history affordance ships)
//

import UIKit

// MARK: - Shortcut category

enum KeyboardShortcutCategory: String, CaseIterable, Hashable {
    case buying     = "Buying"
    case prestige   = "Prestige"
    case autobuyers = "Autobuyers"
    case navigation = "Navigation"
    case ui         = "UI"

    /// Display order in the Options sheet.
    var sortIndex: Int {
        switch self {
        case .buying:     0
        case .prestige:   1
        case .autobuyers: 2
        case .navigation: 3
        case .ui:         4
        }
    }
}

// MARK: - Visibility predicate

/// Visibility predicates resolve against a small dictionary of named flags
/// (populated by `GameEngine.loadKeyboardShortcutVisibility`). Keeping the
/// predicate symbolic — rather than a closure — means we don't capture
/// engine references at module-init time.
enum KeyboardShortcutVisibility {
    case always
    case flag(String)
    /// Logical OR of multiple flags. Empty list ⇒ never visible.
    case anyFlag([String])

    func evaluate(_ flags: [String: Bool]) -> Bool {
        switch self {
        case .always: return true
        case .flag(let key): return flags[key] ?? false
        case .anyFlag(let keys): return keys.contains { flags[$0] ?? false }
        }
    }
}

// MARK: - Shortcut descriptor

/// One row of the binding table. Drives both `UIKeyCommand` construction
/// and the Options-tab listing.
struct KeyboardShortcutDescriptor: Identifiable {
    /// Stable identifier (used by ForEach + SwiftUI diffing).
    let id: String

    /// User-facing name. Localizable at the call site.
    let name: String

    /// Display order group.
    let category: KeyboardShortcutCategory

    /// The actual key character or named input. For arrows / esc, use a
    /// `UIKeyCommand.input*` constant; for everything else, the literal
    /// character we want UIKit to match against the keystroke's generated
    /// output (case-insensitive — UIKit lowercases for matching).
    let input: String

    /// Modifier flags. Empty for bare letters.
    let modifiers: UIKeyModifierFlags

    /// Whether to show this binding in the Options sheet.
    let visibility: KeyboardShortcutVisibility

    /// Engine action invoked on keystroke. Closure receives the engine + the
    /// sidebar state (when present) so navigation/dismiss actions can route
    /// without grabbing references at descriptor-build time.
    let action: KeyboardShortcutAction
}

/// Action closures are split by what context they need so we can keep them
/// simple at the call site. All run on main.
enum KeyboardShortcutAction {
    case engine((GameEngine) -> Void)
    case engineSidebar((GameEngine, SidebarState?) -> Void)
}

// MARK: - The table

enum KeyboardShortcuts {

    /// Full binding table. Build once at module-init and reuse — the
    /// closures don't capture per-call state.
    static let all: [KeyboardShortcutDescriptor] = buildTable()

    private static func buildTable() -> [KeyboardShortcutDescriptor] {
        var rows: [KeyboardShortcutDescriptor] = []

        // MARK: - Buying

        // 1-8 → buy max dimension; shift+1-8 → buy one.
        for tier in 1...8 {
            rows.append(.init(
                id: "buyMaxDim\(tier)",
                name: "Buy max \(Self.dimensionName(tier))",
                category: .buying,
                input: "\(tier)",
                modifiers: [],
                visibility: .always,
                action: .engine { $0.buyMaxDimension(tier) }
            ))
            rows.append(.init(
                id: "buyOneDim\(tier)",
                name: "Buy one \(Self.dimensionName(tier))",
                category: .buying,
                input: "\(tier)",
                modifiers: .shift,
                visibility: .always,
                action: .engine { $0.buyDimension(tier) }
            ))
        }

        rows.append(.init(
            id: "buyMaxTickspeed",
            name: "Buy max Tickspeed",
            category: .buying,
            input: "t",
            modifiers: [],
            visibility: .flag("tickspeedUnlocked"),
            action: .engine { $0.buyMaxTickSpeed() }
        ))
        rows.append(.init(
            id: "buyOneTickspeed",
            name: "Buy one Tickspeed",
            category: .buying,
            input: "t",
            modifiers: .shift,
            visibility: .flag("tickspeedUnlocked"),
            action: .engine { $0.buyTickSpeed() }
        ))

        rows.append(.init(
            id: "maxAll",
            name: "Max all",
            category: .buying,
            input: "m",
            modifiers: [],
            visibility: .always,
            action: .engine { $0.maxAll() }
        ))

        rows.append(.init(
            id: "sacrifice",
            name: "Dimensional Sacrifice",
            category: .buying,
            input: "s",
            modifiers: [],
            visibility: .flag("sacrificeUnlocked"),
            action: .engine { $0.sacrifice() }
        ))

        rows.append(.init(
            id: "dimBoost",
            name: "Dimension Boost",
            category: .buying,
            input: "d",
            modifiers: [],
            visibility: .flag("dimBoostUnlocked"),
            action: .engine { $0.buyDimensionBoost() }
        ))

        rows.append(.init(
            id: "galaxy",
            name: "Antimatter Galaxy",
            category: .buying,
            input: "g",
            modifiers: [],
            visibility: .flag("galaxyUnlocked"),
            action: .engine { $0.buyGalaxy() }
        ))

        // MARK: - Prestige

        rows.append(.init(
            id: "bigCrunch",
            name: "Big Crunch",
            category: .prestige,
            input: "c",
            modifiers: [],
            visibility: .anyFlag(["infinityUnlocked", "canCrunch"]),
            action: .engine { $0.bigCrunch() }
        ))

        rows.append(.init(
            id: "replicantiGalaxy",
            name: "Replicanti Galaxy",
            category: .prestige,
            input: "r",
            modifiers: [],
            visibility: .anyFlag(["replicantiUnlocked", "eternityUnlocked"]),
            action: .engine { $0.replicantiGalaxy() }
        ))

        rows.append(.init(
            id: "eternity",
            name: "Eternity",
            category: .prestige,
            input: "e",
            modifiers: [],
            visibility: .anyFlag(["eternityUnlocked", "canEternity"]),
            action: .engine { $0.requestEternity() }
        ))

        rows.append(.init(
            id: "toggleTSRespec",
            name: "Toggle Time Study respec",
            category: .prestige,
            input: "e",
            modifiers: .shift,
            visibility: .flag("eternityUnlocked"),
            action: .engine { $0.toggleTSRespec() }
        ))

        rows.append(.init(
            id: "dilation",
            name: "Enter/Exit Dilation",
            category: .prestige,
            input: "l",
            modifiers: [],
            visibility: .anyFlag(["dilationUnlocked", "realityUnlocked"]),
            action: .engine { $0.requestDilation() }
        ))

        rows.append(.init(
            id: "reality",
            name: "Reality",
            category: .prestige,
            input: "y",
            modifiers: [],
            visibility: .anyFlag(["realityUnlocked", "canReality"]),
            action: .engine { $0.requestReality() }
        ))

        rows.append(.init(
            id: "toggleGlyphRespec",
            name: "Toggle Glyph unequip",
            category: .prestige,
            input: "y",
            modifiers: .shift,
            visibility: .flag("realityUnlocked"),
            action: .engine { $0.toggleGlyphRespec() }
        ))

        rows.append(.init(
            id: "armageddon",
            name: "Armageddon",
            category: .prestige,
            input: "z",
            modifiers: [],
            visibility: .flag("pelleDoomed"),
            action: .engine { $0.armageddonRequest() }
        ))

        rows.append(.init(
            id: "togglePelleGlyphRespec",
            name: "Toggle Glyph unequip (Pelle)",
            category: .prestige,
            input: "z",
            modifiers: .shift,
            visibility: .flag("pelleDoomed"),
            action: .engine { $0.togglePelleGlyphRespec() }
        ))

        // MARK: - Autobuyers

        rows.append(.init(
            id: "toggleAllAutobuyers",
            name: "Pause/Resume autobuyers",
            category: .autobuyers,
            input: "a",
            modifiers: [],
            visibility: .flag("autobuyersUnlocked"),
            action: .engine { $0.toggleAllAutobuyers() }
        ))

        // alt+letter / shift+alt+letter — toggle / buy-singles for named autobuyers.
        let namedAutobuyers: [(input: String, type: String, label: String)] = [
            ("t", "tickspeed",        "Tickspeed"),
            ("s", "sacrifice",        "Sacrifice"),
            ("d", "dimboost",         "Dimension Boost"),
            ("g", "galaxy",           "Antimatter Galaxy"),
            ("r", "replicantiGalaxy", "Replicanti Galaxy"),
            ("c", "bigCrunch",        "Big Crunch"),
            ("e", "eternity",         "Eternity"),
            ("y", "reality",          "Reality"),
        ]
        for ab in namedAutobuyers {
            let type = ab.type
            rows.append(.init(
                id: "toggleAB-\(type)",
                name: "Toggle \(ab.label) autobuyer",
                category: .autobuyers,
                input: ab.input,
                modifiers: .alternate,
                visibility: .flag("autobuyersUnlocked"),
                action: .engine { $0.toggleAutobuyer(type) }
            ))
            // Only Tickspeed exposes a buy-singles toggle in web `hotkeys.js`.
            if type == "tickspeed" {
                rows.append(.init(
                    id: "toggleABMode-\(type)",
                    name: "Toggle Tickspeed buy-singles",
                    category: .autobuyers,
                    input: ab.input,
                    modifiers: [.shift, .alternate],
                    visibility: .flag("autobuyersUnlocked"),
                    action: .engine { $0.toggleAutobuyerMode(type) }
                ))
            }
        }

        // alt+1-8 / shift+alt+1-8 — AD autobuyer toggles + buy-singles.
        for tier in 1...8 {
            rows.append(.init(
                id: "toggleABAntimatter\(tier)",
                name: "Toggle \(Self.dimensionName(tier)) autobuyer",
                category: .autobuyers,
                input: "\(tier)",
                modifiers: .alternate,
                visibility: .flag("autobuyersUnlocked"),
                action: .engine { $0.toggleAutobuyer("antimatterDimension", tier: tier) }
            ))
            rows.append(.init(
                id: "toggleABModeAntimatter\(tier)",
                name: "Toggle \(Self.dimensionName(tier)) buy-singles",
                category: .autobuyers,
                input: "\(tier)",
                modifiers: [.shift, .alternate],
                visibility: .flag("autobuyersUnlocked"),
                action: .engine { $0.toggleAutobuyerMode("antimatterDimension", tier: tier) }
            ))
        }

        rows.append(.init(
            id: "toggleContinuum",
            name: "Toggle Continuum",
            category: .autobuyers,
            input: "a",
            modifiers: .alternate,
            visibility: .flag("laitelaContinuumUnlocked"),
            action: .engine { $0.toggleContinuum() }
        ))

        // MARK: - Navigation

        rows.append(.init(
            id: "subtabPrev",
            name: "Previous subtab",
            category: .navigation,
            input: "[",
            modifiers: .command,
            visibility: .always,
            action: .engineSidebar { engine, sidebar in
                sidebar?.cycleSubtab(direction: -1, engine: engine)
            }
        ))
        rows.append(.init(
            id: "subtabNext",
            name: "Next subtab",
            category: .navigation,
            input: "]",
            modifiers: .command,
            visibility: .always,
            action: .engineSidebar { engine, sidebar in
                sidebar?.cycleSubtab(direction: +1, engine: engine)
            }
        ))

        // MARK: - UI

        rows.append(.init(
            id: "automatorToggle",
            name: "Start/Pause Automator",
            category: .ui,
            input: "u",
            modifiers: [],
            visibility: .flag("automatorUnlocked"),
            action: .engine { $0.automatorToggleRunning() }
        ))
        rows.append(.init(
            id: "automatorRestart",
            name: "Restart Automator",
            category: .ui,
            input: "u",
            modifiers: .shift,
            visibility: .flag("automatorUnlocked"),
            action: .engine { $0.automatorRestart() }
        ))

        rows.append(.init(
            id: "toggleBlackHole",
            name: "Toggle Black Hole",
            category: .ui,
            input: "b",
            modifiers: [],
            visibility: .flag("blackHolesUnlocked"),
            action: .engine { $0.toggleBlackHolePause() }
        ))

        rows.append(.init(
            id: "save",
            name: "Save game",
            category: .ui,
            input: "s",
            modifiers: .command,
            visibility: .always,
            action: .engine { engine in
                engine.save()
                engine.enqueueToast(type: "info", text: "Game saved")
            }
        ))
        rows.append(.init(
            id: "export",
            name: "Export save",
            category: .ui,
            input: "e",
            modifiers: .command,
            visibility: .always,
            action: .engine { $0.exportSave() }
        ))

        rows.append(.init(
            id: "dismissEsc",
            name: "Dismiss sheet",
            category: .ui,
            input: UIKeyCommand.inputEscape,
            modifiers: [],
            visibility: .always,
            action: .engineSidebar { engine, _ in
                Task { @MainActor in engine.dismissTopGameSheet() }
            }
        ))
        // `⌘.` alias for Esc — common iPadOS convention. Not shown in the
        // Options sheet to keep the list clean (Esc is the canonical hint).
        rows.append(.init(
            id: "dismissCmdPeriod",
            name: "Dismiss sheet (Cmd-Period)",
            category: .ui,
            input: ".",
            modifiers: .command,
            visibility: .anyFlag([]),   // never visible — alias only
            action: .engineSidebar { engine, _ in
                Task { @MainActor in engine.dismissTopGameSheet() }
            }
        ))

        // MARK: - Secret-achievement keyboard bindings (web `hotkeys.js`).
        //
        // All hidden from the Options sheet — they're easter eggs the
        // player should discover by experimentation, not have spoiled.
        // Each fires its action directly; the Konami sequence (SA #17)
        // is tracked by `KonamiTracker` intercepting in `KeyCommandHost`.

        // F → SecretAchievement(13) "It pays to have respect"
        rows.append(.init(
            id: "payRespects",
            name: "Pay respects",
            category: .ui,
            input: "f",
            modifiers: [],
            visibility: .anyFlag([]),
            action: .engine { $0.payRespects() }
        ))

        // 9 → SecretAchievement(41) "That dimension doesn't exist"
        // Keyboard parity with web `hotkeys.js:294-300` + the iOS tap-zone
        // hook in DimensionsTab. Both surfaces fire the same unlock.
        rows.append(.init(
            id: "tryBuyDim9",
            name: "Doesn't exist",
            category: .ui,
            input: "9",
            modifiers: [],
            visibility: .anyFlag([]),
            action: .engine { $0.tryPurchaseNinthDimension() }
        ))

        // Arrow keys + Enter → no-op actions registered so UIKit routes
        // the keystrokes to `KeyCommandHost.handleKeyCommand`, where
        // `KonamiTracker` records them. No-op is intentional — these keys
        // have no other game purpose on iOS.
        let konamiOnlyKeys: [(id: String, input: String)] = [
            ("konamiUp",    UIKeyCommand.inputUpArrow),
            ("konamiDown",  UIKeyCommand.inputDownArrow),
            ("konamiLeft",  UIKeyCommand.inputLeftArrow),
            ("konamiRight", UIKeyCommand.inputRightArrow),
            ("konamiEnter", "\r"),
        ]
        for entry in konamiOnlyKeys {
            rows.append(.init(
                id: entry.id,
                name: "Konami tracker",
                category: .ui,
                input: entry.input,
                modifiers: [],
                visibility: .anyFlag([]),
                action: .engine { _ in /* tracked at host */ }
            ))
        }

        return rows
    }

    /// Filter to the rows that should appear in the Options sheet for the
    /// current visibility flag snapshot.
    static func visibleRows(for flags: [String: Bool]) -> [KeyboardShortcutDescriptor] {
        all.filter { $0.visibility.evaluate(flags) }
    }

    // MARK: - Helpers

    private static func dimensionName(_ tier: Int) -> String {
        let names = ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th"]
        let suffix = "Antimatter Dimension"
        guard tier >= 1 && tier <= 8 else { return suffix }
        return "\(names[tier - 1]) \(suffix)"
    }
}

// MARK: - Display formatting

extension KeyboardShortcutDescriptor {
    /// Compact key-cap rendering: `⇧⌥1`, `⌘S`, `Esc`, `[`, etc. Used by the
    /// Options sheet and `UIKeyCommand.discoverabilityTitle`.
    var displayCombo: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.alternate) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(Self.displayKey(for: input))
        return parts.joined()
    }

    private static func displayKey(for input: String) -> String {
        switch input {
        case UIKeyCommand.inputEscape: return "Esc"
        case UIKeyCommand.inputUpArrow: return "↑"
        case UIKeyCommand.inputDownArrow: return "↓"
        case UIKeyCommand.inputLeftArrow: return "←"
        case UIKeyCommand.inputRightArrow: return "→"
        default: return input.uppercased()
        }
    }
}
