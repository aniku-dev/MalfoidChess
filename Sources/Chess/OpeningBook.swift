public enum OpeningBook {
    // Short, quiet lines: develop safely and let the opponent create weaknesses.
    private static let lines: [[String]] = [
        // Open Game: Quiet Italian-style development
        ["e2e4", "e7e5", "g1f3", "b8c6", "d2d3", "g8f6", "c2c3", "d7d6"],

        // The Double Quiet Setup
        ["d2d3", "d7d6", "c2c3", "e7e5", "g1f3", "g8f6", "e2e4", "b8d7"],

        // The Caro-Kann Defense
        ["e2e4", "c7c6", "d2d3", "d7d5", "g1f3", "g8f6", "b1d2", "c8g4"],
    ]

    public static func move(for history: [String], on board: Board) -> Move? {
        let candidates = lines.compactMap { line -> String? in
            guard history.count < line.count,
                line.prefix(history.count).elementsEqual(history) else {
                return nil
            }

            return line[history.count]
        }

        guard let nextMove = candidates.randomElement() else {
            return nil
        }

        return board.legalMoves().first { $0.uci == nextMove }
    }
}


