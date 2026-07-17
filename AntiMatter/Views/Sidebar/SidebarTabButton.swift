//
//  SidebarTabButton.swift
//  AntiMatter
//
//  A single tab row in the game sidebar.
//  Dark themed with a colored left accent border when active.
//  Multi-subtab tabs show the active subtab symbol + chevron when collapsed,
//  or just a rotated chevron when expanded (its inline subtab list is visible).
//

import SwiftUI

struct SidebarTabButton: View {
    let tab: SidebarTab
    let isActive: Bool
    let hasSubtabs: Bool
    let isExpanded: Bool
    let activeSubtab: Subtab
    let hasNotification: Bool
    let onTap: () -> Void

    private static let height: CGFloat = 56
    private static let accentWidth: CGFloat = 6

    var body: some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 0) {
                // Colored left accent border
                Rectangle()
                    .fill(isActive ? tab.accentColor : .clear)
                    .frame(width: isActive ? Self.accentWidth : 0)
                    .animation(.easeInOut(duration: 0.2), value: isActive)

                // Tab label + (subtitle when collapsed-but-active)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.displayName)
                        .font(.system(size: 16, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? tab.accentColor : tab.inactiveTextColor)

                    if isActive && hasSubtabs && !isExpanded {
                        Text(activeSubtab.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)

                if hasNotification && !isExpanded {
                    NotificationBadge()
                        .font(.system(size: 14))
                }

                // Right-side affordance for multi-subtab parents.
                // Expanded: just the chevron, rotated 90°.
                // Collapsed: active subtab symbol + chevron pointing right.
                if hasSubtabs {
                    HStack(spacing: 4) {
                        if !isExpanded {
                            SubtabSymbolView(symbol: activeSubtab.symbolType, size: 14)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.2), value: isExpanded)
                    }
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.trailing, 12)
                }
            }
            .frame(height: Self.height)
            .background(isActive ? Color.white.opacity(0.06) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline subtab row (rendered below an expanded parent)

struct SidebarSubtabRow: View {
    let subtab: Subtab
    let parent: SidebarTab
    let isActive: Bool
    let hasNotification: Bool
    let onTap: () -> Void

    private static let height: CGFloat = 36
    private static let leadingPad: CGFloat = 20  // 6pt parent accent + 26pt indent

    /// Drop the redundant "Dimensions" suffix when these subtabs sit under the
    /// "Dimensions" parent — the parent label already supplies that context.
    private var rowName: String {
        if parent == .dimensions, subtab.displayName.hasSuffix(" Dimensions") {
            return String(subtab.displayName.dropLast(" Dimensions".count))
        }
        return subtab.displayName
    }

    var body: some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 6) {
                SubtabSymbolView(symbol: subtab.symbolType, size: 14)
                    .foregroundStyle(isActive ? parent.accentColor : parent.inactiveTextColor.opacity(0.85))

                Text(rowName)
                    .font(.system(size: 14, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? parent.accentColor : parent.inactiveTextColor.opacity(0.85))
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if hasNotification {
                    NotificationBadge()
                        .font(.system(size: 12))
                }
            }
            .padding(.leading, Self.leadingPad)
            .padding(.trailing, 12)
            .frame(height: Self.height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Color.white.opacity(0.04) : .clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isActive ? parent.accentColor : .clear)
                    .frame(height: 1.5)
                    .padding(.leading, Self.leadingPad)
                    .padding(.trailing, 12)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Symbol rendering helper

struct SubtabSymbolView: View {
    let symbol: SubtabSymbol
    let size: CGFloat

    var body: some View {
        switch symbol {
        case .text(let glyph):
            Text(glyph)
                .font(.system(size: size))
        case .sfSymbol(let name):
            Image(systemName: name)
                .font(.system(size: size))
        }
    }
}
