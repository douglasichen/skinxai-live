import SwiftUI
import UIKit
import EczemaKit

@main
struct EczemaTwinApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The watch link starts with the process: WatchConnectivity may wake the app in the
        // background to deliver episodes, and then no screen appears.
        WatchInbox.shared.activate()
        // The live session follows the watch from launch, whatever screen is up.
        _ = LiveSession.shared
        // The chat hears the hidden "Replay last Claude chat" control even before Insight is opened.
        _ = ChatSession.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.light)
                .tint(Twin.Palette.ink)
                // The phone is mirrored to the big screen and lies on a stand for minutes at a time
                // (Douglas "asleep", the chat): it never locks while the app is in front.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    UIApplication.shared.isIdleTimerDisabled = phase == .active
                }
        }
    }
}

/// UIKit hooks SwiftUI has no API for: the orientations the app allows right now (`OrientationLock`:
/// portrait, landscape while the live monitor is up).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
