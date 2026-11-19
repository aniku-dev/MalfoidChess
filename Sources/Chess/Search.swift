struct SearchResult {
    let bestMove: Move?
    let score: Int
    let nodes: Int
    let depth: Int
    let personalityProfile: PersonalityProfile?
    let composure: Int
    let usedPersonalityDeviation: Bool
    let usedMateSafeguard: Bool
}

private struct RootMoveScore {
    let move: Move
    let score: Int
}

private struct RootIteration {
    let move: Move
    let score: Int
    let candidateScores: [RootMoveScore]
}

final class Searcher {
    private let mateScore = 30_000
    private let clock = ContinuousClock()
    private var deadline: ContinuousClock.Instant?
    private var nodes = 0

    func search(
        board: Board,
        maximumDepth: Int,
        timeLimitMilliseconds: Int? = nil,
        personality: ComposureSystem? = nil,
        personalityConfiguration: PersonalityConfiguration = PersonalityConfiguration()
    ) -> SearchResult {
        nodes = 0
        deadline = timeLimitMilliseconds.map {
            clock.now.advanced(by: .milliseconds(Int64(max(0, $0))))
        }

        let rootMoves = board.legalMoves()
        guard let fallbackMove = rootMoves.first else {
            return SearchResult(
                bestMove: nil, score: 0, nodes: 0, depth: 0,
                personalityProfile: personality?.profile, composure: personality?.composure ?? 100,
                usedPersonalityDeviation: false, usedMateSafeguard: false
            )
        }

        var bestMove = fallbackMove
        var bestScore = evaluateForSideToMove(board)
        var completedDepth = 0
        var completedRootScores: [RootMoveScore] = []
        let collectCandidateScores = personalityConfiguration.enabled && personality != nil

        // Keep the last complete iteration so a time limit never leaves us without a legal move.
        for depth in 1...max(1, maximumDepth) {
            guard !timeExpired(),
                  let iteration = searchRoot(board, moves: rootMoves, depth: depth, collectCandidateScores: collectCandidateScores) else { break }
            bestMove = iteration.move
            bestScore = iteration.score
            completedRootScores = iteration.candidateScores
            completedDepth = depth
            if abs(bestScore) >= mateScore - 100 { break }
        }

        var usedPersonalityDeviation = false
        var usedMateSafeguard = false
        if collectCandidateScores, completedDepth > 0, let personality {
            let candidates = completedRootScores.map { makePersonalityCandidate($0, on: board) }
            if let selection = personality.selectMove(from: candidates, configuration: personalityConfiguration) {
                bestMove = selection.candidate.move
                bestScore = selection.candidate.score
                usedPersonalityDeviation = selection.usedPersonalityDeviation
                usedMateSafeguard = selection.usedMateSafeguard
            }
        }

        return SearchResult(
            bestMove: bestMove,
            score: bestScore,
            nodes: nodes,
            depth: completedDepth,
            personalityProfile: personality?.profile,
            composure: personality?.composure ?? 100,
            usedPersonalityDeviation: usedPersonalityDeviation,
            usedMateSafeguard: usedMateSafeguard
        )
    }

    private func timeExpired() -> Bool {
        guard let deadline else { return false }
        return clock.now >= deadline
    }

    private func searchRoot(
        _ board: Board,
        moves: [Move],
        depth: Int,
        collectCandidateScores: Bool
    ) -> RootIteration? {
        var alpha = -mateScore
        let beta = mateScore
        var bestMove = moves[0]
        var bestScore = -mateScore
        var candidateScores: [RootMoveScore] = []
        let orderedMoves = moves.sorted { moveOrderingScore($0, on: board) > moveOrderingScore($1, on: board) }

        for move in orderedMoves {
            if timeExpired() { return nil }
            var child = board
            child.make(move)
            // Full windows give the personality selector comparable root scores. When it is
            // disabled, keep the original alpha-beta root search and its exact move behavior.
            let score: Int
            if collectCandidateScores {
                score = -negamax(child, depth: depth - 1, alpha: -mateScore, beta: mateScore, ply: 1)
                candidateScores.append(RootMoveScore(move: move, score: score))
            } else {
                score = -negamax(child, depth: depth - 1, alpha: -beta, beta: -alpha, ply: 1)
            }
            if timeExpired() { return nil }
            if score > bestScore {
                bestScore = score
                bestMove = move
            }
            alpha = max(alpha, score)
        }
        return RootIteration(move: bestMove, score: bestScore, candidateScores: candidateScores)
    }

    private func makePersonalityCandidate(_ rootScore: RootMoveScore, on board: Board) -> PersonalityMoveCandidate {
        let ownColor = board.sideToMove
        let movingPiece = board.piece(at: rootScore.move.from)
        let capturedValue = board.piece(at: rootScore.move.to)?.type.materialValue ??
            (rootScore.move.to == board.enPassantSquare ? PieceType.pawn.materialValue : 0)
        let hangingBefore = hangingMaterial(on: board, color: ownColor)

        var child = board
        child.make(rootScore.move)
        let givesCheck = child.isInCheck(ownColor.opposite)
        let attackedValuableSquares = valuablePiecesAttacked(on: child, by: ownColor)
        let hangingAfter = hangingMaterial(on: child, color: ownColor)
        let movedPieceIsExposed = child.isSquareAttacked(rootScore.move.to, by: ownColor.opposite) &&
            !child.isSquareAttacked(rootScore.move.to, by: ownColor)
        let createsNewExposure = hangingAfter >= hangingBefore + 200
        let canRiskPiece = movingPiece.map { $0.type != .queen && $0.type != .king && $0.type.materialValue <= PieceType.rook.materialValue } ?? false
        let isRisky = canRiskPiece && capturedValue < (movingPiece?.type.materialValue ?? 0) &&
            (movedPieceIsExposed || createsNewExposure) &&
            (givesCheck || !attackedValuableSquares.isEmpty)

        return PersonalityMoveCandidate(
            move: rootScore.move,
            score: rootScore.score,
            isActive: board.isCapture(rootScore.move) || rootScore.move.promotion != nil ||
                givesCheck || !attackedValuableSquares.isEmpty,
            isRisky: isRisky,
            allowsMateInOne: allowsMateInOne(after: child),
            isStrongDefense: board.isInCheck(ownColor) || hangingAfter + 200 < hangingBefore,
            isCounterattack: givesCheck || !attackedValuableSquares.isEmpty
        )
    }

