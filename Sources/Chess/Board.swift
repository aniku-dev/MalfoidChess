

public struct Board: Sendable {
    private(set) var squares: [Piece?]
    public private(set) var sideToMove: Color
    private(set) var castlingRights: Set<Character>
    public private(set) var enPassantSquare: Int?
    private(set) var halfmoveClock: Int
    private(set) var fullmoveNumber: Int

    public static let startingFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    public init() {
        try! self.init(fen: Self.startingFEN)
    }

    public init(fen: String) throws {
        let fields = fen.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count >= 4 else { throw BoardError.invalidFEN }

        var board = Array<Piece?>(repeating: nil, count: 64)
        let ranks = fields[0].split(separator: "/")
        guard ranks.count == 8 else { throw BoardError.invalidFEN }
        for (fenRank, row) in ranks.enumerated() {
            var file = 0
            let rank = 7 - fenRank
            for character in row {
                if let emptyCount = character.wholeNumberValue {
                    guard (1...8).contains(emptyCount) else { throw BoardError.invalidFEN }
                    file += emptyCount
                } else {
                    guard file < 8, let piece = Piece(fenLetter: character) else {
                        throw BoardError.invalidFEN
                    }
                    board[rank * 8 + file] = piece
                    file += 1
                }
            }
            guard file == 8 else { throw BoardError.invalidFEN }
        }

        switch fields[1] {
        case "w": sideToMove = .white
        case "b": sideToMove = .black
        default: throw BoardError.invalidFEN
        }
        squares = board
        castlingRights = fields[2] == "-" ? [] : Set(fields[2])
        if fields[3] == "-" {
            enPassantSquare = nil
        } else if let square = Square(uci: fields[3]) {
            enPassantSquare = square.index
        } else {
            throw BoardError.invalidFEN
        }
        halfmoveClock = fields.count > 4 ? (Int(fields[4]) ?? 0) : 0
        fullmoveNumber = fields.count > 5 ? (Int(fields[5]) ?? 1) : 1
    }

    public func piece(at square: Int) -> Piece? { squares[square] }

    public var fen: String {
        var placement = ""
        for rank in stride(from: 7, through: 0, by: -1) {
            var emptyCount = 0
            for file in 0..<8 {
                if let piece = squares[rank * 8 + file] {
                    if emptyCount > 0 {
                        placement += String(emptyCount)
                        emptyCount = 0
                    }
                    placement.append(piece.fenLetter)
                } else {
                    emptyCount += 1
                }
            }
            if emptyCount > 0 { placement += String(emptyCount) }
            if rank > 0 { placement += "/" }
        }
        let activeColor = sideToMove == .white ? "w" : "b"
        let rights = "KQkq".filter { castlingRights.contains($0) }
        let castling = rights.isEmpty ? "-" : rights
        let enPassant = enPassantSquare.flatMap { Square(index: $0)?.uci } ?? "-"
        return "\(placement) \(activeColor) \(castling) \(enPassant) \(halfmoveClock) \(fullmoveNumber)"
    }

    public mutating func make(_ move: Move) {
        guard let movingPiece = squares[move.from] else { return }
        let movingColor = movingPiece.color
        let movingType = movingPiece.type
        let destinationPiece = squares[move.to]
        var isCapture = destinationPiece != nil

        // En passant captures the pawn behind the empty destination square.
        if movingType == .pawn, move.to == enPassantSquare, destinationPiece == nil {
            let capturedSquare = move.to - movingColor.pawnDirection * 8
            squares[capturedSquare] = nil
            isCapture = true
        }

        squares[move.from] = nil
        if movingType == .king, abs(move.to - move.from) == 2 {
            let rankOffset = movingColor.homeRank * 8
            if move.to > move.from {
                squares[rankOffset + 5] = squares[rankOffset + 7]
                squares[rankOffset + 7] = nil
            } else {
                squares[rankOffset + 3] = squares[rankOffset]
                squares[rankOffset] = nil
            }
        }
        squares[move.to] = Piece(type: move.promotion ?? movingType, color: movingColor)

        if movingType == .king { removeCastlingRights(for: movingColor) }
        updateRookRights(square: move.from)
        if destinationPiece != nil { updateRookRights(square: move.to) }

        enPassantSquare = nil
        if movingType == .pawn, abs(move.to - move.from) == 16 {
            enPassantSquare = (move.from + move.to) / 2
        }
        halfmoveClock = movingType == .pawn || isCapture ? 0 : halfmoveClock + 1
        if movingColor == .black { fullmoveNumber += 1 }
        sideToMove = movingColor.opposite
    }

