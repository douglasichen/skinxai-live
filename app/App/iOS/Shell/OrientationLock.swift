import UIKit

/// Which way the app may turn: portrait everywhere, landscape only while the live monitor is up.
/// `AppDelegate` reports `mask` to UIKit; `set(_:)` changes it and turns the screen right away.
///
///     OrientationLock.set(.landscape)   // the live monitor opens
///     OrientationLock.set(.portrait)    // it closes
@MainActor
enum OrientationLock {
    /// The orientations the app allows right now. Default: portrait.
    private(set) static var mask: UIInterfaceOrientationMask = .portrait

    /// Allows only `mask` and rotates the interface to it now (for `.landscape` UIKit picks the side).
    static func set(_ mask: UIInterfaceOrientationMask) {
        self.mask = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            // UIKit asks the app delegate again only after a view controller says the answer changed:
            // tell the root and everything presented on it (the monitor is a full-screen cover).
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}
