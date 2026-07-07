//
//  CloudSyncSection.swift
//  AntiMatter
//
//  iCloud sync toggle + Sync Now button for the Options tab. Actual sync
//  behaviour lives in CloudSaveService; this view only surfaces state and
//  exposes the two user actions (enable toggle, manual sync).
//

import SwiftUI

struct CloudSyncSection: View {
    let engine: GameEngine

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("iCloud Sync")
                    .font(.headline)
                Spacer()
                if let service = engine.cloudSaveService, service.isSyncing || service.isUploading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let service = engine.cloudSaveService {
                Toggle(isOn: Binding(
                    get: { service.syncEnabled },
                    set: { newValue in handleToggle(newValue, service: service) }
                )) {
                    Text("Sync saves via iCloud")
                        .font(.subheadline.weight(.medium))
                }
                .tint(GameColor.good)

                Text(descriptionText(for: service))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if service.syncEnabled {
                    GameButton(borderColor: GameColor.infinity, isEnabled: !service.isSyncing) {
                        service.syncNow()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                            Text("Sync now")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }

                    if let lastSynced = service.lastSyncedAt {
                        Text("Last checked \(relativeString(lastSynced))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("iCloud service not yet ready — try again in a moment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func handleToggle(_ newValue: Bool, service: CloudSaveService) {
        if newValue {
            service.requestEnableSync { ok in
                if !ok {
                    // User cancelled or iCloud unavailable — no-op.
                }
            }
        } else {
            service.disableSync()
        }
    }

    private func descriptionText(for service: CloudSaveService) -> String {
        if !service.isAvailable {
            return "Sign in to iCloud in Settings to enable save sync."
        }
        if !service.syncEnabled {
            return "Keep this slot in sync across your iPhone and iPad. Off by default — your progress never leaves the device unless you turn this on."
        }
        return "Your active slot uploads after each save and reconciles with iCloud when you open the app. Conflicts prompt you to choose; local progress is never silently overwritten."
    }

    private func relativeString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
