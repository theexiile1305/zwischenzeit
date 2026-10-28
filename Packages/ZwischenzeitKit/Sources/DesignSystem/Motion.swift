import SwiftUI

public extension DS {
    /// Animations that switch off under Reduce Motion. Read `\.accessibilityReduceMotion` in the view
    /// and pass it in; `nil` means "change instantly".
    enum Motion {
        public static func snappy(reduce: Bool) -> Animation? { reduce ? nil : .snappy }

        /// `withAnimation` that does nothing special when motion is reduced.
        @MainActor
        public static func perform(reduce: Bool, _ body: () -> Void) {
            withAnimation(snappy(reduce: reduce), body)
        }
    }
}
