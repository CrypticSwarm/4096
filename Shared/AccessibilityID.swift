/// Accessibility identifiers for elements the UI tests look up.
///
/// Files in `Shared/` are compiled into both the app and the UI test target,
/// so the identifiers have a single definition.
enum AccessibilityID {
    static let title = "title"
    /// The score box; its accessibility value is the score.
    static let score = "score"
    /// The best score box; its accessibility value is the high score.
    static let best = "best"
    static let newGame = "newGame"
    static let undo = "undo"
    static let redo = "redo"
    /// The board container; its accessibility value is the board's notation.
    static let board = "board"
    /// The title of the alert that confirms a new game. Alerts don't take
    /// identifiers, so the UI tests find it by its title.
    static let newGameAlertTitle = "Start a new game?"

    /// The cell at `row` and `column` (0-based, from the top left); its label
    /// is the tile's value or "Empty".
    static func cell(row: Int, column: Int) -> String {
        "cell-\(row)-\(column)"
    }
}
