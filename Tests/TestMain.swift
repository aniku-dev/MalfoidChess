func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("PASS: \(message)")
    } else {
        fatalError("FAIL: \(message)")
    }
}

func perft(_ board: Board, depth: Int) -> Int {
    if depth == 0 { return 1 }
    return board.legalMoves().reduce(0) { total, move in
        var child = board
        child.make(move)
        return total + perft(child, depth: depth - 1)
    }
}

func testBoardRules() {
    let start = Board()
    expect(start.legalMoves().count == 20, "start position has 20 legal moves")
    expect(perft(start, depth: 2) == 400, "start position perft depth 2")
    expect(perft(start, depth: 3) == 8_902, "start position perft depth 3")

    let fen = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 7 12"
    expect((try? Board(fen: fen).fen) == fen, "FEN round trip")

    var castleBoard = try! Board(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
    let castle = castleBoard.legalMoves().first { $0.uci == "e1g1" }
    expect(castle != nil, "king-side castling is legal when clear")
    castleBoard.make(castle!)
    expect(castleBoard.piece(at: Square(uci: "g1")!.index)?.type == .king, "castling moves the king")
    expect(castleBoard.piece(at: Square(uci: "f1")!.index)?.type == .rook, "castling moves the rook")
    expect(castleBoard.fen.split(separator: " ")[2] == "kq", "castling removes white rights")

    let attackedCastle = try! Board(fen: "4kr2/8/8/8/8/8/8/R3K2R w KQ - 0 1")
    expect(!attackedCastle.legalMoves().contains { $0.uci == "e1g1" }, "king cannot castle through check")
    expect(attackedCastle.legalMoves().contains { $0.uci == "e1c1" }, "other castle remains legal")

    let pinnedRook = try! Board(fen: "4r2k/8/8/8/8/8/4R3/4K3 w - - 0 1")
    expect(!pinnedRook.legalMoves().contains { $0.uci == "e2d2" }, "pinned rook cannot expose its king")

    var enPassant = try! Board(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
    let enPassantMove = enPassant.legalMoves().first { $0.uci == "e5d6" }
    expect(enPassantMove != nil, "en passant is generated")
    enPassant.make(enPassantMove!)
    expect(enPassant.piece(at: Square(uci: "d5")!.index) == nil, "en passant removes the captured pawn")
    expect(enPassant.piece(at: Square(uci: "d6")!.index)?.type == .pawn, "en passant lands on the target square")

    let promotionBoard = try! Board(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
    let promotions = promotionBoard.legalMoves().filter { $0.from == Square(uci: "a7")!.index }
    expect(Set(promotions.compactMap(\.promotion)) == Set([.queen, .rook, .bishop, .knight]), "all promotion choices are generated")
}

func testOpeningAndSearch() {
    var board = Board()
    let firstMove = OpeningBook.move(for: [], on: board)
    expect(firstMove?.uci == "d2d3", "opening book begins quietly")
    if let firstMove {
        board.make(firstMove)
        expect(OpeningBook.move(for: [firstMove.uci], on: board)?.uci == "d7d6", "quiet black reply is in the book")
    }

    var blackPosition = Board()
    let e4 = blackPosition.legalMoves().first { $0.uci == "e2e4" }
    expect(e4 != nil, "e4 is legal from the initial position")
    if let e4 {
        blackPosition.make(e4)
        expect(OpeningBook.move(for: ["e2e4"], on: blackPosition)?.uci == "e7e5", "book answers e4")
    }

    let matePosition = try! Board(fen: "7k/8/5KQ1/8/8/8/8/8 w - - 0 1")
    let result = Searcher().search(board: matePosition, maximumDepth: 3)
    var child = matePosition
    if let move = result.bestMove { child.make(move) }
    expect(result.bestMove != nil, "search returns a move")
    expect(child.isInCheck(.black) && child.legalMoves().isEmpty, "search finds mate in one")
}

@main
enum TestRunner {
    static func main() {
        testBoardRules()
        testOpeningAndSearch()
        print("All MalfoidChess checks passed.")
    }
}

