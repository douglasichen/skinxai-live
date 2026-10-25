import SwiftUI

/// Raft-style phone tab bar. The selected icon sits in a yellow sticker that slides to the next tab
/// with a spring, squashes and stretches on the way, and the new icon bounces when it lands.
/// With Reduce Motion the sticker doesn't travel: it fades out of one slot and into the next.
struct TwinTabBar: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ns
    /// Bumps once per tab change: drives the sticker's squash-and-stretch.
    @State private var travel = 0
    /// Per-tab bounce counters, so only the tab that becomes selected bounces.
    @State private var bounces: [Tab: Int] = [:]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 2)
        // One sticker for the whole bar; it follows the selected icon slot.
        .background {
            if !reduceMotion {
                sticker
                    .matchedGeometryEffect(id: "tab.sticker", in: ns, properties: .frame, isSource: false)
            }
        }
        .background(alignment: .top) {
            Twin.Palette.paper
                .overlay(alignment: .top) { Rectangle().fill(Twin.Palette.seam).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.74), value: app.tab)
        .onChange(of: app.tab) { _, new in
            travel += 1
            bounces[new, default: 0] += 1
        }
    }

    private var sticker: some View {
        RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous)
            .fill(Twin.Palette.yellow)
            .overlay(RoundedRectangle(cornerRadius: Twin.Radius.control, style: .continuous)
                .strokeBorder(Twin.Palette.ink, lineWidth: Twin.Stroke.ink))
            .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: travel) { view, scale in
                view.scaleEffect(x: reduceMotion ? 1 : scale.width, y: reduceMotion ? 1 : scale.height)
            } keyframes: { _ in
                KeyframeTrack(\.width) {
                    CubicKeyframe(1.24, duration: 0.14)
                    CubicKeyframe(0.94, duration: 0.16)
                    SpringKeyframe(1, duration: 0.34, spring: .bouncy)
                }
                KeyframeTrack(\.height) {
                    CubicKeyframe(0.84, duration: 0.14)
                    CubicKeyframe(1.06, duration: 0.16)
                    SpringKeyframe(1, duration: 0.34, spring: .bouncy)
                }
            }
            .offset(y: -2)
            .allowsHitTesting(false)
    }

    private func item(_ tab: Tab) -> some View {
        let on = app.tab == tab
        // The press style taps on touch-down, like every button in the app.
        return Button { app.select(tab, haptic: false) } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(on ? Twin.Palette.ink : Twin.Palette.inkMuted)
                    .symbolEffect(.bounce.up, options: .speed(1.3), value: reduceMotion ? 0 : bounces[tab, default: 0])
                    // The selected icon (and its sticker, see `sticker`) sits 2 pt higher.
                    .offset(y: on ? -2 : 0)
                    .frame(width: 48, height: 32)
                    .background {
                        if on {
                            if reduceMotion {
                                sticker.transition(.opacity)
                            } else {
                                Color.clear.matchedGeometryEffect(id: "tab.sticker", in: ns, properties: .frame)
                            }
                        }
                    }
                Text(tab.title)
                    .font(Twin.Typeface.sans(11, on ? .bold : .medium))
                    .foregroundStyle(on ? Twin.Palette.ink : Twin.Palette.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(TabPressStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// Small squash and a light tap on press.
private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Twin.Motion.bouncy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
    }
}
