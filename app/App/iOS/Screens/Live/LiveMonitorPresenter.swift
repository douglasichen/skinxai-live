import SwiftUI
import UIKit

/// Puts the live monitor over everything, full screen and sideways, and takes it away again.
///
/// The monitor is a full-screen modal presentation (what `.fullScreenCover` does underneath), owned
/// here instead of by the pill: it stays up when the pill hides (3.5 s without batches), the watch's
/// Stop can close it from anywhere, and `-screen live` can open it at launch.
///
/// Opening: a blank page dissolves in over Today → the phone turns to landscape
/// (`OrientationLock`) → the monitor fades in. Closing: the monitor fades out → portrait → the
/// page dissolves away to Today. The screen stays awake (the app keeps it awake whenever it is active,
/// see `EczemaTwinApp`).
@MainActor
final class LiveMonitorPresenter: ObservableObject {
    static let shared = LiveMonitorPresenter()

    enum Phase { case closed, opening, open, closing }
    @Published private(set) var phase: Phase = .closed
    /// The monitor's content is on screen (it fades in once the phone is sideways).
    @Published private(set) var contentShown = false

    static let goodMorning = "Good morning, Douglas · last night is ready"

    private weak var controller: UIViewController?
    private var greetWhenClosed = false
    /// Bumped to cancel steps scheduled with `after(_:_:)`.
    private var stepToken = 0

    /// Opens the monitor over whatever is on screen (Today, from the pill).
    func open() {
        guard phase == .closed, let host = Self.topController() else { return }
        greetWhenClosed = false
        contentShown = false
        phase = .opening
        stepToken += 1

        let monitor = LiveMonitorController(rootView: LiveMonitorRoot(presenter: self))
        monitor.modalPresentationStyle = .fullScreen
        monitor.modalTransitionStyle = .crossDissolve
        monitor.overrideUserInterfaceStyle = .light
        monitor.view.backgroundColor = .white
        controller = monitor
        UIApplication.shared.isIdleTimerDisabled = true      // a monitor on a stand must not lock
        host.present(monitor, animated: true) { [weak self] in
            guard let self, self.phase == .opening else { return }
            OrientationLock.set(.landscape)
            // The content fades in when the page reports a landscape size; this is the fallback.
            self.after(1.1) { self.reveal() }
        }
        // UIKit can refuse a presentation (the screen below is mid-transition): then the completion
        // never runs. Don't stay stuck half-open; the next tap tries again.
        after(1.5) {
            guard self.phase == .opening, monitor.presentingViewController == nil else { return }
            self.phase = .closed
            self.controller = nil
            if OrientationLock.mask != .portrait { OrientationLock.set(.portrait) }
        }
    }

    /// "Done": back to portrait and to the screen underneath. If the watch had gone quiet (its Stop
    /// never reached the phone), this is the wake-up: Today greets the morning as the monitor goes.
    func close() {
        guard phase == .opening || phase == .open else { return }
        if LiveSession.shared.greetAfterQuiet() { greetWhenClosed = true }
        startClosing()
    }

    /// The watch's Stop (never mere silence). An open monitor closes itself and Today (underneath)
    /// greets the morning; a closed one has nothing to do (the pill hides on its own).
    func watchDidStop() {
        guard phase != .closed else { return }
        greetWhenClosed = true
        startClosing()
    }

    /// `-screen live`: open as soon as there is a window (with the stand-in watch, once it tracks).
    func openWhenReady(waitForTracking: Bool) {
        let started = Date()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            while Date().timeIntervalSince(started) < 8 {
                let waited = Date().timeIntervalSince(started)
                let ready = UIApplication.shared.applicationState == .active && Self.topController() != nil
                let tracking = !waitForTracking || LiveSession.shared.tracking || waited > 4
                if ready && tracking {
                    self?.open()
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    /// The monitor page's size (it turns with the phone).
    func pageResized(to size: CGSize) {
        guard phase == .opening, size.width > size.height else { return }
        after(0.25) { self.reveal() }                        // let the turn settle first
    }

    // MARK: - Private

    private func reveal() {
        guard phase == .opening else { return }
        phase = .open
        withAnimation(.timingCurve(0.22, 0.9, 0.24, 1, duration: 0.5)) { contentShown = true }
    }

    private func startClosing() {
        guard phase == .opening || phase == .open else { return }
        phase = .closing
        stepToken += 1
        withAnimation(.easeOut(duration: 0.2)) { contentShown = false }
        after(0.2) {
            OrientationLock.set(.portrait)
            self.after(0.4) { self.dismiss() }               // the turn takes ~0.3 s
        }
    }

    private func dismiss() {
        guard phase == .closing else { return }
        guard let monitor = controller, let below = monitor.presentingViewController else {
            finish()
            return
        }
        below.dismiss(animated: true) { [weak self] in self?.finish() }
    }

    private func finish() {
        phase = .closed
        controller = nil
        if OrientationLock.mask != .portrait { OrientationLock.set(.portrait) }
        if greetWhenClosed {
            greetWhenClosed = false
            Haptics.success()
            NotificationCenter.default.postTwinToast(Self.goodMorning)
        }
    }

    /// Runs `step` after `seconds` unless a newer sequence started meanwhile.
    private func after(_ seconds: Double, _ step: @escaping @MainActor () -> Void) {
        let token = stepToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.stepToken == token else { return }
            step()
        }
    }

    /// The controller everything else is presented from: the key window's root, or what it presents.
    static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first,
              var top = window.rootViewController else { return nil }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}

/// The monitor's page: no status bar, the home indicator hides itself.
final class LiveMonitorController: UIHostingController<LiveMonitorRoot> {
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
}

/// The page under the monitor: white paper that turns with the phone, and the monitor fading in on it.
struct LiveMonitorRoot: View {
    @ObservedObject var presenter: LiveMonitorPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            LiveMonitorView(wide: geo.size.width >= geo.size.height) { presenter.close() }
                .opacity(presenter.contentShown ? 1 : 0)
                .offset(y: presenter.contentShown || reduceMotion ? 0 : 12)
                .allowsHitTesting(presenter.phase == .open)
                .onAppear { presenter.pageResized(to: geo.size) }
                .onChange(of: geo.size) { _, size in presenter.pageResized(to: size) }
        }
        .background(Twin.Palette.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}
