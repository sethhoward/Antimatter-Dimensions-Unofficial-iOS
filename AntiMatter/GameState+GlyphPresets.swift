//
//  GameState+GlyphPresets.swift
//  AntiMatter
//
//  State structs for the Glyph Presets feature (port of
//  GlyphSetSavePanel.vue). All loaded on demand by GameEngine extension
//  methods — none of these are part of the per-tick `pollDirect` snapshot.
//

import Foundation
import SwiftUI

// MARK: - Mini preview glyph (visualization-only)

/// Minimal glyph data for rendering inside preset previews + diff rows.
/// Distinct from `GlyphInfo` because saved-glyph snapshots don't carry
/// the full effect-text / sacrifice / refine fields — we only need what
/// a `GlyphComponent` reads to draw the tile.
struct GlyphPresetGlyph: Identifiable, Equatable, Hashable {
    let id: Int
    let type: String
    let symbol: String
    let level: Int
    let strength: Double
    let effects: Int       // bitmask (for ID-equality + debugging)
    let effectCount: Int   // for the dot row along the bottom
    let typeColor: String  // hex
    let rarityColor: String // hex
}

// MARK: - Saved preset slot

struct GlyphLoadoutSlot: Identifiable, Equatable {
    let id: Int            // 0..6
    var name: String       // empty when never named; <=20 chars
    /// Auto-derived "Powerful Infinite Time"-style name computed from the
    /// saved glyph types (matches the live equipped-set name in
    /// `GlyphsTabState.setName`). Empty for empty slots.
    var autoName: String
    var glyphs: [GlyphPresetGlyph]
    var isEmpty: Bool { glyphs.isEmpty }
}

// MARK: - Sheet snapshot

/// Fetched on demand when the Glyph Presets sheet opens or after any
/// mutating action. NOT part of per-tick `pollDirect`.
struct GlyphPresetsSnapshot: Equatable {
    var sets: [GlyphLoadoutSlot]
    var ignoreEffects: Bool
    var ignoreLevel: Bool
    var ignoreRarity: Bool
    var hasEquipped: Bool
    var activeSlotCount: Int
    var freeInventorySlots: Int

    static let empty = GlyphPresetsSnapshot(
        sets: (0..<7).map { GlyphLoadoutSlot(id: $0, name: "", autoName: "", glyphs: []) },
        ignoreEffects: false,
        ignoreLevel: false,
        ignoreRarity: false,
        hasEquipped: false,
        activeSlotCount: 0,
        freeInventorySlots: 0
    )
}

// MARK: - Per-slot match result (used for both preview diff and post-load badges)

/// One result entry per saved glyph in the preset. The order mirrors the
/// preset's stored `glyphs` array (so saved index 0 ↔ result.slots[0]).
struct GlyphLoadSlotMatch: Identifiable, Equatable {
    var id: Int { (savedGlyph?.id).map { Int($0) } ?? -1 }
    /// The saved glyph the user originally captured.
    let savedGlyph: GlyphPresetGlyph?
    /// What actually got equipped (or would, in preview). nil for `missing`.
    let willEquipGlyph: GlyphPresetGlyph?
    /// Match classification — see comments in glyph-loadout-helpers.js
    /// (`exact` / `fuzzy-full` / `partial` / `missing` / `already`).
    let matchKind: GlyphMatchKind
}

enum GlyphMatchKind: String, Equatable {
    case exact
    case fuzzyFull = "fuzzy-full"
    case partial
    case missing
    case already

    /// Whether this kind requires a preview/confirmation modal. `exact`
    /// and `already` are no-warning; everything else needs surfacing.
    var requiresPreview: Bool {
        switch self {
        case .exact, .already: return false
        case .fuzzyFull, .partial, .missing: return true
        }
    }

    /// Color of the persistent badge on the equipped slot after load.
    /// nil = no badge (exact match).
    var badgeColor: Color? {
        switch self {
        case .exact, .already: return nil
        case .fuzzyFull: return GameColor.dilationGreen
        case .partial: return Color(red: 1.0, green: 0.84, blue: 0.0)   // amber/yellow
        case .missing: return Color(red: 0.95, green: 0.27, blue: 0.27) // red
        }
    }

    /// One-line label shown in tooltips and the diff preview rows.
    var label: String {
        switch self {
        case .exact: return "Exact match"
        case .already: return "Already equipped"
        case .fuzzyFull: return "Equivalent (full effects)"
        case .partial: return "Partial match"
        case .missing: return "No match in inventory"
        }
    }
}

/// Result of a (preview or real) load. `lastLoadResult` on `GameEngine`
/// holds the most recent post-load result so persistent badges can render.
struct GlyphLoadResult: Equatable {
    let presetId: Int
    let presetName: String
    let slots: [GlyphLoadSlotMatch]
    let exactCount: Int
    let fuzzyCount: Int
    let partialCount: Int
    let alreadyCount: Int
    let missingCount: Int

    /// When true, the preview/diff modal should be shown before applying.
    var requiresPreview: Bool {
        slots.contains(where: { $0.matchKind.requiresPreview })
    }

    /// Human-readable summary for the preview footer and the post-load toast.
    var summary: String {
        var parts: [String] = []
        if exactCount > 0 { parts.append("\(exactCount) exact") }
        if alreadyCount > 0 { parts.append("\(alreadyCount) already equipped") }
        if fuzzyCount > 0 { parts.append("\(fuzzyCount) equivalent") }
        if partialCount > 0 { parts.append("\(partialCount) partial") }
        if missingCount > 0 { parts.append("\(missingCount) missing") }
        return parts.joined(separator: ", ")
    }
}

/// Reason a `Load` action couldn't proceed at all — surfaced as a banner
/// inside the sheet rather than via toast, so the user can act on it.
enum GlyphPresetLoadError: Equatable, Error {
    case empty
    case tooManyGlyphs(required: Int, available: Int)
    case notEnoughInventorySpace(deficit: Int)
    case unknown
}
