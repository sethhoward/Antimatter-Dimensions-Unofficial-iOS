//
//  SecretAchievementsTab.swift
//  AntiMatter
//
//  Sibling subtab to NormalAchievementsTab under the Achievements parent tab.
//  4 rows × 8 tiles (IDs 11–18, 21–28, 31–38, 41–48 = 32 total). Locked tiles
//  show "S{id}"; unlocked tiles show name. Tap any tile → detail sheet.
//  Tapping tile #11 while locked is the easter-egg unlock trigger.
//
//  Mirrors `src/components/tabs/secret-achievements/SecretAchievementTab.vue`
//  + `SecretAchievementRow.vue` + `SecretAchievement.vue`. iOS additions
//  (documented in the design notes):
//    • "X / Y unlocked" count line under the banner (web shows no count).
//    • Tap-to-sheet replaces hover-tooltip (no hover on touch).
//

import SwiftUI

struct SecretAchievementsTab: View {
    let engine: GameEngine

    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                    .padding(.horizontal)
                grid
                    // No horizontal padding — grid spans edge-to-edge.
            }
            .padding(.vertical)
            .padding(.bottom, metrics.isCompact ? 100 : 0)
        }
    }

    // MARK: - Header

    private var header: some View {
        let state = engine.gameState.secretAchievements
        return VStack(spacing: 6) {
            Text("Secret Achievements are optional and give no bonuses.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("\(state.unlockedCount) / \(state.totalCount) unlocked")
                .font(.title3.weight(.medium))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Grid

    private var grid: some View {
        let state = engine.gameState.secretAchievements
        let spacing: CGFloat = metrics.isCompact ? 4 : 6
        return VStack(spacing: spacing) {
            ForEach(Array(state.rows.enumerated()), id: \.offset) { _, row in
                SecretAchievementsRowView(row: row, spacing: spacing, engine: engine)
            }
        }
    }
}

// MARK: - Row

/// One row of up to 8 tiles. Whole-row green highlight when every tile in the
/// row is unlocked (mirrors web's `SecretAchievementRow.vue` row-completion).
/// Tiles fill the row width equally via `.frame(maxWidth: .infinity)` +
/// `.aspectRatio(1, contentMode: .fit)` — matches the AntimatterDimensions tab
/// and normal-achievements grid, which both stretch edge-to-edge.
private struct SecretAchievementsRowView: View {
    let row: [SecretAchievementInfo]
    let spacing: CGFloat
    let engine: GameEngine

    var body: some View {
        let allUnlocked = !row.isEmpty && row.allSatisfy(\.isUnlocked)
        HStack(spacing: spacing) {
            ForEach(row) { entry in
                SecretAchievementTile(entry: entry, engine: engine)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(spacing / 2)
        .background(
            // Web `.c-achievement-grid__row--completed` — solid dark green
            // backdrop visible in the gaps between tiles (NOT a stroke).
            RoundedRectangle(cornerRadius: 6)
                .fill(allUnlocked ? GameColor.achievementRowCompleted : .clear)
        )
    }
}

// MARK: - Tile

private struct SecretAchievementTile: View {
    let entry: SecretAchievementInfo
    let engine: GameEngine

    @State private var showDetail = false

    private var tileImage: UIImage? {
        AchievementImageProvider.shared.image(for: entry)
    }

    // Same visual language as `AchievementCell.normalTile` — green tint +
    // artwork + ID badge + checkmark on unlock; flat gray with "S{id}" hint
    // when locked.
    @ViewBuilder
    private var tileContent: some View {
        ZStack {
            Rectangle()
                .fill(entry.isUnlocked ? Color.green.opacity(0.35) : Color.gray.opacity(0.25))

            if entry.isUnlocked, let img = tileImage {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            }

            if entry.isUnlocked {
                // ID badge (bottom-left) + checkmark (bottom-right), matching
                // normal achievements' overlay.
                Text("\(entry.id)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .shadow(color: .black, radius: 2, x: 0, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(4)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)
                    .shadow(color: .black, radius: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(4)
            } else {
                // Locked: just the "S{id}" hint, centered.
                Text("S\(entry.id)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.gray)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // Web parity: unlocked tiles have no visible border (border-color
        // #127a20 blends into background #43a047). Only locked tiles get a
        // muted hint outline. Row-completion is signalled by the dark green
        // backdrop on `SecretAchievementsRowView`, not per-tile.
        .roundedBorder(
            entry.isUnlocked ? Color.clear : Color.gray.opacity(0.45),
            cornerRadius: 4,
            lineWidth: entry.isUnlocked ? 0 : 1
        )
    }

    var body: some View {
        tileContent
            .contentShape(Rectangle())
            .onTapGesture { handleTap() }
            .popover(isPresented: $showDetail,
                     attachmentAnchor: .point(.top),
                     arrowEdge: .bottom) {
                secretAchievementDetail
                    .presentationCompactAdaptation(.popover)
            }
            #if DEBUG
            // Dev-only long-press menu, mirroring `AchievementCell`'s.
            // `SecretAchievement(id).lock()` does NOT dispatch
            // `ACHIEVEMENT_UNLOCKED`, so we manually bust the helper cache
            // after toggling so the tile redraws within the next poll tick.
            .contextMenu {
                if entry.isUnlocked {
                    Button(role: .destructive) {
                        engine.devCommand("SecretAchievement(\(entry.id)).lock(); if (typeof _nativeSecretAchievementsInvalidate !== 'undefined') _nativeSecretAchievementsInvalidate();")
                    } label: {
                        Label("Lock Secret Achievement", systemImage: "lock")
                    }
                } else {
                    Button {
                        engine.devCommand("SecretAchievement(\(entry.id)).unlock();")
                    } label: {
                        Label("Unlock Secret Achievement", systemImage: "lock.open")
                    }
                }
            }
            #endif
    }

    // Matches `AchievementCell.achievementDetail` — same dimensions, font
    // ramp, and layout so the two grids feel like one navigation surface.
    private var secretAchievementDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.isUnlocked {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.name)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Text("S\(entry.id)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text(entry.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Secret Achievement")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Text("S\(entry.id)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text("Locked. Discover the requirement on your own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(idealWidth: 260, maxWidth: 320)
    }

    private func handleTap() {
        // Easter egg: tapping the locked #11 tile is its unlock trigger.
        // Mirrors web `SecretAchievement.vue` `@click="if (id===11) unlock()"`.
        if entry.id == 11 && !entry.isUnlocked {
            engine.unlockSecretAchievement11()
            return
        }
        showDetail = true
    }
}

