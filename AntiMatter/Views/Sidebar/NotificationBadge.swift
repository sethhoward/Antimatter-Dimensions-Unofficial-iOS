//
//  NotificationBadge.swift
//  AntiMatter
//
//  Yellow exclamation badge matching the web's tab notification indicator.
//  Web CSS: fa-circle-exclamation, color: yellow.
//
//  Static — the previous version pulsed brightness 70%–100% over 2s via
//  `.repeatForever(autoreverses:)`. That attaches a CAAnimation per
//  visible badge that keeps interpolating on the render server even when
//  the app is backgrounded (we tore it down on `.inactive` / `.background`,
//  but still ran continuously when active). With multiple sidebar /
//  PhoneTabBar entries flagged at once, the per-frame compositor cost
//  was non-trivial. iOS sidebar/tab-bar badges are conventionally
//  non-animated; the icon + color is enough signal.
//

import SwiftUI

struct NotificationBadge: View {
    var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(.yellow)
            .shadow(color: .black, radius: 2, x: -1, y: 1)
    }
}
