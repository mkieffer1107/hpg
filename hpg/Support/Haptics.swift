import SwiftUI
import UIKit

/// Small, consistent haptics: a light tap for buttons and links, a selection tick for
/// tabs, toggles and steppers, and notification buzzes for login success and failures.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    static func tap() { light.impactOccurred() }
    static func select() { selection.selectionChanged() }
    static func success() { notification.notificationOccurred(.success) }
    static func warning() { notification.notificationOccurred(.warning) }
    static func error() { notification.notificationOccurred(.error) }
}

extension Binding {
    /// The same binding, calling `action` whenever it's set (used for haptics on toggles and tabs).
    func onChange(_ action: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0; action($0) })
    }
}
