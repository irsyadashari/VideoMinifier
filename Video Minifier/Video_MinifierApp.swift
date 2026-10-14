//
//  Video_MinifierApp.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 12/15/25.
//

import SwiftUI

@main
struct Video_MinifierApp: App {
    /// Owned by the app, not a screen, so compression keeps going while the
    /// user moves around.
    @StateObject private var compressionQueue = CompressionQueue()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(compressionQueue)
        }
    }
}
