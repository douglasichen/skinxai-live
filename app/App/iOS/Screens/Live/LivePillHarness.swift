#if DEBUG
import SwiftUI
import UIKit

/// Development only (Debug builds, never in Release): a copy of Today's top bar with the pill in
/// it, so the pill can be filmed while Today itself is built elsewhere. The simulator can't be
/// tapped from the build scripts, so taps are launch arguments:
///
///     -screen livepill         this page at launch (add -liveSim 1 for a watch)
///     -livePillTap <seconds>   tap the pill that long after launch
///     -liveDone <seconds>      tap the monitor's Done that long after launch
enum LivePillHarness {
    static func presentIfRequested() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "screen") == "livepill" else { return }
        let launched = Date()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            for _ in 0..<60 {
                if UIApplication.shared.applicationState == .active, let host = LiveMonitorPresenter.topController() {
                    let page = UIHostingController(rootView: LivePillHarnessPage())
                    page.modalPresentationStyle = .fullScreen
                    page.overrideUserInterfaceStyle = .light
                    host.present(page, animated: false)
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            let tap = defaults.double(forKey: "livePillTap")
            let done = defaults.double(forKey: "liveDone")
            if tap > 0 {
                await sleep(until: launched.addingTimeInterval(tap))
                LiveMonitorPresenter.shared.open()
            }
            if done > 0 {
                await sleep(until: launched.addingTimeInterval(done))
                LiveMonitorPresenter.shared.close()
            }
        }
    }

    private static func sleep(until date: Date) async {
        let wait = date.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
    }
}

/// Today's top bar as the app draws it (yellow frame, title, mono date), with the pill and a "D".
private struct LivePillHarnessPage: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today").font(Twin.Typeface.largeTitle).foregroundStyle(Twin.Palette.ink)
                    Text("SAT · OCT 24").font(Twin.Typeface.meta).tracking(0.6).foregroundStyle(Twin.Palette.frameInk)
                }
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    LivePill()
                    Text("D")
                        .font(Twin.Typeface.sans(15, .bold))
                        .foregroundStyle(Twin.Palette.ink)
                        .frame(width: 36, height: 36)
                        .sticker(Twin.Palette.pink)
                }
            }
            .padding(.horizontal, Twin.Space.screen + 4)
            .padding(.top, 6)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .background(alignment: .bottom) {
                Twin.Palette.frame
                    .overlay(alignment: .bottom) { Rectangle().fill(Twin.Palette.seam).frame(height: 1) }
                    .ignoresSafeArea(edges: .top)
            }
            Spacer()
        }
        .background(Twin.Palette.paper)
    }
}
#endif
