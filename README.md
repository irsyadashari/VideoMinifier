# Video Minifier

A lightweight, native iOS app that shrinks the videos in your Photos library, so you can reclaim storage without leaving your device or uploading anything.

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI-informational)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

## Overview


https://github.com/user-attachments/assets/ff917243-d864-4f2a-8dba-5acc30ebb2db



Large videos are the biggest consumers of space on most phones. Video Minifier lets you pick any video from your library, choose a target resolution, and re-encode it on-device using Apple's AVFoundation. You see exactly how much space you saved before deciding whether to keep the original.

## Features

- **Photo library browser**: a 3-column grid of all your videos, newest first, with thumbnails.
- **Live preview**: watch the video and see its original file size before compressing.
- **Three quality presets**: High (1080p), Medium (720p), Low (540p).
- **Progress and ETA**: real-time percentage and estimated time remaining while compressing.
- **Before / after comparison**: see the original size, compressed size, and space saved.
- **Size-increase warning**: if the result is larger than the original (the video was already well compressed), you're warned and can discard it.
- **Flexible saving**: save the new video and keep the original, or save and delete the original in one step.
- **Quick delete**: remove a video straight from the preview screen.
- **100% on-device**: no network, no accounts, no third-party SDKs.

## How It Works

1. Grant access to your Photo Library.
2. Select a video from the grid.
3. Pick a quality preset and tap **Start Compressing**.
4. Review the size comparison, then choose **Keep Original & Save New** or **Delete Original & Save New**.

Compression uses `AVAssetExportSession` with the resolution presets `AVAssetExportPreset1920x1080`, `1280x720`, and `960x540`, exporting to MP4 with network-optimized layout.

## Requirements

| Requirement | Version |
|---|---|
| Xcode | Version that supports the iOS 26.1 SDK |
| iOS / iPadOS deployment target | 26.1 |
| Swift | 5 |

## Getting Started

```bash
git clone https://github.com/irsyadashari/VideoMinifier.git
cd VideoMinifier
open "Video Minifier.xcodeproj"
```

1. Select the **Video Minifier** scheme and a simulator or a connected device.
2. Under *Signing & Capabilities*, choose your own development team.
3. Press **⌘R** to build and run.

> Tip: run on a real device for meaningful results. The simulator's photo library has very few videos, and compression is much slower there.

## Permissions

The app requests the following in `Info.plist`:

| Key | Purpose |
|---|---|
| `NSPhotoLibraryUsageDescription` | Let you choose which video to compress |
| `NSPhotoLibraryAddUsageDescription` | Save the compressed video back to your library |

## Project Structure

```
Video Minifier/
├── Video_MinifierApp.swift          # App entry point
├── VideoBrowserView.swift           # Video grid, permission and empty states
├── VideoLibraryViewModel.swift      # Photos fetch, authorization, change observer
├── VideoThumbnail.swift             # Thumbnail loading for grid cells
├── CompressorView.swift             # Preview, compression, results, save/delete
├── QualityOption.swift              # Quality presets mapped to AVFoundation
└── Assets.xcassets/                 # App icon and accent color
```

## Tech Stack

- **SwiftUI**: declarative UI
- **Photos / PhotosUI**: library access, asset fetching, saving and deleting
- **AVFoundation / AVKit**: video playback and export
- **Combine**: observable view model state

## Notes and Limitations

- Compression is lossy. Keep the original unless you are sure about the result.
- Already heavily compressed videos (e.g. screen recordings, downloaded clips) may come out larger; the app will tell you.
- Videos stored in iCloud are downloaded on demand before processing, which requires a network connection.
- Keep the app in the foreground while compressing.

## Roadmap Ideas

- Custom bitrate / resolution controls
- Batch compression of multiple videos
- Background processing and notifications
- Estimated output size before compressing

## Author

**Muh Irsyad Ashari**: [@irsyadashari](https://github.com/irsyadashari)
