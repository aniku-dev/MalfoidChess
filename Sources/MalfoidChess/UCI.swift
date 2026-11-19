@_silgen_name("fflush")
private func flushCOutput(_ stream: UnsafeMutableRawPointer?) -> Int32

private func sendProtocolLine(_ line: String) {
    print(line)
    // Cute Chess reads through a pipe, where stdout may stay buffered without an explicit flush.
    _ = flushCOutput(nil)
}

final class UCIEngine {
    private struct TrackedMove {
        let move: Move
        let before: Board
        let after: Board
    }

    private var board = Board()
    private var moveHistory: [String] = []
    private var canUseOpeningBook = true
    private var commentaryEnabled: Bool
    private var personalityConfiguration = PersonalityConfiguration()
    private let composureSystem: ComposureSystem
    private var personalityGameStarted = false
    private var trackedRootFEN: String?
    private var trackedMoveHistory: [String] = []
    private var trackedBoard: Board?
    private var pendingTrackedMoves: [TrackedMove] = []
    private var engineColor: Color?

    init(commentaryEnabled: Bool, personalitySeed: UInt64? = nil) {
        self.commentaryEnabled = commentaryEnabled
        composureSystem = ComposureSystem(seed: personalitySeed)
    }

    func run() {
        while let line = readLine() {
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let command = tokens.first else { continue }
            switch command {
            case "uci":
                sendProtocolLine("id name MalfoidChess")
                sendProtocolLine("id author MalfoidChess contributors")
                sendProtocolLine("option name Personality type check default true")
                sendProtocolLine("option name Commentary type check default false")
                sendProtocolLine("option name Composed Probability type spin default 40 min 0 max 100")
                sendProtocolLine("option name Irritated Probability type spin default 30 min 0 max 100")
                sendProtocolLine("option name Tilted Probability type spin default 20 min 0 max 100")
                sendProtocolLine("option name Meltdown Probability type spin default 10 min 0 max 100")
                sendProtocolLine("option name Irritated Chance type spin default 8 min 0 max 100")
                sendProtocolLine("option name Tilted Chance type spin default 14 min 0 max 100")
                sendProtocolLine("option name Meltdown Chance type spin default 22 min 0 max 100")
                sendProtocolLine("option name Irritated Deviation cp type spin default 80 min 0 max 400")
                sendProtocolLine("option name Tilted Deviation cp type spin default 170 min 0 max 400")
                sendProtocolLine("option name Meltdown Deviation cp type spin default 260 min 0 max 400")
                sendProtocolLine("option name Maximum Deviation cp type spin default 400 min 0 max 600")
                sendProtocolLine("uciok")
            case "isready":
                sendProtocolLine("readyok")
            case "setoption":
                setOption(from: tokens)
            case "ucinewgame":
                board = Board()
                moveHistory = []
                canUseOpeningBook = true
                beginPersonalityGame()
            case "position":
                setPosition(tokens)
            case "go":
                search(tokens)
            case "stop":
                // Searches are bounded by depth or movetime and return bestmove themselves.
                break
            case "quit":
                return
            default:
                // Ignore unknown GUI extensions.
                continue
            }
        }
    }

    private func setOption(from tokens: [String]) {
        guard let nameIndex = tokens.firstIndex(of: "name"),
              let valueIndex = tokens.firstIndex(of: "value"),
              nameIndex + 1 < valueIndex,
              valueIndex + 1 < tokens.count else { return }
        let name = tokens[(nameIndex + 1)..<valueIndex].joined(separator: " ").lowercased()
        let value = tokens[(valueIndex + 1)...].joined(separator: " ").lowercased()

        if name == "commentary" {
            commentaryEnabled = value == "true"
            return
        }
        if name == "personality" {
            personalityConfiguration.enabled = value == "true"
            if personalityGameStarted {
                beginPersonalityGame()
            }
            return
        }
        guard let number = Int(value) else { return }
        let bounded = min(600, max(0, number))
        switch name {
        case "composed probability": personalityConfiguration.probabilities.composed = min(100, bounded)
        case "irritated probability": personalityConfiguration.probabilities.irritated = min(100, bounded)
        case "tilted probability": personalityConfiguration.probabilities.tilted = min(100, bounded)
        case "meltdown probability": personalityConfiguration.probabilities.meltdownProne = min(100, bounded)
        case "irritated chance": personalityConfiguration.irritatedChancePercent = min(100, bounded)
        case "tilted chance": personalityConfiguration.tiltedChancePercent = min(100, bounded)
        case "meltdown chance": personalityConfiguration.meltdownChancePercent = min(100, bounded)
        case "irritated deviation cp": personalityConfiguration.irritatedDeviationCp = min(400, bounded)
        case "tilted deviation cp": personalityConfiguration.tiltedDeviationCp = min(400, bounded)
        case "meltdown deviation cp": personalityConfiguration.meltdownDeviationCp = min(400, bounded)
        case "maximum deviation cp": personalityConfiguration.maximumDeviationCp = bounded
        default: break
        }
    }

