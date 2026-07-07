//
//  HelpContent.swift
//  AntiMatter
//
//  Catalogue of help sections surfaced in Options → Help.
//
//  Each `HelpSection` knows its display title, the markdown file it loads
//  from `Resources/HelpContent/<filename>.md`, a visibility predicate gated
//  on progression (so a fresh save doesn't see "Pelle Strikes"), and the
//  progression flag set passed to `MarkdownLoader` for within-section
//  `[if:flag]` reveals (used by Common Abbreviations).
//
//  Section ordering matches web's progression order so the index reads
//  naturally. Visibility predicates use `engine.*Unlocked` flags polled
//  every tick in `pollDirect()`.
//

import Foundation

struct HelpSection: Identifiable {
    let id: String           // stable id used by search/state
    let title: String        // display title
    let filename: String     // stem under Resources/HelpContent/
    let isVisible: (GameEngine) -> Bool

    /// Optional within-section progression flags. Used by Common Abbreviations
    /// to reveal abbreviation rows progressively. Empty by default — most
    /// sections have static bodies and rely on `isVisible` alone.
    let progressionFlags: (GameEngine) -> Set<String>

    init(
        id: String,
        title: String,
        filename: String,
        isVisible: @escaping (GameEngine) -> Bool = { _ in true },
        progressionFlags: @escaping (GameEngine) -> Set<String> = { _ in [] }
    ) {
        self.id = id
        self.title = title
        self.filename = filename
        self.isVisible = isVisible
        self.progressionFlags = progressionFlags
    }
}

enum HelpContent {
    /// Progression flag names used by `[if:flag]` line-prefix conditionals
    /// inside section markdown. Defined in one place so the markdown files
    /// and the engine reads can't drift.
    enum Flag {
        static let infinity = "infinity"
        static let replicanti = "replicanti"
        static let eternity = "eternity"
        static let dilation = "dilation"
        static let reality = "reality"
        static let effarig = "effarig"
        static let laitela = "laitela"
    }

    /// Collect every progression flag that's currently active for `engine`.
    /// Used as the default flag set for sections that don't override
    /// `progressionFlags`.
    static func defaultFlags(for engine: GameEngine) -> Set<String> {
        var flags: Set<String> = []
        if engine.infinityUnlocked { flags.insert(Flag.infinity) }
        if engine.replicantiUnlocked { flags.insert(Flag.replicanti) }
        if engine.eternityUnlocked { flags.insert(Flag.eternity) }
        if engine.dilationUnlocked { flags.insert(Flag.dilation) }
        if engine.realityUnlocked { flags.insert(Flag.reality) }
        if engine.effarigEternityUnlocked { flags.insert(Flag.effarig) }
        if engine.laitelaUnlocked { flags.insert(Flag.laitela) }
        return flags
    }

