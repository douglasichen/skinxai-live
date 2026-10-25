import SwiftUI

/// Press feedback for compact controls (segments, list rows, page dots): a firmer squash than
/// `PressableStyle`, which is tuned for big cards, and the same light tap the moment it's pressed.
/// The action shouldn't tap again.
struct ControlPressStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.tap() } }
    }
}
