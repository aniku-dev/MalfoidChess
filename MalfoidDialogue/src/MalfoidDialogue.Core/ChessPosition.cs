namespace MalfoidDialogue.Core;

/// <summary>A compact board model used only to derive move context from UCI.</summary>
public sealed class ChessPosition
{
    private readonly char[] board;
    private bool whiteToMove;
    private string castlingRights;
    private int enPassantSquare;
    private int fullmoveNumber;

    private ChessPosition(char[] board, bool whiteToMove, string castlingRights, int enPassantSquare, int fullmoveNumber)
    { this.board = board; this.whiteToMove = whiteToMove; this.castlingRights = castlingRights; this.enPassantSquare = enPassantSquare; this.fullmoveNumber = fullmoveNumber; }

    public bool WhiteToMove => whiteToMove;
    public static ChessPosition StartPosition() => FromFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");

    public static ChessPosition FromFen(string fen)
    {
        var fields = fen.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (fields.Length < 4) throw new FormatException("FEN must contain at least four fields.");
        var board = new char[64]; var ranks = fields[0].Split('/');
        if (ranks.Length != 8) throw new FormatException("FEN must contain eight ranks.");
        for (var row = 0; row < 8; row++)
        {
            var file = 0;
            foreach (var symbol in ranks[row])
            {
                if (char.IsDigit(symbol)) file += symbol - '0';
                else { if (file >= 8) throw new FormatException("Invalid FEN rank."); board[(7 - row) * 8 + file++] = symbol; }
            }
            if (file != 8) throw new FormatException("Invalid FEN rank width.");
        }
        return new ChessPosition(board, fields[1] == "w", fields[2], fields[3] == "-" ? -1 : ParseSquare(fields[3]),
            fields.Length > 5 && int.TryParse(fields[5], out var full) ? full : 1);
    }

    public ChessPosition Clone() => new((char[])board.Clone(), whiteToMove, castlingRights, enPassantSquare, fullmoveNumber);

    public MoveFacts ApplyUci(string uci)
    {
        if (uci.Length < 4) throw new FormatException($"Invalid UCI move: {uci}");
        var from = ParseSquare(uci[..2]); var to = ParseSquare(uci[2..4]); var moving = board[from];
        if (moving == '\0' || IsWhite(moving) != whiteToMove) throw new InvalidOperationException($"Unexpected mover in {uci}.");
        var moverWhite = whiteToMove; var captured = board[to]; var capturedSquare = to;
        if (char.ToUpperInvariant(moving) == 'P' && to == enPassantSquare && captured == '\0')
        { capturedSquare = to + (moverWhite ? -8 : 8); captured = board[capturedSquare]; }
        var before = MaterialBalanceWhiteCp();
        board[from] = '\0'; board[capturedSquare] = '\0';
        board[to] = uci.Length > 4 ? (moverWhite ? char.ToUpperInvariant(uci[4]) : char.ToLowerInvariant(uci[4])) : moving;
        if (char.ToUpperInvariant(moving) == 'K' && Math.Abs(to - from) == 2) MoveCastleRook(from, to);
        UpdateCastlingRights(moving, from, to, captured);
        enPassantSquare = char.ToUpperInvariant(moving) == 'P' && Math.Abs(to - from) == 16 ? (from + to) / 2 : -1;
        if (!moverWhite) fullmoveNumber++;
        whiteToMove = !whiteToMove;
        var check = IsKingInCheck(whiteToMove);
        var mate = check && GenerateLegalMoves().Count == 0;
        var after = MaterialBalanceWhiteCp();
        var ply = moverWhite ? fullmoveNumber * 2 - 1 : (fullmoveNumber - 1) * 2;
        return new MoveFacts(uci, ply, moverWhite ? fullmoveNumber : fullmoveNumber - 1, moverWhite,
            PieceName(moving), captured == '\0' ? null : PieceName(captured), check, mate, after, after - before);
    }

    public int MaterialBalanceWhiteCp()
    {
        var balance = 0;
        foreach (var piece in board) if (piece != '\0') balance += (IsWhite(piece) ? 1 : -1) * PieceValue(piece);
        return balance;
    }

    public bool IsInCheck(bool white) => IsKingInCheck(white);

