//
//  view.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 12/15/25.
//


import SwiftUI
import Photos

// MARK: - 2. The Thumbnail View (UI Component)
// efficiently loads the image from the PHAsset
struct VideoThumbnail: View {
    let asset: PHAsset
    @State private var image: UIImage?
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.width)
                        .clipped()
                } else {
                    // Placeholder while loading
                    Color.gray.opacity(0.3)
                }
                
                // Video Duration Overlay
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formatDuration(asset.duration))
                            .font(.caption2)
                            .bold()
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .padding(4)
                    }
                }
            }
            .onAppear {
                fetchImage(size: proxy.size)
            }
        }
    }

    private func fetchImage(size: CGSize) {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        
        // Request a slightly larger image for sharpness on Retina screens
        let targetSize = CGSize(width: size.width * 2, height: size.height * 2)
        
        manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { result, _ in
            self.image = result
        }
    }
    
    // Helper to format seconds into MM:SS
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "0:00"
    }
}
