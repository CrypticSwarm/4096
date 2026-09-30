/// Accessibility identifiers for elements the UI tests look up.
///
/// Files in `Shared/` are compiled into both the app and the UI test target,
/// so the identifiers have a single definition.
enum AccessibilityID {
    static let title = "title"
    /// The board container; its accessibility value is the board's notation.
    static let board = "board"

    /// The cell at `row` and `column` (0-based, from the top left); its label
    /// is the tile's value or "Empty".
    static func cell(row: Int, column: Int) -> String {
        "cell-\(row)-\(column)"
    }
}
