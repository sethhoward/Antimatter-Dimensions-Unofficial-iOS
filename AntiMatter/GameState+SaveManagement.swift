//
//  GameState+SaveManagement.swift
//  AntiMatter
//
//  State structs for the Save Management UI (multi-slot cards + per-slot
//  backup restore). Populated on demand by GameEngine+SaveManagement via the
//  save-helpers.js JS bridge. This data is NOT part of the per-tick pollDirect
//  pipeline — it's fetched when the user opens the Options tab or a backup
//  sheet, and refreshed after mutating actions (switch, rename, delete,
//  restore).
//

import Foundation

/// One of the 3 persistent save slots (web parity: GameStorage.saves[0..2]).
struct SaveSlotInfo: Identifiable, Equatable {
    let id: Int            // 0, 1, 2
    let isEmpty: Bool
    let isActive: Bool     // matches GameStorage.currentSlot
    let saveFileName: String
    let antimatter: String
    let realities: String
    let eternities: String
    let infinitied: String
    let realTimePlayed: String
    let lastUpdate: Double // ms since epoch; 0 when empty
    let stage: String      // "Antimatter" / "Infinity" / "Eternity" / "Reality" / "Doomed" / "Empty"
}

/// Listing of all slots. `current` is the index of the active slot — mirrors
/// `GameStorage.currentSlot` at the moment of the read.
struct SaveSlotsSnapshot: Equatable {
    let current: Int
    let slots: [SaveSlotInfo]

    static let empty = SaveSlotsSnapshot(current: 0, slots: [])
}

/// One backup slot (web's AutoBackupSlots 1..8). Each save slot gets its own
/// set of 8 backups — the interval schedule is fixed (1m / 5m / 20m / 1h /
/// 10m offline / 1h offline / 5h offline / reserve).
struct SaveBackupInfo: Identifiable, Equatable {
    let backupId: Int       // 1..8 — matches AutoBackupSlots[i].id
    let type: String        // "online" / "offline" / "reserve"
    let intervalLabel: String
    let isEmpty: Bool
    let antimatter: String
    let realities: String
    let eternities: String
    let realTimePlayed: String
    let stage: String
    let date: Double        // ms since epoch of the most recent write; 0 if never

    var id: Int { backupId }
}

/// Full listing for one save slot.
struct SaveBackupsSnapshot: Equatable {
    let slotId: Int
    let backups: [SaveBackupInfo]

    static func empty(slotId: Int) -> SaveBackupsSnapshot {
        SaveBackupsSnapshot(slotId: slotId, backups: [])
    }
}