    private func setPosition(_ tokens: [String]) {
        guard tokens.count >= 2 else { return }
        var candidate: Board
        var rootFEN: String
        var historyStart: Int?
        var usesStartPosition = false

        if tokens[1] == "startpos" {
            candidate = Board()
            rootFEN = Board.startingFEN
            usesStartPosition = true
            if tokens.count > 2, tokens[2] == "moves" { historyStart = 3 }
        } else if tokens[1] == "fen" {
            let fenStart = 2
            let moveMarker = tokens[fenStart...].firstIndex(of: "moves")
            let fenEnd = moveMarker ?? tokens.endIndex
            let fen = tokens[fenStart..<fenEnd].joined(separator: " ")
            guard let parsed = try? Board(fen: fen) else { return }
            candidate = parsed
            rootFEN = parsed.fen
            if let moveMarker { historyStart = moveMarker + 1 }
        } else {
            return
        }

        let rootBoard = candidate
        var candidateHistory: [String] = []
        if let historyStart {
            for moveText in tokens[historyStart...] {
                guard let move = candidate.legalMoves().first(where: { $0.uci == moveText.lowercased() }) else {
                    return
                }
                candidate.make(move)
                candidateHistory.append(move.uci)
            }
        }

        board = candidate
        moveHistory = candidateHistory
        canUseOpeningBook = usesStartPosition
        observePosition(rootFEN: rootFEN, rootBoard: rootBoard, history: candidateHistory)
    }

    private func observePosition(rootFEN: String, rootBoard: Board, history: [String]) {
        if !personalityGameStarted { beginPersonalityGame() }

        if trackedRootFEN != rootFEN {
            // Some GUIs send a fresh FEN each turn instead of the game's original position.
            // Rebase tracking in that case without treating every FEN as a new game.
            let returnedToStart = rootFEN == Board.startingFEN && trackedRootFEN != nil
            if returnedToStart { beginPersonalityGame() }
            trackedRootFEN = rootFEN
            trackedMoveHistory = []
            trackedBoard = rootBoard
            pendingTrackedMoves = []
        } else if !history.starts(with: trackedMoveHistory) {
            // A rewind or new branch is a fresh game-like personality session.
            beginPersonalityGame()
            trackedRootFEN = rootFEN
            trackedMoveHistory = []
            trackedBoard = rootBoard
            pendingTrackedMoves = []
        }

        guard var current = trackedBoard else { return }
        for moveText in history.dropFirst(trackedMoveHistory.count) {
            guard let move = current.legalMoves().first(where: { $0.uci == moveText }) else { return }
            let before = current
            current.make(move)
            let observed = TrackedMove(move: move, before: before, after: current)
            trackedMoveHistory.append(moveText)
            if let engineColor {
                observeComposure(observed, engineColor: engineColor)
            } else {
                pendingTrackedMoves.append(observed)
            }
        }
        trackedBoard = current
    }

    private func beginPersonalityGame() {
        composureSystem.startNewGame(configuration: personalityConfiguration)
        personalityGameStarted = true
        engineColor = nil
        trackedRootFEN = nil
        trackedMoveHistory = []
        trackedBoard = nil
        pendingTrackedMoves = []
    }

    private func preparePersonalityForSearch() {
        if !personalityGameStarted { beginPersonalityGame() }
        if engineColor == nil {
            engineColor = board.sideToMove
            for move in pendingTrackedMoves {
                observeComposure(move, engineColor: board.sideToMove)
            }
            pendingTrackedMoves = []
        }
    }

    private func observeComposure(_ observed: TrackedMove, engineColor: Color) {
        let mover = observed.before.piece(at: observed.move.from)?.color ?? observed.before.sideToMove
        let materialBefore = materialScore(observed.before, for: mover)
        let materialAfter = materialScore(observed.after, for: mover)
        let hangingBefore = hangingMaterial(observed.before, for: mover)
        let hangingAfter = hangingMaterial(observed.after, for: mover)
        let attackedSquares = valuablePiecesAttacked(observed.after, by: engineColor)
        let facts = ObservedMoveFacts(
            move: observed.move,
            mover: mover,
            materialDeltaForMoverCp: materialAfter - materialBefore,
            wasInCheck: observed.before.isInCheck(mover),
            gaveCheck: observed.after.isInCheck(mover.opposite),
            hangingMaterialBeforeCp: hangingBefore,
            hangingMaterialAfterCp: hangingAfter,
            malfoidAttackedValuableSquares: attackedSquares
        )
        composureSystem.observe(facts, engineColor: engineColor)
    }