    private List<(int From, int To, char? Promotion)> GenerateLegalMoves()
    {
        var pseudo = new List<(int From, int To, char? Promotion)>();
        for (var from = 0; from < 64; from++)
            if (board[from] != '\0' && IsWhite(board[from]) == whiteToMove) AddPseudoMoves(from, board[from], pseudo);
        var legal = new List<(int From, int To, char? Promotion)>();
        foreach (var move in pseudo)
        {
            var copy = Clone();
            var suffix = move.Promotion is char promotion ? char.ToLowerInvariant(promotion).ToString() : "";
            copy.ApplyWithoutMate(SquareName(move.From) + SquareName(move.To) + suffix);
            if (!copy.IsKingInCheck(whiteToMove)) legal.Add(move);
        }
        return legal;
    }

    private void AddPseudoMoves(int from, char piece, List<(int From, int To, char? Promotion)> moves)
    {
        var white = IsWhite(piece); var kind = char.ToUpperInvariant(piece); var file = from % 8; var rank = from / 8;
        void Add(int to)
        {
            if (to is < 0 or >= 64) return;
            if (board[to] == '\0' || IsWhite(board[to]) != white && char.ToUpperInvariant(board[to]) != 'K') moves.Add((from, to, null));
        }
        if (kind == 'P')
        {
            var direction = white ? 1 : -1; var nextRank = rank + direction;
            if (nextRank is >= 0 and < 8)
            {
                var forward = nextRank * 8 + file;
                if (board[forward] == '\0')
                {
                    AddPawn(from, forward, nextRank, white, moves);
                    var doublePush = (rank + 2 * direction) * 8 + file;
                    if (rank == (white ? 1 : 6) && board[doublePush] == '\0') Add(doublePush);
                }
                foreach (var df in new[] { -1, 1 })
                {
                    var targetFile = file + df; if (targetFile is < 0 or > 7) continue;
                    var target = nextRank * 8 + targetFile;
                    if ((board[target] != '\0' && IsWhite(board[target]) != white && char.ToUpperInvariant(board[target]) != 'K') || target == enPassantSquare)
                        AddPawn(from, target, nextRank, white, moves);
                }
            }
            return;
        }
        if (kind == 'N')
        {
            foreach (var (df, dr) in new[] { (1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2) })
            { var f = file + df; var r = rank + dr; if (f is >= 0 and < 8 && r is >= 0 and < 8) Add(r * 8 + f); }
            return;
        }
        if (kind == 'K')
        {
            for (var df = -1; df <= 1; df++) for (var dr = -1; dr <= 1; dr++)
            { var f = file + df; var r = rank + dr; if ((df != 0 || dr != 0) && f is >= 0 and < 8 && r is >= 0 and < 8) Add(r * 8 + f); }
            AddCastles(from, white, moves); return;
        }
        var directions = kind switch
        {
            'B' => new[] { (1, 1), (1, -1), (-1, 1), (-1, -1) },
            'R' => new[] { (1, 0), (-1, 0), (0, 1), (0, -1) },
            _ => new[] { (1, 1), (1, -1), (-1, 1), (-1, -1), (1, 0), (-1, 0), (0, 1), (0, -1) }
        };
        foreach (var (df, dr) in directions)
        {
            var f = file + df; var r = rank + dr;
            while (f is >= 0 and < 8 && r is >= 0 and < 8)
            {
                var to = r * 8 + f;
                if (board[to] == '\0') moves.Add((from, to, null));
                else { if (IsWhite(board[to]) != white && char.ToUpperInvariant(board[to]) != 'K') moves.Add((from, to, null)); break; }
                if (kind == 'K') break;
                f += df; r += dr;
            }
        }
    }

    private static void AddPawn(int from, int to, int rank, bool white, List<(int From, int To, char? Promotion)> moves)
    { moves.Add((from, to, rank == (white ? 7 : 0) ? 'Q' : null)); }

    private void AddCastles(int from, bool white, List<(int From, int To, char? Promotion)> moves)
    {
        var home = white ? 4 : 60;
        if (from != home || IsKingInCheck(white)) return;
        var king = white ? 'K' : 'k'; var queen = white ? 'Q' : 'q';
        if (castlingRights.Contains(king) && board[home + 1] == '\0' && board[home + 2] == '\0' &&
            !IsSquareAttacked(home + 1, !white) && !IsSquareAttacked(home + 2, !white)) moves.Add((home, home + 2, null));
        if (castlingRights.Contains(queen) && board[home - 1] == '\0' && board[home - 2] == '\0' && board[home - 3] == '\0' &&
            !IsSquareAttacked(home - 1, !white) && !IsSquareAttacked(home - 2, !white)) moves.Add((home, home - 2, null));
    }

