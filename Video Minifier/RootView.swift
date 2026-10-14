//
//  RootView.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/14/26.
//

import SwiftUI

/// Hosts the queue sheet, so closing it never loses the way back. The pill
/// itself is attached per screen with .queuePill(), because an inset applied
/// out here cannot reach the scroll views inside the NavigationStack.
struct RootView: View {
    @EnvironmentObject private var queue: CompressionQueue
    
    var body: some View {
        HomeView()
            .sheet(isPresented: $queue.isShowingQueue) {
                NavigationStack {
                    CompressionQueueView()
                }
            }
    }
}
