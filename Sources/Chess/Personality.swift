enum Personality {
    static let demoLine = "You first, POTTAH."

    static func line(
        after move: Move,
        on board: Board,
        score: Int,
        profile: PersonalityProfile,
        composure: Int,
        usedPersonalityDeviation: Bool,
        usedMateSafeguard: Bool
    ) -> String {
        if isCheckmate(after: move, on: board) {
            return profile == .meltdownProne && composure < 30
                ? "MY FATHER WILL HEAR ABOUT THIS! Checkmate."
                : "Checkmate. Do try to keep up."
        }
        if usedPersonalityDeviation {
            switch profile {
            case .composed:
                break
            case .irritated:
                return "I chose the sharper line. Try to keep up, POTTAH."
            case .tilted:
                return "Waiting is tedious. I am making things happen."
            case .meltdownProne:
                return composure < 30
                    ? "I REFUSE TO DISCUSS THAT MOVE. MY FATHER WILL HEAR ABOUT THIS!"
                    : "That was a tactical investment. Obviously."
            }
        }
        if usedMateSafeguard {
            return profile == .irritated
                ? "I saw that mate threat coming. Honestly, POTTAH."
                : "I had the mating threat covered."
        }
        if board.isCapture(move) {
            if board.piece(at: move.to)?.type == .pawn ||
                (board.piece(at: move.from)?.type == .pawn && move.to == board.enPassantSquare) {
                return profile == .composed
                    ? "A free pawn? How generous of you, POTTAH."
                    : "A pawn is still material. I'll take it, POTTAH."
            }
            let name = board.piece(at: move.to).map(pieceName) ?? "piece"
            return profile == .tilted || profile == .meltdownProne
                ? "Finally, something worth taking: that \(name)."
                : "That \(name) is now a family heirloom."
        }
        if score >= 700 {
            switch profile {
            case .composed: return "A tidy position. Try to keep up, POTTAH."
            case .irritated: return "I'm winning. Do try to look surprised."
            case .tilted: return "Good. Now let's finish this."
            case .meltdownProne: return "At least someone here knows what she's doing."
            }
        }
        if score <= -700 {
            switch profile {
            case .composed: return "This is a strategic retreat. Obviously, POTTAH."
            case .irritated: return "I can still turn this around. Watch me."
            case .tilted: return "This position is beneath me. Rematch. NOW."
            case .meltdownProne: return "THIS BOARD IS A DISGRACE. REMATCH. NOW."
            }
        }
        if composure < 35 && profile != .composed {
            return profile == .meltdownProne
                ? "I REFUSE TO DISCUSS THAT MOVE."
                : "I'm perfectly calm. Stop looking at me like that."
        }
        switch profile {
        case .composed: return "You first, POTTAH."
        case .irritated: return "A decent move. Don't get used to it."
        case .tilted: return "Could we hurry this along?"
        case .meltdownProne: return "I had a plan. I will remember it shortly."
        }
    }

    private static func isCheckmate(after move: Move, on board: Board) -> Bool {
        var child = board
        child.make(move)
        return child.isInCheck(child.sideToMove) && child.legalMoves().isEmpty
    }

    private static func pieceName(_ piece: Piece) -> String {
        switch piece.type {
        case .pawn: "pawn"
        case .knight: "knight"
        case .bishop: "bishop"
        case .rook: "rook"
        case .queen: "queen"
        case .king: "king"
        }
    }
}