    public func isCapture(_ move: Move) -> Bool {
        squares[move.to] != nil || (squares[move.from]?.type == .pawn && move.to == enPassantSquare)
    }

    public func isInCheck(_ color: Color) -> Bool {
        guard let kingSquare = squares.firstIndex(where: { $0?.type == .king && $0?.color == color }) else {
            return true
        }
        return isSquareAttacked(kingSquare, by: color.opposite)
    }

    public func isSquareAttacked(_ target: Int, by attacker: Color) -> Bool {
        guard let targetSquare = Square(index: target) else { return false }
        for source in 0..<64 {
            guard let piece = squares[source], piece.color == attacker,
                  let sourceSquare = Square(index: source) else { continue }
            let fileDelta = targetSquare.file - sourceSquare.file
            let rankDelta = targetSquare.rank - sourceSquare.rank
            switch piece.type {
            case .pawn:
                if abs(fileDelta) == 1 && rankDelta == attacker.pawnDirection { return true }
            case .knight:
                if (abs(fileDelta) == 1 && abs(rankDelta) == 2) || (abs(fileDelta) == 2 && abs(rankDelta) == 1) {
                    return true
                }
            case .king:
                if max(abs(fileDelta), abs(rankDelta)) == 1 { return true }
            case .bishop, .rook, .queen:
                let diagonal = abs(fileDelta) == abs(rankDelta) && fileDelta != 0
                let straight = (fileDelta == 0) != (rankDelta == 0)
                let canSlide = (piece.type == .queen && (diagonal || straight)) || (piece.type == .bishop && diagonal) || (piece.type == .rook && straight)
                guard canSlide else { continue }
                let fileStep = fileDelta == 0 ? 0 : (fileDelta > 0 ? 1 : -1)
                let rankStep = rankDelta == 0 ? 0 : (rankDelta > 0 ? 1 : -1)
                var file = sourceSquare.file + fileStep
                var rank = sourceSquare.rank + rankStep
                var blocked = false
                while file != targetSquare.file || rank != targetSquare.rank {
                    if squares[rank * 8 + file] != nil { blocked = true; break }
                    file += fileStep
                    rank += rankStep
                }
                if !blocked { return true }
            }
        }
        return false
    }

    public func legalMoves() -> [Move] {
        let movingColor = sideToMove
        return pseudoLegalMoves().filter { move in
            var next = self
            next.make(move)
            return !next.isInCheck(movingColor)
        }
    }

