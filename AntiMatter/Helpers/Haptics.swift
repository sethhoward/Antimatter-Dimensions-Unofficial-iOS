//
//  Haptics.swift
//  AntiMatter
//
//  Gentle tap feedback for primary buttons. No-op on iPad hardware.
//  Gated by the `buttonHapticsEnabled` UserDefaults flag (default true,
//  registered in `GameEngine.start()`). Toggle lives in Options → Gameplay.
//

import UIKit

enum Haptics {
    static let userDefaultsKey = "buttonHapticsEnabled"

    private static let lightImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()

    /// Gentle tap feedback for primary buttons.
    static func tap() {
        guard UserDefaults.standard.bool(forKey: userDefaultsKey) else { return }
        lightImpact.impactOccurred(intensity: 0.6)
        lightImpact.prepare()
    }
}
