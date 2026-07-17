//
//  SpeedrunStatusView.swift
//  AntiMatter
//
//  Live elapsed-time + last-milestone display for an active Speedrun.
//
//  - iPad: rendered in `GameSidebar` as a footer above the bottom spacer.
//  - iPhone: rendered in `CompactHeaderView` as a 2-line subtitle row
//    (pinnedHeight adds 28pt when `hasSpeedrun` is true).
//
//  Hidden entirely when `!engine.speedrunQuick.isActive` — no slot
//  reserved, no placeholder. Pre-start (`!hasStarted`) shows frozen
//  `00:00:00`; clock auto-flips to live the moment the player buys their
//  first dimension (web `Speedrun.startTimer()`).
//

import SwiftUI

/// Compact 2-line view: elapsed timer + last-milestone label.
struct SpeedrunStatusView: View {
    let engine: GameEngine
    /// `.compact` (iPhone): tighter font, single accent line under the
    /// compact header. `.regular` (iPad): bigger, sidebar-footer styling.
    enum Layout { case compact, regular }
    var layout: Layout = .regular

    var body: some View {
        let s = engine.speedrunQuick
        if !s.isActive {
            EmptyView()
        } else if layout == .compact {
            // Single-line layout: timer + milestone label sit at the same
            // 12pt size so the milestone is legible (was 9pt, unreadable).
            HStack(spacing: 6) {
                Text(formatElapsed(s.elapsedMs, hasStarted: s.hasStarted))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(s.hasStarted ? GameColor.eternity : Color.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Text(milestoneLine(s))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 1)
            .padding(.horizontal, 6)
        } else {
            VStack(spacing: 2) {
                Text(formatElapsed(s.elapsedMs, hasStarted: s.hasStarted))
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(s.hasStarted ? GameColor.eternity : Color.secondary)
                    .lineLimit(1)
                Text(milestoneLine(s))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        }
    }

    private func milestoneLine(_ s: SpeedrunQuickState) -> String {
        if s.mostRecentId == 0 || s.mostRecentMs <= 0 {
            return String(localized: "no milestones yet")
        }
        // Name is resolved JS-side from GameDatabase.speedrunMilestones (see
        // _nativeSpeedrunQuick). Fall back to the id only in the rare window
        // before the JS name is populated.
        let name = s.mostRecentName.isEmpty ? "Milestone #\(s.mostRecentId)" : s.mostRecentName
        let split = formatElapsed(s.mostRecentMs, hasStarted: true)
        // Compact prefix to fit the iPhone subtitle row width.
        return "last: \(name) (\(split))"
    }

    private func formatElapsed(_ ms: Double, hasStarted: Bool) -> String {
        guard hasStarted && ms > 0 else { return "00:00:00" }
        let totalSec = Int(ms / 1000)
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
