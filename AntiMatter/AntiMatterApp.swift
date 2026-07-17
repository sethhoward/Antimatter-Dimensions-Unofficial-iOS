//
//  AntiMatterApp.swift
//  AntiMatter
//
//  Created by Seth Howard on 3/31/26.
//

import SwiftUI

@main
struct AntiMatterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .dynamicTypeSize(...DynamicTypeSize.large)
             //   .defersSystemGestures(on: .bottom)
        }
    }
}
