//
//  GameSidebar.swift
//  AntiMatter
//
//  Custom game sidebar matching the web's Modern UI.
//  Contains: currency header, tab list, collapse toggle.
//

import SwiftUI

struct GameSidebar: View {
    @Bindable var sidebar: SidebarState
    let engine: GameEngine

    static let width: CGFloat = 200

    private var visibleTabs: [SidebarTab] {
        SidebarTab.allCases.filter {
            $0.isAvailable(engine: engine) && !$0.isHidden(engine: engine)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SidebarCurrencyHeader(engine: engine)

            Divider()
                .background(Color.white.opacity(0.1))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(visibleTabs, id: \.self) { tab in
                        // `availableVisibleSubtabs` excludes user-hidden
                        // subtabs so the sidebar flyout matches what's
                        // reachable via tab cycling / swipe pager.
                        let available = tab.availableVisibleSubtabs(engine: engine)
                        let multiSubtab = available.count > 1
                        let activeSubtab = sidebar.lastSubtab[tab] ?? tab.defaultSubtab
                        let isExpanded = multiSubtab && sidebar.activeTab == tab
                        // Badge-suppression on hidden subtabs: a notification
                        // on a hidden subtab would otherwise produce an
                        // un-clearable dot (user can't navigate to clear it).
                        // The JS-side Set stays untouched so the prefs
                        // round-trip with web saves.
                        let parentNotification = available.contains(where: { engine.notifiedSubtabs.contains($0) })

                        SidebarTabButton(
                            tab: tab,
                            isActive: sidebar.activeTab == tab,
                            hasSubtabs: multiSubtab,
                            isExpanded: isExpanded,
                            activeSubtab: activeSubtab,
                            hasNotification: parentNotification,
                            onTap: { sidebar.selectTab(tab, engine: engine) }
                        )

                        if isExpanded {
                            ForEach(available, id: \.self) { subtab in
                                SidebarSubtabRow(
                                    subtab: subtab,
                                    parent: tab,
                                    isActive: sidebar.activeTab == tab && activeSubtab == subtab,
                                    hasNotification: engine.notifiedSubtabs.contains(subtab),
                                    onTap: {
                                        sidebar.selectSubtab(subtab, in: tab, engine: engine)
                                    }
                                )
                            }
                        }
                    }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.85), value: sidebar.activeTab)
            }

            Spacer(minLength: 0)

            // Speedrun status footer (when active). Hidden entirely
            // otherwise — no slot reserved, no layout shift on inactive runs.
            if engine.speedrunQuick.isActive {
                Divider().background(Color.white.opacity(0.1))
                SpeedrunStatusView(engine: engine, layout: .regular)
            }

            // Collapse toggle
//            Button {
//                withAnimation(.easeInOut(duration: 0.25)) {
//                    sidebar.isCollapsed = true
//                }
//            } label: {
//                Image(systemName: "sidebar.left")
//                    .font(.system(size: 16))
//                    .foregroundStyle(.white.opacity(0.4))
//                    .frame(maxWidth: .infinity)
//                    .frame(height: 44)
//                    .contentShape(Rectangle())
//            }
//            .buttonStyle(.plain)
        }
        .frame(width: Self.width)
        //.background(Color(red: 0.12, green: 0.11, blue: 0.14))  // #1d1b22
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    // Swipe left to collapse
                    if value.translation.width < -60 && abs(value.translation.height) < 100 {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            sidebar.isCollapsed = true
                        }
                    }
                }
        )
    }
}