    private bool IsKingInCheck(bool white)
    { var king = Array.IndexOf(board, white ? 'K' : 'k'); return king < 0 || IsSquareAttacked(king, !white); }

    private bool IsSquareAttacked(int square, bool byWhite)
    {
        var file = square % 8; var rank = square / 8; var pawnRank = rank + (byWhite ? -1 : 1);
        foreach (var df in new[] { -1, 1 })
        { var f = file + df; if (f is >= 0 and < 8 && pawnRank is >= 0 and < 8 && board[pawnRank * 8 + f] == (byWhite ? 'P' : 'p')) return true; }
        foreach (var (df, dr) in new[] { (1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2) })
        { var f = file + df; var r = rank + dr; if (f is >= 0 and < 8 && r is >= 0 and < 8 && board[r * 8 + f] == (byWhite ? 'N' : 'n')) return true; }
        foreach (var (df, dr) in new[] { (1, 1), (1, -1), (-1, 1), (-1, -1), (1, 0), (-1, 0), (0, 1), (0, -1) })
        {
            var f = file + df; var r = rank + dr; var distance = 1;
            while (f is >= 0 and < 8 && r is >= 0 and < 8)
            {
                var piece = board[r * 8 + f];
                if (piece != '\0')
                {
                    if (IsWhite(piece) == byWhite)
                    {
                        var kind = char.ToUpperInvariant(piece);
                        if (kind == 'Q' || (distance == 1 && kind == 'K') || (Math.Abs(df) == Math.Abs(dr) && kind == 'B') || ((df == 0 || dr == 0) && kind == 'R')) return true;
                    }
                    break;
                }
                f += df; r += dr; distance++;
            }
        }
        return false;
    }

    private void ApplyWithoutMate(string uci)
    {
        var from = ParseSquare(uci[..2]); var to = ParseSquare(uci[2..4]); var moving = board[from]; var captured = board[to];
        var white = whiteToMove; var ep = char.ToUpperInvariant(moving) == 'P' && to == enPassantSquare && captured == '\0';
        board[from] = '\0'; if (ep) board[to + (white ? -8 : 8)] = '\0';
        board[to] = uci.Length > 4 ? (white ? char.ToUpperInvariant(uci[4]) : char.ToLowerInvariant(uci[4])) : moving;
        if (char.ToUpperInvariant(moving) == 'K' && Math.Abs(to - from) == 2) MoveCastleRook(from, to);
        UpdateCastlingRights(moving, from, to, captured);
        enPassantSquare = char.ToUpperInvariant(moving) == 'P' && Math.Abs(to - from) == 16 ? (from + to) / 2 : -1;
        whiteToMove = !whiteToMove;
    }

    private void MoveCastleRook(int from, int to)
    { var rookFrom = to > from ? from + 3 : from - 4; var rookTo = to > from ? from + 1 : from - 1; board[rookTo] = board[rookFrom]; board[rookFrom] = '\0'; }

    private void UpdateCastlingRights(char moving, int from, int to, char captured)
    {
        if (moving == 'K') castlingRights = castlingRights.Replace("K", "").Replace("Q", "");
        if (moving == 'k') castlingRights = castlingRights.Replace("k", "").Replace("q", "");
        if (from == 0 || to == 0 && captured == 'R') castlingRights = castlingRights.Replace("Q", "");
        if (from == 7 || to == 7 && captured == 'R') castlingRights = castlingRights.Replace("K", "");
        if (from == 56 || to == 56 && captured == 'r') castlingRights = castlingRights.Replace("q", "");
        if (from == 63 || to == 63 && captured == 'r') castlingRights = castlingRights.Replace("k", "");
    }

    private static bool IsWhite(char piece) => char.IsUpper(piece);
    private static int PieceValue(char piece) => char.ToUpperInvariant(piece) switch { 'P' => 100, 'N' => 320, 'B' => 330, 'R' => 500, 'Q' => 900, _ => 0 };
    private static string PieceName(char piece) => char.ToUpperInvariant(piece) switch { 'P' => "pawn", 'N' => "knight", 'B' => "bishop", 'R' => "rook", 'Q' => "queen", 'K' => "king", _ => "piece" };
    private static int ParseSquare(string value)
    { if (value.Length != 2 || value[0] is < 'a' or > 'h' || value[1] is < '1' or > '8') throw new FormatException($"Invalid square: {value}"); return (value[1] - '1') * 8 + value[0] - 'a'; }
    private static string SquareName(int square) => $"{(char)('a' + square % 8)}{(char)('1' + square / 8)}";
}

