import SwiftUI

/// The watch app is one screen. The title sits on the system clock's line; the screen gets the
/// rest, from just under the clock to `bottomMargin` above the bottom edge (the system's safe area
/// keeps far more room for a navigation bar and corner toolbar than this screen needs).
struct WatchRootView: View {
    /// The screen starts this far below the middle of the clock row.
    private static let belowClock: CGFloat = 10
    private static let bottomMargin: CGFloat = 16
    private static let titleLeading: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let ins = geo.safeAreaInsets
            let clockRow = max(30, ins.top)
            let top = clockRow / 2 + Self.belowClock
            let fullW = geo.size.width + ins.leading + ins.trailing
            let fullH = geo.size.height + ins.top + ins.bottom
            ZStack(alignment: .topLeading) {
                MonitorScreen()
                    .frame(width: fullW, height: max(0, fullH - top - Self.bottomMargin))
                    .offset(x: -ins.leading, y: top - ins.top)
                WatchTitle()
                    .frame(height: clockRow, alignment: .center)
                    .offset(x: Self.titleLeading - ins.leading, y: -ins.top)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(Color.black.ignoresSafeArea())
    }
}