    private func materialScore(_ position: Board, for color: Color) -> Int {
        (0..<64).reduce(0) { total, square in
            guard let piece = position.piece(at: square), piece.type != .king else { return total }
            return total + (piece.color == color ? piece.type.materialValue : -piece.type.materialValue)
        }
    }

    private func hangingMaterial(_ position: Board, for color: Color) -> Int {
        (0..<64).reduce(0) { total, square in
            guard let piece = position.piece(at: square), piece.color == color,
                  piece.type != .king, piece.type.materialValue >= PieceType.knight.materialValue,
                  position.isSquareAttacked(square, by: color.opposite),
                  !position.isSquareAttacked(square, by: color) else { return total }
            return total + piece.type.materialValue
        }
    }

    private func valuablePiecesAttacked(_ position: Board, by color: Color) -> Set<Int> {
        Set((0..<64).filter { square in
            guard let piece = position.piece(at: square), piece.color != color,
                  piece.type != .king, piece.type.materialValue >= PieceType.knight.materialValue else { return false }
            return position.isSquareAttacked(square, by: color)
        })
    }

    private func search(_ tokens: [String]) {
        preparePersonalityForSearch()
        if canUseOpeningBook,
           let bookMove = OpeningBook.move(for: moveHistory, on: board) {
            showCommentary(
                for: bookMove, score: 0, on: board,
                profile: composureSystem.profile ?? .composed,
                composure: composureSystem.composure,
                usedPersonalityDeviation: false,
                usedMateSafeguard: false
            )
            sendProtocolLine("bestmove \(bookMove.uci)")
            return
        }

        let explicitDepth = integer(after: "depth", in: tokens)
        let moveTime = integer(after: "movetime", in: tokens)
        let infinite = tokens.contains("infinite")
        let timeLimit = infinite ? nil : (moveTime ?? clockBudget(in: tokens))
        let defaultDepth = timeLimit == nil ? 4 : 64
        let maximumDepth = min(64, max(1, explicitDepth ?? (infinite ? 4 : defaultDepth)))
        let result = Searcher().search(
            board: board,
            maximumDepth: maximumDepth,
            timeLimitMilliseconds: timeLimit,
            personality: personalityConfiguration.enabled ? composureSystem : nil,
            personalityConfiguration: personalityConfiguration
        )

        if result.depth > 0 {
            let principalVariation = result.bestMove?.uci ?? "0000"
            sendProtocolLine(
                "info depth \(result.depth) score \(uciScore(result.score)) nodes \(result.nodes) pv \(principalVariation)"
            )
        }
        guard let bestMove = result.bestMove else {
            sendProtocolLine("bestmove 0000")
            return
        }
        showCommentary(
            for: bestMove,
            score: result.score,
            on: board,
            profile: result.personalityProfile ?? .composed,
            composure: result.composure,
            usedPersonalityDeviation: result.usedPersonalityDeviation,
            usedMateSafeguard: result.usedMateSafeguard
        )
        sendProtocolLine("bestmove \(bestMove.uci)")
    }

    private func showCommentary(
        for move: Move,
        score: Int,
        on position: Board,
        profile: PersonalityProfile,
        composure: Int,
        usedPersonalityDeviation: Bool,
        usedMateSafeguard: Bool
    ) {
        guard commentaryEnabled else { return }
        let dialogue = Personality.line(
            after: move,
            on: position,
            score: score,
            profile: profile,
            composure: composure,
            usedPersonalityDeviation: usedPersonalityDeviation,
            usedMateSafeguard: usedMateSafeguard
        )
        // UCI's info string form is protocol-safe; the companion can also read this mood tag.
        sendProtocolLine("info string Malfoid profile=\(profile.rawValue) composure=\(composure) | \(dialogue)")
    }

    private func integer(after key: String, in tokens: [String]) -> Int? {
        guard let index = tokens.firstIndex(of: key), tokens.indices.contains(index + 1) else { return nil }
        return Int(tokens[index + 1])
    }

    private func clockBudget(in tokens: [String]) -> Int? {
        let timeKey = board.sideToMove == .white ? "wtime" : "btime"
        let incrementKey = board.sideToMove == .white ? "winc" : "binc"
        guard let remaining = integer(after: timeKey, in: tokens) else { return nil }
        let increment = integer(after: incrementKey, in: tokens) ?? 0
        let suggested = remaining / 30 + increment * 3 / 4
        return max(1, min(remaining, min(5_000, suggested)))
    }

    private func uciScore(_ score: Int) -> String {
        let mateThreshold = 30_000 - 1_000
        if score >= mateThreshold {
            return "mate \((30_000 - score + 1) / 2)"
        }
        if score <= -mateThreshold {
            return "mate \(-((30_000 + score + 1) / 2))"
        }
        return "cp \(score)"
    }
}
