//
//  SidebarState.swift
//  AntiMatter
//
//  Observable state for the custom game sidebar.
//  Tracks active tab/subtab, flyout visibility, and collapse state.
//

import SwiftUI
import Observation

// MARK: - Environment key

private struct SidebarStateKey: EnvironmentKey {
    static let defaultValue: SidebarState? = nil
}

extension EnvironmentValues {
    var sidebarState: SidebarState? {
        get { self[SidebarStateKey.self] }
        set { self[SidebarStateKey.self] = newValue }
    }
}

@Observable
final class SidebarState {

    // MARK: - Navigation

    /// Currently selected parent tab.
    var activeTab: SidebarTab = .dimensions

    /// Remembers the last-selected subtab per parent tab.
    var lastSubtab: [SidebarTab: Subtab] = [
        .dimensions:   .antimatterDimensions,
        .achievements: .normalAchievements,
        .automation:   .autobuyers,
        .infinity:     .infinityUpgrades,
        .statistics:   .statistics,
        .options:      .options,
        .debug:        .debug,
    ]

    /// The active leaf subtab (drives content switching + poll category).
    var activeSubtab: Subtab {
        lastSubtab[activeTab] ?? activeTab.defaultSubtab
    }

    // MARK: - Sidebar visibility

    var isCollapsed: Bool = false

    // MARK: - Actions

    /// Tap a parent tab. If it's already active and multi-subtab, cycle to the next
    /// subtab (wrapping); otherwise switch to it, loading its last-remembered subtab.
    /// The active tab's inline subtab list is always expanded.
    func selectTab(_ tab: SidebarTab, engine: GameEngine) {
        engine.recordInteraction()
        // Cycle / new-tab selection operates over the visible subtab list
        // so user-hidden subtabs are skipped. (The Modify Visible Tabs
        // sheet itself never invokes selectTab, so it doesn't need the
        // un-filtered list here.)
        let available = tab.availableVisibleSubtabs(engine: engine)

        if activeTab == tab && available.count > 1 {
            cycleSubtab(direction: 1, engine: engine)
            return
        }

        activeTab = tab
        if let current = lastSubtab[tab], available.contains(current) {
            // Keep it
        } else if let first = available.first {
            lastSubtab[tab] = first
        }

        engine.selectSubtab(activeSubtab)
        engine.clearTabNotification(for: activeSubtab)
    }

    /// Select a specific subtab.
    func selectSubtab(_ subtab: Subtab, in tab: SidebarTab, engine: GameEngine) {
        engine.recordInteraction()
        activeTab = tab
        lastSubtab[tab] = subtab
        engine.selectSubtab(subtab)
        engine.clearTabNotification(for: subtab)
    }

    /// Web parity: `Tab.show(manual=false)` is gated on
    /// `player.options.automaticTabSwitching` ([tabs.js:141](AntimatterDimensionsSourceCode-master/src/core/tabs.js:141)).
    /// This helper mirrors that for game-event-driven navigation (challenge
    /// enter/exit/restart, future event-driven nav). User-driven taps continue
    /// to use `selectSubtab` directly so the toggle only suppresses *automatic*
    /// nav.
    func selectSubtabIfAuto(_ subtab: Subtab, in tab: SidebarTab, engine: GameEngine) {
        guard engine.automaticTabSwitching else { return }
        selectSubtab(subtab, in: tab, engine: engine)
    }

    /// Cycle through the active tab's available subtabs by ±1 step. Wraps
    /// at both ends. Used by the `⌘[` / `⌘]` keyboard shortcuts and any
    /// future swipe-by-keyboard affordance. No-op when the active tab has
    /// only one available subtab.
    func cycleSubtab(direction: Int, engine: GameEngine) {
        // `⌘[` / `⌘]` cycles only through visible (non-hidden) subtabs.
        let available = activeTab.availableVisibleSubtabs(engine: engine)
        guard available.count > 1 else { return }
        let current = activeSubtab
        let idx = available.firstIndex(of: current) ?? 0
        let count = available.count
        // Modular arithmetic that handles negative direction without bias.
        let next = ((idx + direction) % count + count) % count
        selectSubtab(available[next], in: activeTab, engine: engine)
    }

    /// Called when an unlock flag changes — redirect if the current tab/subtab is no longer available.
    func validateSelection(engine: GameEngine) {
        if !activeTab.isAvailable(engine: engine) {
            selectTab(.dimensions, engine: engine)
            return
        }
        if !activeSubtab.isAvailable(engine: engine) {
            let available = activeTab.availableSubtabs(engine: engine)
            if let first = available.first {
                lastSubtab[activeTab] = first
                engine.selectSubtab(first)
            } else {
                selectTab(.dimensions, engine: engine)
            }
        }
    }
}
