/// A direction the player can swipe; every tile slides as far as it can that way.
///
/// The raw values are stable and used when a direction is persisted.
public enum Direction: String, CaseIterable, Codable, Sendable {
    /// Toward row 0.
    case up
    /// Toward the last row.
    case down
    /// Toward column 0.
    case left
    /// Toward the last column.
    case right
}

extension Direction {
    /// Maps a point on a line of movement to a board position.
    ///
    /// A board of size `n` has `n` lines parallel to the direction (rows for
    /// left and right, columns for up and down). `offset` counts cells from the
    /// edge the tiles move toward, so offset 0 is where the first tile of the
    /// line ends up. This is the only direction-specific code in the engine: the
    /// slide algorithm walks every line from offset 0 upward.
    func position(line: Int, offset: Int, size: Int) -> Position {
        switch self {
        case .left: Position(row: line, column: offset)
        case .right: Position(row: line, column: size - 1 - offset)
        case .up: Position(row: offset, column: line)
        case .down: Position(row: size - 1 - offset, column: line)
        }
    }
}
