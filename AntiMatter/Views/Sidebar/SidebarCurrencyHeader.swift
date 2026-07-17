//
//  SidebarCurrencyHeader.swift
//  AntiMatter
//
//  Currency display at the top of the sidebar.
//  Shows current resource value + name, tap to cycle between resources.
//

import SwiftUI

struct SidebarCurrencyHeader: View {
    let engine: GameEngine
    @State private var resourceIndex: Int = 0

    /// Cycle order mirrors web `sidebar-resources.js` so iOS surfaces
    /// progressively unlock the same resources the web sidebar offers.
    /// "Reality Machines" shows RM only — the combined RM + iM readout has
    /// its own "Machines" entry, gated on Imaginary Machines unlock.
    private var resources: [(value: String, name: String, color: Color)] {
        var list: [(String, String, Color)] = [
            (engine.antimatter, "Antimatter", GameColor.antimatter)
        ]
        if engine.infinityUnlocked {
            list.append((engine.currentIP, "Infinity Points", GameColor.infinity))
        }
        if engine.replicantiUnlocked {
            list.append((engine.replicantiAmountHeader, "Replicanti", GameColor.replicanti))
        }
        if engine.eternityUnlocked {
            list.append((engine.currentEP, "Eternity Points", GameColor.eternity))
            list.append((engine.currentTT, "Time Theorems", GameColor.eternity))
        }
        if engine.dilationUnlocked {
            list.append((engine.currentTP, "Tachyon Particles", GameColor.dilationGreen))
            list.append((engine.currentDT, "Dilated Time", GameColor.dilationGreen))
        }
        if engine.realityUnlocked {
            list.append((engine.currentRM, "Reality Machines", GameColor.reality))
        }
        if engine.effarigUnlocked {
            list.append((engine.currentRelicShards, "Relic Shards", GameColor.effarig))
        }
        if engine.imaginaryUpgradesUnlocked {
            list.append((engine.currentImaginaryMachines, "Imaginary Machines", GameColor.reality))
            list.append((engine.currentMachinesCombined, "Machines", GameColor.reality))
        }
        if engine.laitelaUnlocked {
            list.append((engine.currentDarkMatter, "Dark Matter", GameColor.laitela))
            list.append((engine.currentDarkEnergy, "Dark Energy", GameColor.laitela))
            list.append((engine.currentSingularities, "Singularities", GameColor.laitela))
        }
        if engine.pelleDoomed {
            list.append((engine.pelleRealityShardsText, "Reality Shards", GameColor.pelle))
        }
        return list
    }

    private var current: (value: String, name: String, color: Color) {
        let idx = resourceIndex % max(resources.count, 1)
        return resources.indices.contains(idx) ? resources[idx] : resources[0]
    }

    var body: some View {
        Button {
            resourceIndex = (resourceIndex + 1) % max(resources.count, 1)
        } label: {
            CurrencyDisplay(value: current.value, name: current.name, color: current.color)
        }
        .buttonStyle(.plain)
        .onChange(of: resources.count) { old, new in
            guard old != new, resourceIndex >= new else { return }
            resourceIndex = 0
        }
    }
}

/// Isolated currency value + name display — prevents parent from re-evaluating
/// layout when only the formatted number string changes at 30 Hz.
private struct CurrencyDisplay: View {
    let value: String
    let name: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: dynamicFontSize, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.4)

            Text(name)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .background(GameColor.sidebarBackground)
        .contentShape(Rectangle())
    }

    private var dynamicFontSize: CGFloat {
        let len = value.count
        if len < 10 { return 22 }
        if len < 15 { return 18 }
        return 14
    }
}
