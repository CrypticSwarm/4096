extension Board {
    /// Creates a board from its ``notation``: rows top to bottom separated by
    /// `;`, values in a row separated by `,`, 0 for an empty cell, with no
    /// spaces.
    ///
    ///     let board = try Board(notation: "2,0;0,4")  // [[2, 0], [0, 4]]
    ///
    /// - Throws: ``BoardError/unreadableValue(_:)`` if a value isn't an
    ///   integer, otherwise the errors of ``init(rows:)``.
    public init(notation: String) throws(BoardError) {
        var rows: [[Int]] = []
        for row in notation.split(separator: ";", omittingEmptySubsequences: false) {
            var values: [Int] = []
            for text in row.split(separator: ",", omittingEmptySubsequences: false) {
                guard let value = Int(text) else { throw .unreadableValue(String(text)) }
                values.append(value)
            }
            rows.append(values)
        }
        try self.init(rows: rows)
    }

    /// The board as compact text, for example `"2,0;0,4"` (see
    /// ``init(notation:)``). UI tests use it to set up and check boards.
    public var notation: String {
        rows.map { $0.map(String.init).joined(separator: ",") }.joined(separator: ";")
    }
}
