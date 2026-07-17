//
//  AutomatorControlsBar.swift
//  AntiMatter
//
//  Play/pause/stop/step/rewind controls and toggle buttons for the Automator.
//  Matches AutomatorControls.vue button logic and layout.
//

import SwiftUI

struct AutomatorControlsBar: View {
    let engine: GameEngine
    @Environment(\.layoutMetrics) private var metrics
    private var state: AutomatorEditorState { engine.gameState.automatorEditorState }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                // Rewind
                controlButton(
                    icon: "backward.end.fill",
                    tooltip: "Restart",
                    isActive: false,
                    isEnabled: state.isOn
                ) {
                    engine.automatorRewind()
                }

                // Play / Pause
                controlButton(
                    icon: state.isRunning ? "pause.fill" : "play.fill",
                    tooltip: state.isRunning ? "Pause" : (state.isPaused ? "Resume" : "Run"),
                    isActive: state.isRunning,
                    isEnabled: true
                ) {
                    engine.automatorPlay()
                }

                // Stop
                controlButton(
                    icon: "stop.fill",
                    tooltip: "Stop",
                    isActive: false,
                    isEnabled: state.isOn
                ) {
                    engine.automatorStop()
                }

                // Step
                controlButton(
                    icon: "forward.frame.fill",
                    tooltip: "Single step",
                    isActive: false,
                    isEnabled: true
                ) {
                    engine.automatorStep()
                }

                Divider()
                    .frame(height: 24)
                    .background(Color.white.opacity(0.2))

                // Repeat toggle
                toggleButton(
                    icon: "arrow.2.squarepath",
                    tooltip: "Repeat",
                    isActive: state.repeatOn
                ) {
                    engine.automatorToggleRepeat()
                }

                // Force restart toggle
                toggleButton(
                    icon: "arrow.uturn.backward",
                    tooltip: "Restart on Reality",
                    isActive: state.forceRestartOn
                ) {
                    engine.automatorToggleForceRestart()
                }

                // Follow execution toggle
                toggleButton(
                    icon: "text.line.first.and.arrowtriangle.forward",
                    tooltip: "Follow execution",
                    isActive: state.followExecution
                ) {
                    engine.automatorToggleFollowExecution()
                }

                Spacer()

                // Speed indicator — iPad only (iPhone moves it into status line).
                if !metrics.isCompact {
                    Text(state.intervalText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Status line — combines running-script label with speed on iPhone.
            statusLine
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Status line

    @ViewBuilder
    private var statusLine: some View {
        let hasStatus = !state.statusText.isEmpty
        // iPhone always shows the line (to surface the speed indicator even when
        // idle). iPad hides when there's no status text.
        if hasStatus || metrics.isCompact {
            HStack(spacing: 6) {
                if state.isRunning {
                    Circle()
                        .fill(GameColor.reality)
                        .frame(width: 6, height: 6)
                }
                if hasStatus {
                    Text(state.statusText)
                        .font(.caption)
                        .foregroundStyle(state.isRunning ? GameColor.reality : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if state.currentLine > 0 {
                        Text("(Line \(state.currentLine))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if metrics.isCompact {
                    Text(state.intervalTextCompact)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Button builders

    private func controlButton(icon: String, tooltip: String, isActive: Bool, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isActive ? GameColor.reality : (isEnabled ? .white : .white.opacity(0.3)))
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? GameColor.automatorActive : Color(white: 0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isActive ? GameColor.reality : Color.white.opacity(0.15), lineWidth: 1)
                )
        }
        .allowsHitTesting(isEnabled)
        .accessibilityLabel(tooltip)
    }

    private func toggleButton(icon: String, tooltip: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? GameColor.reality : .white.opacity(0.4))
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? GameColor.automatorActive : Color(white: 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isActive ? GameColor.reality : Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .accessibilityLabel(tooltip)
    }
}
