//
//  CompressionActivityManager.swift
//  Video Minifier
//
//  Created by Muh Irsyad Ashari on 10/13/26.
//

import ActivityKit
import Combine
import UIKit
import UserNotifications

/// Owns everything that has to keep working while the user is looking at
/// another app: the Live Activity, the completion notification, and the
/// background runtime the export borrows from the system.
final class CompressionActivityManager: ObservableObject {

    private var activity: Activity<CompressionActivityAttributes>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var lastUpdate: Date = .distantPast

    /// ActivityKit throttles frequent updates, and the export timer ticks ten
    /// times a second, so updates are coalesced to roughly one per second.
    private let minimumUpdateInterval: TimeInterval = 1.0

    deinit {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
    }

    // MARK: - Notifications

    func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Only fires when the app is not in front: on screen the UI already says this.
    private func notifyIfBackgrounded(title: String, body: String) {
        DispatchQueue.main.async {
            guard UIApplication.shared.applicationState != .active else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content,
                                                trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Background Runtime

    /// Buys the export the extra seconds iOS grants a backgrounded app.
    /// `onExpiration` runs just before that time runs out.
    func beginBackgroundTask(onExpiration: @escaping () -> Void) {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Video Compression") {
            DispatchQueue.main.async {
                onExpiration()
                self.endBackgroundTask()
            }
        }
    }

    func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Live Activity

    func start(videoName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }

        let state = CompressionActivityAttributes.ContentState(phase: .preparing,
                                                              progress: 0,
                                                              statusText: "Preparing video",
                                                              etaText: nil)
        do {
            activity = try Activity.request(
                attributes: CompressionActivityAttributes(videoName: videoName),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            lastUpdate = Date()
        } catch {
            // Live Activities may be off for the app; compression still runs.
            activity = nil
        }
    }

    func update(phase: CompressionActivityAttributes.Phase,
                progress: Double,
                statusText: String,
                etaText: String?,
                force: Bool = false) {
        guard let activity = activity else { return }

        let now = Date()
        guard force || now.timeIntervalSince(lastUpdate) >= minimumUpdateInterval else { return }
        lastUpdate = now

        let state = CompressionActivityAttributes.ContentState(phase: phase,
                                                              progress: progress,
                                                              statusText: statusText,
                                                              etaText: etaText)
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// Shows the activity as paused and tells the user it needs the app back.
    func pause(progress: Double) {
        update(phase: .paused,
               progress: progress,
               statusText: "Paused — reopen to finish",
               etaText: nil,
               force: true)

        notifyIfBackgrounded(title: "Compression paused",
                             body: "iOS stopped the export in the background. Open Video Minifier to finish it.")
    }

    func finish(savedText: String) {
        endActivity(phase: .done, statusText: "Compression complete")
        notifyIfBackgrounded(title: "Compression complete",
                             body: savedText)
    }

    func fail(message: String) {
        // No activity means nothing was running; stay quiet.
        guard activity != nil else {
            endBackgroundTask()
            return
        }
        endActivity(phase: .failed, statusText: "Compression failed")
        notifyIfBackgrounded(title: "Compression failed", body: message)
    }

    /// Clears the activity without a notification, e.g. when leaving the screen.
    func cancel() {
        endActivity(phase: .failed, statusText: "Compression cancelled")
        endBackgroundTask()
    }

    private func endActivity(phase: CompressionActivityAttributes.Phase, statusText: String) {
        endBackgroundTask()

        guard let activity = activity else { return }
        self.activity = nil

        let state = CompressionActivityAttributes.ContentState(phase: phase,
                                                              progress: 1,
                                                              statusText: statusText,
                                                              etaText: nil)
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil),
                               dismissalPolicy: .after(Date().addingTimeInterval(8)))
        }
    }
}
