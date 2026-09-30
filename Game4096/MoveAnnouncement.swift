import GameCore

/// What VoiceOver announces after each change, since the tiles' new places,
/// the score and the messages over the board otherwise go unspoken. One
/// announcement covers a whole change, so that parts of it don't interrupt
/// each other.
enum MoveAnnouncement {
    /// The announcement for `change`, made in `model`'s current state. For
    /// example "Moved left. Made 8. New 2 in row 4, column 2. Score 12.",
    /// followed by the message over the board if the change brought one.
    @MainActor
    static func text(for change: GameModel.Change, in model: GameModel) -> String {
        var sentences: [String] = []
        switch change.kind {
        case .move: break
        case .redo: sentences.append("Redone.")
        case .undo: sentences.append("Move undone.")
        case .newGame: sentences.append("New game. Tiles: \(list(model.layout.tiles.map(describe))).")
        case .keepPlaying: sentences.append("Keep playing.")
        }
        if let transition = change.transition {
            sentences.append(text(for: transition))
        }
        sentences.append("Score \(model.score).")
        if let overlay = model.overlay {
            sentences.append(overlay.title)
            sentences.append(overlay.detail(winningValue: model.winningValue, canUndo: model.canUndo))
        }
        return sentences.joined(separator: " ")
    }

    /// For example "Moved left. Made 8 and 16. New 2 in row 4, column 2."
    static func text(for transition: TileTransition) -> String {
        var sentences = ["Moved \(transition.direction.rawValue)."]
        let merged = transition.merged.map { String($0.value) }
        if !merged.isEmpty {
            sentences.append("Made \(list(merged)).")
        }
        sentences.append("New \(describe(transition.spawned)).")
        return sentences.joined(separator: " ")
    }

    /// For example "Can't move left."
    static func blockedText(for direction: Direction) -> String {
        "Can't move \(direction.rawValue)."
    }

    /// For example "2 in row 4, column 2".
    private static func describe(_ tile: Tile) -> String {
        "\(tile.value) in row \(tile.position.row + 1), column \(tile.position.column + 1)"
    }

    /// The items joined as an English list: "a", "a and b", "a, b and c".
    /// The sentences are English (the app isn't localized yet), so the list
    /// is joined in English too, not in the device's language.
    private static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        return items.count == 1 ? last : items.dropLast().joined(separator: ", ") + " and " + last
    }
}
