/// A cell on a board, addressed by row and column.
///
/// Row 0 is the top row and column 0 is the leftmost column, so ``Direction/up``
/// moves tiles toward row 0 and ``Direction/left`` toward column 0.
public struct Position: Hashable, Codable, Sendable, CustomStringConvertible {
    /// The row, counted from the top starting at 0.
    public var row: Int
    /// The column, counted from the left starting at 0.
    public var column: Int

    /// Creates a position from a row and a column.
    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    public var description: String { "(\(row), \(column))" }
}
