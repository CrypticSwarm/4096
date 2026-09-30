import GameCore

/// What VoiceOver announces after a move, since the tiles' new places
/// otherwise go unspoken.
enum MoveAnnouncement {
    /// For example "Moved left. Made 8 and 16. New 2 in row 4, column 2."
    static func text(for transition: TileTransition) -> String {
        var sentences = ["Moved \(transition.direction.rawValue)."]
        let merged = transition.merged.map { String($0.value) }
        if !merged.isEmpty {
            // The sentences are English (the app isn't localized yet), so
            // the list is joined in English too, not in the device's language.
            let list =
                merged.count == 1
                ? merged[0] : merged.dropLast().joined(separator: ", ") + " and " + merged[merged.count - 1]
            sentences.append("Made \(list).")
        }
        let spawned = transition.spawned
        sentences.append(
            "New \(spawned.value) in row \(spawned.position.row + 1), column \(spawned.position.column + 1).")
        return sentences.joined(separator: " ")
    }

    /// For example "Can't move left."
    static func blockedText(for direction: Direction) -> String {
        "Can't move \(direction.rawValue)."
    }
}