    private func pseudoLegalMoves() -> [Move] {
        var moves: [Move] = []
        for from in 0..<64 {
            guard let piece = squares[from], piece.color == sideToMove,
                  let square = Square(index: from) else { continue }
            switch piece.type {
            case .pawn: addPawnMoves(from: from, square: square, color: piece.color, to: &moves)
            case .knight:
                addLeaperMoves(from: from, square: square, offsets: [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)], to: &moves)
            case .bishop: addSlidingMoves(from: from, square: square, directions: [(1, 1), (1, -1), (-1, 1), (-1, -1)], to: &moves)
            case .rook: addSlidingMoves(from: from, square: square, directions: [(1, 0), (-1, 0), (0, 1), (0, -1)], to: &moves)
            case .queen: addSlidingMoves(from: from, square: square, directions: [(1, 1), (1, -1), (-1, 1), (-1, -1), (1, 0), (-1, 0), (0, 1), (0, -1)], to: &moves)
            case .king:
                addLeaperMoves(from: from, square: square, offsets: [(1, 1), (1, 0), (1, -1), (0, 1), (0, -1), (-1, 1), (-1, 0), (-1, -1)], to: &moves)
                addCastlingMoves(from: from, color: piece.color, to: &moves)
            }
        }
        return moves
    }

    private func addPawnMoves(from: Int, square: Square, color: Color, to moves: inout [Move]) {
        let nextRank = square.rank + color.pawnDirection
        guard (0..<8).contains(nextRank) else { return }
        let forward = nextRank * 8 + square.file
        if squares[forward] == nil {
            addPawnMove(from: from, to: forward, promotionRank: color.promotionRank, moves: &moves)
            if square.rank == color.pawnStartRank {
                let doubleForward = (square.rank + 2 * color.pawnDirection) * 8 + square.file
                if squares[doubleForward] == nil { moves.append(Move(from: from, to: doubleForward)) }
            }
        }
        for fileDelta in [-1, 1] {
            let file = square.file + fileDelta
            guard (0..<8).contains(file) else { continue }
            let target = nextRank * 8 + file
            if let occupant = squares[target], occupant.color != color, occupant.type != .king {
                addPawnMove(from: from, to: target, promotionRank: color.promotionRank, moves: &moves)
            } else if target == enPassantSquare {
                moves.append(Move(from: from, to: target))
            }
        }
    }

    private func addPawnMove(from: Int, to: Int, promotionRank: Int, moves: inout [Move]) {
        guard to / 8 == promotionRank else {
            moves.append(Move(from: from, to: to))
            return
        }
        for type in [PieceType.queen, .rook, .bishop, .knight] {
            moves.append(Move(from: from, to: to, promotion: type))
        }
    }

    private func addLeaperMoves(from: Int, square: Square, offsets: [(Int, Int)], to moves: inout [Move]) {
        for (fileDelta, rankDelta) in offsets {
            let file = square.file + fileDelta
            let rank = square.rank + rankDelta
            guard (0..<8).contains(file), (0..<8).contains(rank) else { continue }
            let target = rank * 8 + file
            if squares[target]?.color == sideToMove || squares[target]?.type == .king { continue }
            moves.append(Move(from: from, to: target))
        }
    }

    private func addSlidingMoves(from: Int, square: Square, directions: [(Int, Int)], to moves: inout [Move]) {
        for (fileDelta, rankDelta) in directions {
            var file = square.file + fileDelta
            var rank = square.rank + rankDelta
            while (0..<8).contains(file), (0..<8).contains(rank) {
                let target = rank * 8 + file
                if let occupant = squares[target] {
                    if occupant.color != sideToMove, occupant.type != .king { moves.append(Move(from: from, to: target)) }
                    break
                }
                moves.append(Move(from: from, to: target))
                file += fileDelta
                rank += rankDelta
            }
        }
    }

    private func addCastlingMoves(from: Int, color: Color, to moves: inout [Move]) {
        let rankOffset = color.homeRank * 8
        guard from == rankOffset + 4, !isInCheck(color) else { return }
        let kingSide: Character = color == .white ? "K" : "k"
        if castlingRights.contains(kingSide), squares[rankOffset + 5] == nil, squares[rankOffset + 6] == nil,
           squares[rankOffset + 7]?.type == .rook, squares[rankOffset + 7]?.color == color,
           !isSquareAttacked(rankOffset + 5, by: color.opposite), !isSquareAttacked(rankOffset + 6, by: color.opposite) {
            moves.append(Move(from: from, to: rankOffset + 6))
        }
        let queenSide: Character = color == .white ? "Q" : "q"
        if castlingRights.contains(queenSide), squares[rankOffset + 1] == nil, squares[rankOffset + 2] == nil,
           squares[rankOffset + 3] == nil, squares[rankOffset]?.type == .rook, squares[rankOffset]?.color == color,
           !isSquareAttacked(rankOffset + 3, by: color.opposite), !isSquareAttacked(rankOffset + 2, by: color.opposite) {
            moves.append(Move(from: from, to: rankOffset + 2))
        }
    }

    private mutating func removeCastlingRights(for color: Color) {
        if color == .white { castlingRights.remove("K"); castlingRights.remove("Q") }
        else { castlingRights.remove("k"); castlingRights.remove("q") }
    }

    private mutating func updateRookRights(square: Int) {
        switch square {
        case 0: castlingRights.remove("Q")
        case 7: castlingRights.remove("K")
        case 56: castlingRights.remove("q")
        case 63: castlingRights.remove("k")
        default: break
        }
    }
}

enum BoardError: Error {
    case invalidFEN
}





