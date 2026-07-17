//
//  ToastOverlay.swift
//  AntiMatter
//
//  Overlay that displays toast notifications (achievement unlocks, etc.)
//  sliding in from the trailing edge, stacked vertically.
//

import SwiftUI

struct ToastOverlay: View {
    let engine: GameEngine

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(engine.toastQueue) { toast in
                ToastView(toast: toast) {
                    engine.dismissToast(id: toast.id)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: engine.toastQueue.count)
        .padding(.top, 8)
        .padding(.trailing, 16)
        .fixedSize()
    }
}

// MARK: - Individual toast

private struct ToastView: View {
    let toast: ToastMessage
    let onDismiss: () -> Void

    private var backgroundColor: Color {
        switch toast.type {
        case "success":      return Color.yellow
        case "error":        return Color.red
        case "modalMessage": return Color.red
        case "info":         return Color.blue
        case "infinity":     return Color.orange
        case "eternity":     return Color.purple
        case "reality":      return Color.green
        default:             return Color.gray
        }
    }

    private var textColor: Color {
        switch toast.type {
        case "success":  return .black
        default:         return .white
        }
    }

    var body: some View {
        Button {
            onDismiss()
        } label: {
            Text(toast.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
                .lineLimit(toast.type == "modalMessage" ? nil : 3)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: 320)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
