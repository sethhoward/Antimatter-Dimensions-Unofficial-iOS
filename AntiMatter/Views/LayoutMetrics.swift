//
//  LayoutMetrics.swift
//  AntiMatter
//
//  Provides device-appropriate sizing constants via @Environment.
//  iPad (regular) gets current hardcoded values; iPhone (compact) gets smaller sizes.
//

import SwiftUI

struct LayoutMetrics {
    let isCompact: Bool

    // Dimension buy buttons
    let dimensionBuyButtonWidth: CGFloat
    let idBuyButtonWidth: CGFloat
    let idBuyMaxWidth: CGFloat

    // Tickspeed row
    let tickspeedCostWidth: CGFloat
    let tickspeedMaxWidth: CGFloat

    // Header
    let headerButtonWidth: CGFloat
    let headerHeight: CGFloat

    // Grids
    let challengeColumns: Int
    let infinityChallengeColumns: Int
    let upgradeColumns: Int

    // Content margins — horizontal padding between the screen edge and card
    // grids. iPhone trims this so narrow cards get more width; iPad keeps the
    // roomier margin. (Vertical padding stays a literal 16 at call sites.)
    let contentHPadding: CGFloat

    // Presets

    static let regular = LayoutMetrics(
        isCompact: false,
        dimensionBuyButtonWidth: 260,
        idBuyButtonWidth: 210,
        idBuyMaxWidth: 70,
        tickspeedCostWidth: 280,
        tickspeedMaxWidth: 110,
        headerButtonWidth: 100,
        headerHeight: 150,
        challengeColumns: 3,
        infinityChallengeColumns: 4,
        upgradeColumns: 3,
        contentHPadding: 16
    )

    static let compact = LayoutMetrics(
        isCompact: true,
        dimensionBuyButtonWidth: 140,
        idBuyButtonWidth: 130,
        idBuyMaxWidth: 50,
        tickspeedCostWidth: 180,
        tickspeedMaxWidth: 90,
        headerButtonWidth: 80,
        headerHeight: 110,
        challengeColumns: 2,
        infinityChallengeColumns: 2,
        upgradeColumns: 2,
        contentHPadding: 8
    )
}

// MARK: - Environment key

private struct LayoutMetricsKey: EnvironmentKey {
    static let defaultValue = LayoutMetrics.regular
}

extension EnvironmentValues {
    var layoutMetrics: LayoutMetrics {
        get { self[LayoutMetricsKey.self] }
        set { self[LayoutMetricsKey.self] = newValue }
    }
}
