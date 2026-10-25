import SwiftUI
import WatchKit
import EczemaKit

@main
struct EczemaTwinWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var model = WatchModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(model)
                .tint(Twin.Palette.yellow)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.appBecameActive()
            case .background: model.appMovedToBackground()
            default: break
            }
        }
    }
}

/// Background refresh: read a little more of the all-day recording, send new episodes to the
/// phone, book the next run. watchOS gives a refresh only a few seconds: the read has its own
/// small budget, and if the task is about to expire it stops reading and the task completes.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        PhoneLink.shared.activate()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            guard let refresh = task as? WKApplicationRefreshBackgroundTask else {
                task.setTaskCompletedWithSnapshot(false)
                continue
            }
            let done = TaskCompletion(refresh)
            refresh.expirationHandler = {
                Task { @MainActor in
                    WatchModel.shared.cancelAnalysis()
                    done.complete()
                }
            }
            Task { @MainActor in
                await WatchModel.shared.backgroundRefresh()
                done.complete()
            }
        }
    }
}

/// Completes a background task once, whichever comes first: the work or the expiration.
private final class TaskCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var task: WKRefreshBackgroundTask?

    init(_ task: WKRefreshBackgroundTask) { self.task = task }

    func complete() {
        lock.lock()
        let t = task
        task = nil
        lock.unlock()
        t?.setTaskCompletedWithSnapshot(false)
    }
}
