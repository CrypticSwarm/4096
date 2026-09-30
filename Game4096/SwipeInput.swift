import GameCore
import SwiftUI

/// Maps swipes and arrow keys to move directions.
enum SwipeInput {
    /// The shortest drag, in points, that counts as a swipe: short enough
    /// for a quick thumb flick (the original takes 10 px).
    static let minimumDistance: CGFloat = 15

    /// The direction of a drag by `translation`: along its dominant axis, or
    /// `nil` if it is shorter than ``minimumDistance``. As in the original
    /// game, even a diagonal drag picks its longer axis.
    static func direction(of translation: CGSize) -> Direction? {
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        guard max(horizontal, vertical) >= minimumDistance else { return nil }
        if horizontal > vertical {
            return translation.width > 0 ? .right : .left
        }
        return translation.height > 0 ? .down : .up
    }

    /// The direction of an arrow key, or `nil` for any other key.
    static func direction(of key: KeyEquivalent) -> Direction? {
        switch key {
        case .upArrow: .up
        case .downArrow: .down
        case .leftArrow: .left
        case .rightArrow: .right
        default: nil
        }
    }
}

extension View {
    /// Calls `action` for each swipe on this view, and for each arrow key
    /// pressed on a hardware keyboard while the view has focus.
    func onSwipe(perform action: @escaping @MainActor (Direction) -> Void) -> some View {
        modifier(SwipeModifier(action: action))
    }
}

private struct SwipeModifier: ViewModifier {
    let action: @MainActor (Direction) -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: SwipeInput.minimumDistance).onEnded { value in
                    if let direction = SwipeInput.direction(of: value.translation) {
                        action(direction)
                    }
                }
            )
            // Focus lets the arrow keys reach onKeyPress. Holding a key
            // repeats the move, as in the original.
            .focusable()
            .focused($isFocused)
            .defaultFocus($isFocused, true)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                guard let direction = SwipeInput.direction(of: press.key) else { return .ignored }
                action(direction)
                return .handled
            }
            .onAppear { isFocused = true }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    isFocused = true
                }
            }
    }
}