    private func valuablePiecesAttacked(on board: Board, by color: Color) -> Set<Int> {
        Set((0..<64).filter { square in
            guard let piece = board.piece(at: square), piece.color != color,
                  piece.type != .king, piece.type.materialValue >= PieceType.knight.materialValue else { return false }
            return board.isSquareAttacked(square, by: color)
        })
    }

    private func hangingMaterial(on board: Board, color: Color) -> Int {
        (0..<64).reduce(0) { total, square in
            guard let piece = board.piece(at: square), piece.color == color,
                  piece.type != .king, piece.type.materialValue >= PieceType.knight.materialValue,
                  board.isSquareAttacked(square, by: color.opposite),
                  !board.isSquareAttacked(square, by: color) else { return total }
            return total + piece.type.materialValue
        }
    }

    private func allowsMateInOne(after position: Board) -> Bool {
        let replies = position.legalMoves()
        // If the candidate itself ends the game, it cannot allow the opponent to mate next.
        if replies.isEmpty { return false }
        for reply in replies {
            var next = position
            next.make(reply)
            if next.isInCheck(next.sideToMove) && next.legalMoves().isEmpty { return true }
        }
        return false
    }

    // Negamax scores from the current player's view; each move changes perspective.
    // Alpha-beta bounds skip branches that cannot improve the best result.
    private func negamax(_ board: Board, depth: Int, alpha: Int, beta: Int, ply: Int) -> Int {
        nodes += 1
        if timeExpired() { return evaluateForSideToMove(board) }
        if depth <= 0 { return quiescence(board, alpha: alpha, beta: beta, ply: ply) }

        let moves = board.legalMoves()
        if moves.isEmpty {
            return board.isInCheck(board.sideToMove) ? -mateScore + ply : 0
        }

        var bestScore = -mateScore
        var currentAlpha = alpha
        let orderedMoves = moves.sorted { moveOrderingScore($0, on: board) > moveOrderingScore($1, on: board) }
        for move in orderedMoves {
            if timeExpired() { break }
            var child = board
            child.make(move)
            let score = -negamax(child, depth: depth - 1, alpha: -beta, beta: -currentAlpha, ply: ply + 1)
            bestScore = max(bestScore, score)
            currentAlpha = max(currentAlpha, score)
            if currentAlpha >= beta { break }
        }
        return bestScore
    }

    // At the depth limit, follow captures and check evasions until the position settles.
    private func quiescence(_ board: Board, alpha: Int, beta: Int, ply: Int) -> Int {
        nodes += 1
        let inCheck = board.isInCheck(board.sideToMove)
        let standPat = evaluateForSideToMove(board)
        if ply >= 16 { return standPat }
        var currentAlpha = alpha
        if !inCheck {
            if standPat >= beta { return standPat }
            currentAlpha = max(currentAlpha, standPat)
        }

        let legalMoves = board.legalMoves()
        if legalMoves.isEmpty { return inCheck ? -mateScore + ply : 0 }
        let forcingMoves = inCheck ? legalMoves : legalMoves.filter { board.isCapture($0) || $0.promotion != nil }
        var bestScore = inCheck ? -mateScore : standPat
        for move in forcingMoves {
            if timeExpired() { break }
            var child = board
            child.make(move)
            let score = -quiescence(child, alpha: -beta, beta: -currentAlpha, ply: ply + 1)
            bestScore = max(bestScore, score)
            currentAlpha = max(currentAlpha, score)
            if currentAlpha >= beta { break }
        }
        return bestScore
    }

    // Material remains the main evaluation signal; bonuses only encourage sensible development.
    private func evaluateForSideToMove(_ board: Board) -> Int {
        var whiteScore = 0
        for index in 0..<64 {
            guard let piece = board.piece(at: index), let square = Square(index: index) else { continue }
            let sign = piece.color == .white ? 1 : -1
            let centerDistance = abs(square.file * 2 - 7) + abs(square.rank * 2 - 7)
            let centerBonus = 14 - centerDistance
            var positionalBonus = 0
            switch piece.type {
            case .knight: positionalBonus = centerBonus * 4
            case .bishop: positionalBonus = centerBonus * 2
            case .pawn:
                positionalBonus = (piece.color == .white ? square.rank : 7 - square.rank) * 5
            case .queen, .rook, .king: break
            }
            whiteScore += sign * (piece.type.materialValue + positionalBonus)
        }
        return board.sideToMove == .white ? whiteScore : -whiteScore
    }

    private func moveOrderingScore(_ move: Move, on board: Board) -> Int {
        let movingPiece = board.piece(at: move.from)
        let capturedPiece = board.piece(at: move.to)
        var score = 0
        if let capturedPiece, let movingPiece {
            score += capturedPiece.type.materialValue * 10 - movingPiece.type.materialValue
        } else if movingPiece?.type == .pawn, move.to == board.enPassantSquare {
            score += PieceType.pawn.materialValue * 10 - PieceType.pawn.materialValue
        }
        if let promotion = move.promotion { score += promotion.materialValue }
        return score
    }
}
