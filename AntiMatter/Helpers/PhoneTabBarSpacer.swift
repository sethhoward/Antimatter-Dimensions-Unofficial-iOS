//
//  PhoneTabBarSpacer.swift
//  AntiMatter
//
//  Transparent spacer that adds bottom clearance inside ScrollView
//  content on iPhone so the last row scrolls above the overlay tab bar.
//  No-ops on iPad (LayoutMetrics.isCompact == false → zero height).
//
//  Usage: drop as the last child inside any ScrollView's VStack:
//
//      ScrollView {
//          VStack {
//              // ... content ...
//              PhoneTabBarSpacer()
//          }
//      }
//

import SwiftUI

struct PhoneTabBarSpacer: View {
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        if metrics.isCompact {
            Color.clear.frame(height: 56)
        }
    }
}
