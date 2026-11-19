

public enum Color: Equatable, Sendable {
    case white
    case black

    public var opposite: Color { self == .white ? .black : .white }
    public var pawnDirection: Int { self == .white ? 1 : -1 }
    public var homeRank: Int { self == .white ? 0 : 7 }
    public var pawnStartRank: Int { self == .white ? 1 : 6 }
    public var promotionRank: Int { self == .white ? 7 : 0 }
}

public enum PieceType: Equatable, Hashable, Sendable, CaseIterable {
    case pawn, knight, bishop, rook, queen, king

    // Values are in centipawns; material is intentionally the evaluation's main signal.
    public var materialValue: Int {
        switch self {
        case .pawn: 100
        case .knight: 320
        case .bishop: 330
        case .rook: 500
        case .queen: 900
        case .king: 20_000
        }
    }

    public var uciLetter: Character {
        switch self {
        case .knight: "n"
        case .bishop: "b"
        case .rook: "r"
        case .queen: "q"
        case .pawn: "p"
        case .king: "k"
        }
    }

    public init?(fenLetter: Character) {
        switch fenLetter.lowercased() {
        case "p": self = .pawn
        case "n": self = .knight
        case "b": self = .bishop
        case "r": self = .rook
        case "q": self = .queen
        case "k": self = .king
        default: return nil
        }
    }
}

public struct Piece: Equatable, Sendable {
    public let type: PieceType
    public let color: Color

    public var fenLetter: Character {
        let letter = type.uciLetter
        return color == .white ? Character(String(letter).uppercased()) : letter
    }

    public init(type: PieceType, color: Color) {
        self.type = type
        self.color = color
    }

    public init?(fenLetter: Character) {
        guard let type = PieceType(fenLetter: fenLetter) else { return nil }
        self.type = type
        self.color = fenLetter.isUppercase ? .white : .black
    }
}

public struct Square: Sendable, Hashable {
    public let file: Int
    public let rank: Int

    public var index: Int { rank * 8 + file }
    public var uci: String {
        let fileLetter = Character(UnicodeScalar(file + 97)!)
        return "\(fileLetter)\(rank + 1)"
    }

    public init(file: Int, rank: Int) {
        self.file = file
        self.rank = rank
    }

    public init?(index: Int) {
        guard (0..<64).contains(index) else { return nil }
        self.init(file: index % 8, rank: index / 8)
    }

    public init?(uci: String) {
        let characters = Array(uci.lowercased())
        guard characters.count == 2,
              let scalar = characters[0].unicodeScalars.first,
              let rank = characters[1].wholeNumberValue,
              (97...104).contains(Int(scalar.value)),
              (1...8).contains(rank) else { return nil }
        self.init(file: Int(scalar.value) - 97, rank: rank - 1)
    }
}

public struct Move: Equatable, Sendable {
    public let from: Int
    public let to: Int
    public let promotion: PieceType?

    public var uci: String {
        let start = Square(index: from)!.uci
        let end = Square(index: to)!.uci
        return start + end + (promotion.map { String($0.uciLetter) } ?? "")
    }

    public init(from: Int, to: Int, promotion: PieceType? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }
}






