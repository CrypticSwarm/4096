import GameCore
import SwiftUI

/// The board: a square grid of empty cells with the tiles of `layout` on top,
/// as large as fits the space offered.
///
/// When `layout` changes by a move (its `lastTransition`), the tiles animate
/// like the original game through the ``TileAnimation`` steps: they slide,
/// then merged tiles pop and the new tile appears. A change while a move
/// animates cuts that animation short, and with Reduce Motion, or after a
/// reset, the tiles are simply replaced. Only the drawing trails `layout`;
/// the accessibility elements always describe it.
///
/// For accessibility the board is a container identified by
/// ``AccessibilityID/board`` whose value is the board's notation (see
/// `Board.notation`), and each cell is an element labeled with its tile's
/// value or "Empty", with its position as extra content and actions to slide
/// the tiles. The cells, not the tiles, carry the labels, so they are in
/// reading order, include empty cells and never lag behind an animation.
/// A slide action that can't move the tiles is announced here; the screen
/// announces changes (see `MoveAnnouncement`).
struct BoardView: View {
    let layout: TileLayout
    /// Called for the slide actions of the accessibility elements; returns
    /// whether the tiles moved.
    let onMove: @MainActor (Direction) -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The tiles drawn, which trail `layout.tiles` while a move animates.
    @State private var shownTiles: [ShownTile]
    @State private var animation: Task<Void, Never>?

    init(layout: TileLayout, onMove: @escaping @MainActor (Direction) -> Bool) {
        self.layout = layout
        self.onMove = onMove
        _shownTiles = State(initialValue: ShownTile.settled(layout.tiles))
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = BoardGeometry(size: layout.board.size, side: min(proxy.size.width, proxy.size.height))
            ZStack {
                RoundedRectangle(cornerRadius: geometry.boardCornerRadius)
                    .fill(Theme.board)
                CellLayout(geometry: geometry) {
                    ForEach(layout.board.positions, id: \.self) { position in
                        cell(at: position, geometry: geometry)
                            .layoutValue(key: CellPosition.self, value: position)
                    }
                }
                // Glows below all tiles, so they only tint the board.
                CellLayout(geometry: geometry) {
                    ForEach(shownTiles) { shown in
                        TileGlow(
                            value: shown.tile.value, side: geometry.cellSide, cornerRadius: geometry.cellCornerRadius
                        )
                        .tileEntrance(shown)
                    }
                }
                .accessibilityHidden(true)
                // Merged-away tiles below the tiles that replace them.
                CellLayout(geometry: geometry) {
                    ForEach(shownTiles) { shown in
                        TileView(
                            value: shown.tile.value, side: geometry.cellSide, cornerRadius: geometry.cellCornerRadius
                        )
                        .tileEntrance(shown)
                        .zIndex(shown.isMergedAway ? 0 : 1)
                    }
                }
                .accessibilityHidden(true)
            }
            .frame(width: geometry.side, height: geometry.side)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: layout) { _, target in
            animation?.cancel()
            animation = nil
            let steps = TileAnimation.steps(to: target, reduceMotion: reduceMotion)
            if steps.count == 1 {
                show(steps[0])
            } else {
                animation = Task { await run(steps) }
            }
        }
        .onDisappear {
            // Don't leave a half-finished animation to reappear with.
            animation?.cancel()
            animation = nil
            shownTiles = ShownTile.settled(layout.tiles)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Board")
        .accessibilityValue(layout.board.notation)
        .accessibilityIdentifier(AccessibilityID.board)
    }

    private func cell(at position: GameCore.Position, geometry: BoardGeometry) -> some View {
        RoundedRectangle(cornerRadius: geometry.cellCornerRadius)
            .fill(Theme.emptyCell)
            .frame(width: geometry.cellSide, height: geometry.cellSide)
            .accessibilityElement()
            .accessibilityLabel(layout.board[position].map { Text(verbatim: String($0)) } ?? Text("Empty"))
            .accessibilityCustomContent(
                Text("Position"), Text("Row \(position.row + 1), column \(position.column + 1)")
            )
            .accessibilityIdentifier(AccessibilityID.cell(row: position.row, column: position.column))
            .accessibilityAction(named: "Slide up") { slide(.up) }
            .accessibilityAction(named: "Slide down") { slide(.down) }
            .accessibilityAction(named: "Slide left") { slide(.left) }
            .accessibilityAction(named: "Slide right") { slide(.right) }
    }

    /// Plays a move for a VoiceOver action, announcing when the tiles can't
    /// move.
    private func slide(_ direction: Direction) {
        if !onMove(direction) {
            AccessibilityNotification.Announcement(MoveAnnouncement.blockedText(for: direction)).post()
        }
    }

    private func run(_ steps: [TileAnimation.Step]) async {
        for step in steps {
            guard !Task.isCancelled else { return }
            show(step)
            if step.pause > 0 {
                try? await Task.sleep(for: .seconds(step.pause))
            }
        }
    }

    private func show(_ step: TileAnimation.Step) {
        switch step.motion {
        case .none:
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { shownTiles = step.tiles }
        case .slide:
            withAnimation(Theme.Motion.slide) { shownTiles = step.tiles }
        case .pop:
            withAnimation(Theme.Motion.pop) { shownTiles = step.tiles }
        }
    }
}

/// Places each subview, sized as a cell, in the cell given by its
/// ``CellPosition``. Each view's bounds are its own cell, so a tile scales
/// around its center and its frame is the cell's for accessibility; a change
/// of position animates with the transaction.
private struct CellLayout: Layout {
    let geometry: BoardGeometry

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: geometry.side, height: geometry.side)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell = ProposedViewSize(width: geometry.cellSide, height: geometry.cellSide)
        for subview in subviews {
            let position = subview[CellPosition.self]
            let center = geometry.center(row: position.row, column: position.column)
            subview.place(
                at: CGPoint(x: bounds.minX + center.x, y: bounds.minY + center.y), anchor: .center, proposal: cell)
        }
    }
}

/// The cell a subview of ``CellLayout`` goes in.
private struct CellPosition: LayoutValueKey {
    static let defaultValue = GameCore.Position(row: 0, column: 0)
}

extension View {
    /// Places a tile's view in its cell, appearing with its entrance.
    fileprivate func tileEntrance(_ shown: ShownTile) -> some View {
        layoutValue(key: CellPosition.self, value: shown.tile.position)
            .transition(.asymmetric(insertion: shown.entrance.transition, removal: .identity))
    }
}

extension ShownTile.Entrance {
    /// How a tile with this entrance is inserted.
    fileprivate var transition: AnyTransition {
        switch self {
        case .none: .identity
        case .pop: AnyTransition.scale.animation(Theme.Motion.pop)
        case .appear: AnyTransition.scale.combined(with: .opacity).animation(Theme.Motion.appear)
        }
    }
}

#Preview("4×4") {
    BoardView(
        layout: TileLayout(board: try! Board(notation: "2,4,8,16;32,64,128,256;512,1024,2048,4096;0,0,8192,0")),
        onMove: { _ in false }
    )
    .padding()
    .background(Theme.background)
}

#Preview("5×5") {
    BoardView(
        layout: TileLayout(board: try! Board(notation: "2,0,0,0,4;0,0,0,0,0;0,0,131072,0,0;0,0,0,0,0;2,0,0,0,2")),
        onMove: { _ in false }
    )
    .padding()
    .background(Theme.background)
}
