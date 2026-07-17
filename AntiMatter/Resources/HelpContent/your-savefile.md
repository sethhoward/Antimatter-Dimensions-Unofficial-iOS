Your save lives on this device. The game writes it automatically every few seconds, and you can copy it elsewhere using **Export Save** in Options. This page covers everything you can do with saves on iOS.

## Save Slots

You have **three save slots**, listed in Options. Each slot is fully independent — switching slots loads that slot's progress; importing a save only replaces the slot you're currently on; hard reset only wipes the current slot.

Tap a slot to bring up its menu:

- **Switch** — make this slot the active one. Your current progress stays in its slot, untouched.
- **Rename** — give the slot a label so you can tell them apart at a glance.
- **Export** — copies this slot's save to the clipboard.
- **Restore from Backup** — open the rolling backup list (see below). Restoring is only allowed on the active slot, so switch first if you want to restore a different slot.
- **Delete** — wipes a non-active slot. Hidden on the slot you're playing — switch away first if you really want to delete that one.

Empty slots show a single **Start New Game Here** action.

## Rolling Backups

Every save slot keeps **eight automatic backups** written on a rolling schedule — four while you're playing (roughly every minute, five minutes, twenty minutes, and an hour), three while you're away (after ten minutes, an hour, and five hours), plus one reserve. Older backups overwrite themselves, so the list always reflects the last several save points.

To restore one, open the slot menu and tap **Restore from Backup**. You'll see each backup with the time it was written and a short summary. Tap to restore — the current save is replaced with the backup, the same way an import works.

Backups are per-slot. Restoring is only allowed on the active slot; the menu reminds you to switch slots first if needed.

## iCloud Sync

**iCloud sync is off by default.** Turn it on in Options → iCloud Sync. Your progress never leaves the device unless you turn it on yourself.

The first time you enable iCloud sync with progress on both your device and iCloud, the game asks which one to keep. Pick **Upload local** to push this device's save up, or **Download iCloud save** to pull the cloud's save down. There's no automatic merge — you choose.

Once enabled, the active slot uploads to iCloud when the app goes to the background. When you reopen the app, the game checks iCloud for changes. The reconciliation rule is **playtime wins**: whichever save has more real-time-played is considered authoritative. So if you played on your iPad, then opened the app on your iPhone, the iPhone notices iCloud has more playtime and quietly loads it.

You'll only see a conflict prompt when something genuinely ambiguous happens — cloud has more playtime but the local save is further along in progression. That's the "you reset or something went wrong upstream" case, and the prompt lets you pick which version to keep. Local progress is never silently overwritten.

The **Sync now** button forces a fresh check against iCloud. Useful if you want to verify reconciliation without backgrounding the app.

## Export and Import

**Export Save** copies a long string of characters to your clipboard. That string contains the entire save. You can paste it into a notes app, a message to a friend, or import it into the web version of the game — the save format is shared with the web build.

**Import Save** does the opposite: paste the save string into the prompt and the game loads it into the **current slot**, replacing whatever was there. The game checks the format before overwriting; if the text isn't a valid save, the import is rejected with no changes made.

A valid save string starts with `AntimatterDimensionsSavefile` and ends with a similar marker. If your clipboard's contents got truncated (some messaging apps cut long pastes), the import will fail with an explanation.

## Hard Reset

**Hard Reset** wipes your save and starts a brand-new game. It's intentionally hard to trigger by accident — you'll see a warning alert, then have to type the exact phrase _"Shrek is love, Shrek is life"_ to confirm.

Hard Reset only affects the active slot. Other slots are untouched. There's no undo, but a freshly-hard-reset slot can be replaced with an Import or a backup restore from a different slot.

## Speedrun Mode

If you've completed the full game at least once, Options shows a **Speedrun Mode** entry that runs a guided fresh-game start with milestone timing. Starting a Speedrun resets the active slot, but a small set of carryover state survives: full-game completion records, Automator scripts, and Glyph cosmetic preferences. Everything else — antimatter, dimensions, glyphs, perks, achievements — starts from zero.
