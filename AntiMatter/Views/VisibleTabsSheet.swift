//
//  VisibleTabsSheet.swift
//  AntiMatter
//
//  Modify Visible Tabs — iOS port of web's `HiddenTabsModal.vue`. Lets the
//  player hide tabs/subtabs they don't actively use. Hidden state lives in
//  `player.options.hiddenTabBits` + `player.options.hiddenSubtabBits` (web's
//  canonical fields; iOS reads/writes the same bits via the iOS↔web id
//  mapping in `SidebarVisibilityMap.swift`).
//
//  Visibility rules implemented by `SidebarTab.isHidden(engine:)` /
//  `Subtab.isHidden(engine:)`. The sheet's job is just to enumerate hideable
//  tabs + their hideable subtabs, present a Toggle per row, and dispatch
//  to the engine's toggle / show-all actions.
//
//  The currently-active tab/subtab is rendered with `.disabled(true)` + an
//  "active" caption so the user can't accidentally hide the surface they're
//  standing on — mirrors web's `TabState.toggleVisibility` current-tab guard.
//

import SwiftUI

struct VisibleTabsSheet: View {
    let engine: GameEngine

    @Environment(\.sidebarState) private var sidebar
    @Environment(\.dismiss) private var dismiss

    /// Tabs to render in the sheet — hideable AND currently unlocked.
    /// Computed every body eval so unlocking a new tab while the sheet is
    /// open (e.g. Reality study purchased) surfaces it without re-opening.
    private var hideableTabs: [SidebarTab] {
        SidebarTab.allCases.filter { $0.isWebHideable && $0.isAvailable(engine: engine) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    introCard

                    VStack(spacing: 10) {
                        ForEach(hideableTabs, id: \.self) { tab in
                            TabVisibilityRow(tab: tab, engine: engine)
                        }
                    }

                    showAllButton
                }
                .padding()
            }
            .background(GameColor.baseBackground)
            .adaptiveSheetTitle("Visible Tabs")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private var introCard: some View {
        Text("Hide tabs and subtabs you don't need. You can't hide the tab you're currently viewing — switch away first if you want to hide it. The Options tab is always visible.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showAllButton: some View {
        GameButton(borderColor: GameColor.good) {
            engine.showAllTabs()
        } label: {
            Text("Show all tabs")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }
}

// MARK: - Per-tab row

/// One disclosure per hideable tab. Header carries the parent-tab Toggle;
/// expanded body carries one Toggle per hideable subtab. Equatable on its
/// stable inputs would be nice but the subtab list is small and the user is
/// only here for a few seconds — body re-eval cost is irrelevant.
private struct TabVisibilityRow: View {
    let tab: SidebarTab
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebar
    @State private var expanded: Bool = false

    private var isActiveTab: Bool { sidebar?.activeTab == tab }
    private var tabIsHidden: Bool { tab.isHidden(engine: engine) }

    /// Hideable + unlocked subtabs for this tab. Non-hideable ones (iOS-only
    /// `.optionsHelp` / `.debug` — only relevant for Options/Debug, which
    /// don't reach this view) are excluded from the listing entirely so the
    /// UI matches web exactly.
    private var subtabs: [Subtab] {
        tab.availableSubtabs(engine: engine).filter { $0.isWebHideable }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Disclosure header — tab name + toggle
            HStack(spacing: 8) {
                Button {
                    if !subtabs.isEmpty {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expanded.toggle()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if !subtabs.isEmpty {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                        } else {
                            Spacer().frame(width: 12)
                        }

                        Text(tab.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(tab.accentColor)

                        if isActiveTab {
                            Text("active")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.1), in: Capsule())
                        }

                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)

                Toggle("", isOn: Binding(
                    get: { !tabIsHidden },
                    set: { _ in engine.toggleTabVisibility(tab) }
                ))
                .labelsHidden()
                .disabled(isActiveTab)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)

            if expanded && !subtabs.isEmpty {
                Divider().opacity(0.3)
                VStack(spacing: 0) {
                    ForEach(subtabs, id: \.self) { sub in
                        SubtabVisibilityRow(parent: tab, subtab: sub, engine: engine)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Per-subtab row

private struct SubtabVisibilityRow: View {
    let parent: SidebarTab
    let subtab: Subtab
    let engine: GameEngine
    @Environment(\.sidebarState) private var sidebar

    private var isActiveSubtab: Bool {
        guard let sidebar else { return false }
        return sidebar.activeTab == parent && sidebar.lastSubtab[parent] == subtab
    }

    private var hidden: Bool { subtab.isHidden(engine: engine) }

    var body: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 24)

            Text(subtab.displayName)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if isActiveSubtab {
                Text("active")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }

            Spacer(minLength: 0)

            Toggle("", isOn: Binding(
                get: { !hidden },
                set: { _ in engine.toggleSubtabVisibility(parent: parent, subtab: subtab) }
            ))
            .labelsHidden()
            .disabled(isActiveSubtab)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}
