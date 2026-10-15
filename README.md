# Video Minifier

A native iOS app that finds the videos eating your storage and shrinks them on the device, one at a time or as a whole batch, plus a Clean Up tool for duplicate photos and QR-code screenshots. Nothing is uploaded.

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS-blue)
![iOS](https://img.shields.io/badge/iOS-17.4%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI-informational)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

## Overview


https://github.com/user-attachments/assets/ff917243-d864-4f2a-8dba-5acc30ebb2db



Large videos are the biggest consumers of space on most phones, and usually it's a handful of them. Video Minifier points at the worst offenders, re-encodes them on-device with AVFoundation, and shows exactly how much space each one gave back. Compress a single video, or queue up several and keep using the app while they work.

## Features

### Find what's taking space
- **Free Up Space**: the home screen lists your largest videos (over 100 MB), biggest first. The rest are one tap away in **Compress several**.
- **Two sources**: pick from your Photos library, or open any video file from the Files app.

### Compress one video
- **Light preview**: the preview streams a low-quality copy and doesn't autoplay, so checking a video doesn't burn through mobile data. iCloud downloads show progress and an ETA.
- **Three quality presets**: High (1080p), Medium (720p), Low (540p).
- **Progress and ETA** while compressing, then a **before / after** size comparison.
- **Size-increase warning**: if the result came out bigger (the video was already well compressed), you're told and can discard it.
- **Flexible saving**: keep or delete the original. Videos from Files can be saved back to Files or into Photos.

### Compress several at once
- **Batch picker**: tick any number of large videos, with one quality and one originals setting for the whole batch. It defaults to **Delete originals**, marked with a warning.
- **Background queue**: videos compress one after another while you keep using the app. A floating progress pill on every screen opens the queue.
- **Safe by design**: a copy that wouldn't be smaller is skipped automatically. Originals are only deleted once every copy is saved, in a single system confirmation at the end.

### Survives interruptions
- **Pauses, never restarts**: if you leave the app, encoding continues for about 20 seconds, then saves a checkpoint. When you come back it carries on from that point instead of starting over.
- **Live Activity** on the Lock Screen (and Dynamic Island), plus a notification when a batch finishes or pauses while you're in another app.

### Fast, careful encoding
- **Reader/writer pipeline** instead of a stock export preset: no extra "fast start" pass, AAC audio copied through untouched, and video and audio processed in parallel.
- **HDR stays HDR**: 10-bit HDR video is encoded as HEVC Main10; SDR video as H.264 High.
- **Sensible bitrates**: never above the source's own bitrate, and never upscaled.
- **Fallback**: anything the pipeline can't handle goes through `AVAssetExportSession` instead.

### Clean Up
- **Finds duplicates and QR codes**: photos and videos that look duplicated (perceptual hashing), and photos containing a QR code (Vision).
- **Stays on the device**: only local copies are scanned, so a scan never downloads your iCloud library.
- **Scans in batches**: 150 items at a time. **Check more photos** keeps going until it finds something.
- **You decide**: nothing is ticked for you. Hold a row for a bigger look; swipe and choose **Keep** to hide something from future scans (you can bring them all back).
- **Recoverable deletes**: deletion goes through iOS's own confirmation, and items land in Recently Deleted.

### Private
- **100% on-device**: nothing is uploaded, no accounts, no third-party SDKs.

## How It Works

**One video**
1. On the home screen, choose **Photos** or **Files** and pick a video.
2. Check the preview, pick a quality and tap **Start Compressing**.
3. Review the size comparison, then keep or delete the original.

**A batch**
1. In **Free Up Space**, tap **Compress several**.
2. Tick the videos, pick a quality and what happens to the originals, then tap **Compress**.
3. Watch the queue, or keep browsing. The floating pill brings you back to it.

### Under the hood

`VideoCompressor` reads with `AVAssetReader` and writes with `AVAssetWriter`. Video is scaled to fit inside the preset's box (1920×1080, 1280×720 or 960×540) without upscaling, at a bitrate worked out from pixels × frame rate. That's 0.10 bits per pixel for H.264 and 0.065 for HEVC, capped at 90% of the source's data rate.

When asked to stop, the pipeline finalises what it has written into a playable segment and reports the exact time to resume from. The next run starts there, and finished segments are joined with a passthrough remux, so nothing is re-encoded twice.

## Requirements

| Requirement | Version |
|---|---|
| Xcode | 26 or later |
| iOS / iPadOS deployment target | 17.4 |
| Swift | Swift 5 language mode, built with the Swift 6.2 toolchain that ships with Xcode 26 |

## Getting Started

```bash
git clone https://github.com/irsyadashari/VideoMinifier.git
cd VideoMinifier
open "Video Minifier.xcodeproj"
```

1. Select the **Video Minifier** scheme and a simulator or a connected device.
2. Under *Signing & Capabilities*, choose your own development team on **both** targets: **Video Minifier** and **CompressionActivity** (the Live Activity extension).
3. Press **⌘R** to build and run.

> Tip: run on a real device for meaningful results. The simulator's photo library has very few videos, and compression is much slower there. Live Activities show on the Lock Screen; the Dynamic Island needs an iPhone 14 Pro or later.

## Permissions

`Info.plist`:

| Key | Purpose |
|---|---|
| `NSPhotoLibraryUsageDescription` | Read your library to find and compress videos |
| `NSPhotoLibraryAddUsageDescription` | Save compressed videos back to your library |
| `NSSupportsLiveActivities` | Show compression progress on the Lock Screen |
| `NSSupportsLiveActivitiesFrequentUpdates` | Keep that progress up to date |

At runtime the app also asks for **notification** permission the first time you compress, so it can tell you when a batch finishes or pauses. No background modes are declared.

## Project Structure

```
Video Minifier/                         # App target
├── Video_MinifierApp.swift             # Entry point; owns the compression queue
├── RootView.swift                      # Presents the queue sheet from anywhere
├── HomeView.swift                      # Sources, Free Up Space, Clean Up entry
├── LargeVideosViewModel.swift          # Finds the largest videos in the library
├── VideoBrowserView.swift              # Photos video grid
├── VideoLibraryViewModel.swift         # Photos fetch, authorization, change observer
├── VideoThumbnail.swift                # Thumbnail loading
├── CompressorView.swift                # One video: preview, compress, save
├── PreviewPlayer.swift                 # Low-data preview player, audio session
├── QualityOption.swift                 # High / Medium / Low presets
├── VideoCompressor.swift               # Reader/writer pipeline, checkpoints, joining
├── BatchCompressView.swift             # Compress several: pick videos and settings
├── CompressionQueue.swift              # App-wide queue, pause/resume, saving
├── CompressionQueueView.swift          # The queue sheet
├── QueuePill.swift                     # Floating progress pill
├── CompressionActivityManager.swift    # Live Activity, notifications, background time
├── CleanupView.swift                   # Review and delete
├── CleanupViewModel.swift              # Paged scanning, selection, kept items
├── CleanupScanner.swift                # Duplicate hashing and QR detection
├── AssetPreviewSheet.swift             # Full-size look at a photo or video
└── Assets.xcassets/                    # App icon and accent color
CompressionActivity/                    # Live Activity widget extension
Shared/
└── CompressionActivityAttributes.swift # Activity state, shared by app and extension
```

## Tech Stack

- **SwiftUI**: declarative UI
- **Photos / PhotosUI**: library access, fetching, saving and deleting
- **AVFoundation / AVKit**: playback, reading, writing and export
- **VideoToolbox**: HEVC Main10 encoding profile for HDR
- **Vision**: QR code detection
- **ActivityKit + WidgetKit**: the Live Activity
- **UserNotifications**: finish and pause notifications
- **Swift Concurrency and Combine**: async pipelines and observable state

## Notes and Limitations

- Compression is lossy. Keep the original unless you are sure about the result.
- iOS won't run the video encoder in the background indefinitely. About 20 seconds after you leave the app, compression pauses, then resumes from the same point when you come back.
- A video that won't get smaller is skipped in a batch and flagged when compressing one at a time.
- For videos stored only in iCloud, the full-quality original is downloaded when compression starts. The preview uses a lighter copy.
- Clean Up only looks at copies already on the device, and its duplicate matching is approximate. Review before deleting.

## Roadmap Ideas

- Custom bitrate / resolution controls
- Estimated output size before compressing
- Optional 30 fps cap for faster encodes
- Remember batch settings between launches

## Author

**Muh Irsyad Ashari**: [@irsyadashari](https://github.com/irsyadashari)