    /// All help sections, ordered by web's progression order.
    static let sections: [HelpSection] = [
        // MARK: Always-visible — meta + early game

        HelpSection(
            id: "your-savefile",
            title: "Your savefile",
            filename: "your-savefile"
        ),
        HelpSection(
            id: "customization",
            title: "Customization",
            filename: "customization"
        ),
        HelpSection(
            id: "offline-progress",
            title: "Offline Progress",
            filename: "offline-progress"
        ),
        HelpSection(
            id: "effect-stacking",
            title: "Effect Stacking",
            filename: "effect-stacking"
        ),
        HelpSection(
            id: "common-abbreviations",
            title: "Common Abbreviations",
            filename: "common-abbreviations",
            isVisible: { $0.infinityUnlocked },
            progressionFlags: { Self.defaultFlags(for: $0) }
        ),
        HelpSection(
            id: "antimatter-dimensions",
            title: "Antimatter Dimensions",
            filename: "antimatter-dimensions"
        ),
        HelpSection(
            id: "tickspeed",
            title: "Tickspeed",
            filename: "tickspeed"
        ),
        HelpSection(
            id: "dimension-boosts",
            title: "Dimension Boosts",
            filename: "dimension-boosts"
        ),
        HelpSection(
            id: "antimatter-galaxies",
            title: "Antimatter Galaxies",
            filename: "antimatter-galaxies"
        ),
        HelpSection(
            id: "dimensional-sacrifice",
            title: "Dimensional Sacrifice",
            filename: "dimensional-sacrifice"
        ),
        HelpSection(
            id: "achievements",
            title: "Achievements",
            filename: "achievements"
        ),

        // MARK: Infinity tier

        HelpSection(
            id: "infinity",
            title: "Infinity",
            filename: "infinity",
            isVisible: { $0.infinityUnlocked }
        ),
        HelpSection(
            id: "normal-challenges",
            title: "Normal Challenges",
            filename: "normal-challenges",
            isVisible: { $0.infinityUnlocked }
        ),
        HelpSection(
            id: "autobuyers",
            title: "Autobuyers",
            filename: "autobuyers",
            isVisible: { $0.infinityUnlocked }
        ),
        HelpSection(
            id: "break-infinity",
            title: "Break Infinity",
            filename: "break-infinity",
            isVisible: { $0.infinityUnlocked }
        ),
        HelpSection(
            id: "infinity-dimensions",
            title: "Infinity Dimensions",
            filename: "infinity-dimensions",
            isVisible: { $0.infinityUnlocked }
        ),
        HelpSection(
            id: "infinity-challenges",
            title: "Infinity Challenges",
            filename: "infinity-challenges",
            isVisible: { $0.infinityUnlocked }
        ),
        HelpSection(
            id: "replicanti",
            title: "Replicanti",
            filename: "replicanti",
            isVisible: { $0.replicantiUnlocked }
        ),

        // MARK: Eternity tier

        HelpSection(
            id: "eternity",
            title: "Eternity",
            filename: "eternity",
            isVisible: { $0.eternityUnlocked }
        ),
        HelpSection(
            id: "eternity-milestones",
            title: "Eternity Milestones",
            filename: "eternity-milestones",
            isVisible: { $0.eternityUnlocked }
        ),
        HelpSection(
            id: "time-dimensions",
            title: "Time Dimensions",
            filename: "time-dimensions",
            isVisible: { $0.eternityUnlocked }
        ),
        HelpSection(
            id: "time-studies",
            title: "Time Studies",
            filename: "time-studies",
            isVisible: { $0.eternityUnlocked }
        ),
        HelpSection(
            id: "eternity-challenges",
            title: "Eternity Challenges",
            filename: "eternity-challenges",
            isVisible: { $0.eternityUnlocked }
        ),
        HelpSection(
            id: "time-dilation",
            title: "Time Dilation",
            filename: "time-dilation",
            isVisible: { $0.dilationUnlocked }
        ),
        HelpSection(
            id: "automator",
            title: "Automator",
            filename: "automator",
            isVisible: { $0.eternityUnlocked }
        ),

        // MARK: Reality tier

        HelpSection(
            id: "reality",
            title: "Reality",
            filename: "reality",
            isVisible: { $0.realityUnlocked }
        ),
        HelpSection(
            id: "glyphs",
            title: "Glyphs",
            filename: "glyphs",
            isVisible: { $0.realityUnlocked }
        ),
        HelpSection(
            id: "perks",
            title: "Perks",
            filename: "perks",
            isVisible: { $0.realityUnlocked }
        ),
        HelpSection(
            id: "black-hole",
            title: "Black Hole",
            filename: "black-hole",
            isVisible: { $0.realityUnlocked }
        ),

        // MARK: Celestials tier

        HelpSection(
            id: "celestials",
            title: "Celestials",
            filename: "celestials",
            isVisible: { $0.teresaUnlocked }
        ),
        HelpSection(
            id: "teresa",
            title: "Teresa, Celestial of Reality",
            filename: "teresa",
            isVisible: { $0.teresaUnlocked }
        ),
        HelpSection(
            id: "effarig",
            title: "Effarig, Celestial of Ancient Relics",
            filename: "effarig",
            isVisible: { $0.effarigUnlocked }
        ),
        HelpSection(
            id: "advanced-glyph-mechanics",
            title: "Advanced Glyph Mechanics",
            filename: "advanced-glyph-mechanics",
            isVisible: { $0.effarigUnlocked }
        ),
        HelpSection(
            id: "nameless-ones",
            title: "The Nameless Ones, Celestial of Time",
            filename: "nameless-ones",
            isVisible: { $0.effarigEternityUnlocked }
        ),
        HelpSection(
            id: "tesseracts",
            title: "Tesseracts",
            filename: "tesseracts",
            isVisible: { $0.enslavedCompleted }
        ),
        HelpSection(
            id: "v",
            title: "V, Celestial of Achievements",
            filename: "v",
            isVisible: { $0.vUnlocked }
        ),
        HelpSection(
            id: "ra",
            title: "Ra, Celestial of the Forgotten",
            filename: "ra",
            isVisible: { $0.raUnlocked }
        ),
        HelpSection(
            id: "glyph-alchemy-resources",
            title: "Glyph Alchemy Resources",
            filename: "glyph-alchemy-resources",
            isVisible: { $0.raUnlocked }
        ),
        HelpSection(
            id: "glyph-alchemy-reactions",
            title: "Glyph Alchemy Reactions",
            filename: "glyph-alchemy-reactions",
            isVisible: { $0.raUnlocked }
        ),
        HelpSection(
            id: "imaginary-machines",
            title: "Imaginary Machines",
            filename: "imaginary-machines",
            isVisible: { $0.effarigEternityUnlocked }
        ),
        HelpSection(
            id: "laitela",
            title: "Lai'tela, Celestial of Dimensions",
            filename: "laitela",
            isVisible: { $0.laitelaUnlocked }
        ),
        HelpSection(
            id: "continuum",
            title: "Continuum",
            filename: "continuum",
            isVisible: { $0.laitelaUnlocked }
        ),
        HelpSection(
            id: "singularities",
            title: "Singularities",
            filename: "singularities",
            isVisible: { $0.laitelaUnlocked }
        ),
        HelpSection(
            id: "pelle",
            title: "Pelle, Celestial of Antimatter",
            filename: "pelle",
            isVisible: { $0.pelleUnlocked }
        ),
        HelpSection(
            id: "pelle-strikes",
            title: "Pelle Strikes",
            filename: "pelle-strikes",
            isVisible: { $0.pelleDoomed }
        ),
        HelpSection(
            id: "galaxy-generator",
            title: "The Galaxy Generator",
            filename: "galaxy-generator",
            isVisible: { $0.pelleDoomed }
        ),
    ]

    /// Filter sections visible for the given engine state.
    static func visibleSections(for engine: GameEngine) -> [HelpSection] {
        sections.filter { $0.isVisible(engine) }
    }
}
