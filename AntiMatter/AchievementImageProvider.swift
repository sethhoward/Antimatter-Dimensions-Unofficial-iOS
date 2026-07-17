//
//  AchievementImageProvider.swift
//  AntiMatter
//
//  Crops individual achievement tiles from the sprite sheets at runtime.
//  Normal sprite sheet: 832x1872 px, 8 columns x 18 rows, each tile 104x104 px.
//  Secret sprite sheet: 832x416 px,  8 columns x 4 rows,  each tile 104x104 px.
//  Position formula (both): x = (column-1)*104, y = (row-1)*104.
//

import UIKit

final class AchievementImageProvider {
    static let shared = AchievementImageProvider()

    private let normalSheet: CGImage?
    private let secretSheet: CGImage?
    private var normalCache: [Int: UIImage] = [:]
    private var secretCache: [Int: UIImage] = [:]
    private let tileSize: CGFloat = 104

    private init() {
        normalSheet = Self.loadSheet(named: "normal-achievements")
        secretSheet = Self.loadSheet(named: "secret-achievements")
    }

    private static func loadSheet(named name: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else {
            print("🔴 AchievementImageProvider: missing \(name).png")
            return nil
        }
        return img.cgImage
    }

    func image(for achievement: AchievementState) -> UIImage? {
        if let cached = normalCache[achievement.id] { return cached }
        guard let cropped = crop(sheet: normalSheet, column: achievement.column, row: achievement.row) else { return nil }
        normalCache[achievement.id] = cropped
        return cropped
    }

    func image(for secret: SecretAchievementInfo) -> UIImage? {
        if let cached = secretCache[secret.id] { return cached }
        guard let cropped = crop(sheet: secretSheet, column: secret.column, row: secret.row) else { return nil }
        secretCache[secret.id] = cropped
        return cropped
    }

    private func crop(sheet: CGImage?, column: Int, row: Int) -> UIImage? {
        guard let sheet = sheet else { return nil }
        let x = CGFloat(column - 1) * tileSize
        let y = CGFloat(row - 1) * tileSize
        let rect = CGRect(x: x, y: y, width: tileSize, height: tileSize)
        guard let cropped = sheet.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped)
    }
}
