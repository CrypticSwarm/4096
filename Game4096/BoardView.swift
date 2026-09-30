import GameCore
import SwiftUI

/// The board: a square grid of empty cells with the tiles of `layout` on top,
/// as large as fits the space offered.
///
/// For accessibility the board is a container identified by
/// ``AccessibilityID/board`` whose value is the board's notation (see
/// `Board.notation`), and each cell is an element labeled with its tile's
/// value or "Empty". The cells, not the tiles, carry the labels, so they are
/// in reading order, include empty cells and always describe the current
/// board.
struct BoardView: View {
    let layout: TileLayout

    var body: some View {
        GeometryReader { proxy in
            let geometry = BoardGeometry(size: layout.board.size, side: min(proxy.size.width, proxy.size.height))
            ZStack {
                RoundedRectangle(cornerRadius: geometry.boardCornerRadius)
                    .fill(Theme.board)
                ForEach(layout.board.positions, id: \.self) { position in
                    cell(at: position, geometry: geometry)
                }
                ForEach(layout.tiles) { tile in
                    TileView(value: tile.value, side: geometry.cellSide, cornerRadius: geometry.cellCornerRadius)
                        .position(geometry.center(row: tile.position.row, column: tile.position.column))
                }
                .accessibilityHidden(true)
            }
            .frame(width: geometry.side, height: geometry.side)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Board")
        .accessibilityValue(layout.board.notation)
        .accessibilityIdentifier(AccessibilityID.board)
    }

    private func cell(at position: GameCore.Position, geometry: BoardGeometry) -> some View {
        RoundedRectangle(cornerRadius: geometry.cellCornerRadius)
            .fill(Theme.emptyCell)
            .frame(width: geometry.cellSide, height: geometry.cellSide)
            .position(geometry.center(row: position.row, column: position.column))
            .accessibilityElement()
            .accessibilityLabel(layout.board[position].map { Text(verbatim: String($0)) } ?? Text("Empty"))
            .accessibilityIdentifier(AccessibilityID.cell(row: position.row, column: position.column))
    }
}

#Preview("4×4") {
    BoardView(layout: TileLayout(board: try! Board(notation: "2,4,8,16;32,64,128,256;512,1024,2048,4096;0,0,8192,0")))
        .padding()
        .background(Theme.background)
}

#Preview("5×5") {
    BoardView(layout: TileLayout(board: try! Board(notation: "2,0,0,0,4;0,0,0,0,0;0,0,131072,0,0;0,0,0,0,0;2,0,0,0,2")))
        .padding()
        .background(Theme.background)
}
