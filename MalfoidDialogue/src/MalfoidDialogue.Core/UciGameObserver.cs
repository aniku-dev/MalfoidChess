using System.Globalization;

namespace MalfoidDialogue.Core;

/// <summary>Observes the UCI stream in a side channel and reconstructs moves for the transcript.</summary>
public sealed class UciGameObserver
{
    private readonly EventLogWriter log;
    private readonly List<string> moves = [];
    private readonly List<MoveFacts> pendingMoves = [];
    private ChessPosition? position;
    private string? rootFen;
    private Guid gameId = Guid.NewGuid();
    private long sequence;
    private bool? engineIsWhite;
    private bool? searchSideIsWhite;
    private int? searchScoreWhiteCp;
    private int? searchMateWhite;
    private int? lastEvaluationWhiteCp;
    private bool gameAnnounced;

    public UciGameObserver(EventLogWriter log) { this.log = log; }

    public void Observe(string line)
    {
        var trimmed = line.Trim();
        if (trimmed.Equals("ucinewgame", StringComparison.OrdinalIgnoreCase)) { StartNewGame(); return; }
        if (trimmed.StartsWith("position ", StringComparison.OrdinalIgnoreCase)) ObservePosition(trimmed);
        else if (trimmed.StartsWith("go", StringComparison.OrdinalIgnoreCase)) BeginSearch();
        else if (trimmed.StartsWith("info ", StringComparison.OrdinalIgnoreCase)) ObserveInfo(trimmed);
        else if (trimmed.StartsWith("bestmove ", StringComparison.OrdinalIgnoreCase)) ObserveBestMove(trimmed);
    }

    private void StartNewGame()
    {
        gameId = Guid.NewGuid(); sequence = 0; moves.Clear(); pendingMoves.Clear();
        rootFen = null; position = null; engineIsWhite = null; searchSideIsWhite = null;
        searchScoreWhiteCp = null; searchMateWhite = null; lastEvaluationWhiteCp = null;
        gameAnnounced = true;
        log.Append(NewEvent("game-start"));
    }

    private void ObservePosition(string line)
    {
        try
        {
            var tokens = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            var marker = Array.IndexOf(tokens, "moves");
            var incomingMoves = marker < 0 ? [] : tokens[(marker + 1)..].Where(IsUciMove).ToList();
            string fen;
            if (tokens.Length > 1 && tokens[1] == "startpos")
                fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
            else if (tokens.Length > 1 && tokens[1] == "fen")
            {
                var end = marker >= 0 ? marker : tokens.Length;
                if (end < 8) return;
                fen = string.Join(' ', tokens[2..Math.Min(end, 8)]);
            }
            else return;

            var sameRoot = rootFen == fen && position is not null;
            var commonPrefix = 0;
            if (sameRoot) while (commonPrefix < moves.Count && commonPrefix < incomingMoves.Count &&
                moves[commonPrefix] == incomingMoves[commonPrefix]) commonPrefix++;
            if (position is null && rootFen is null)
            {
                if (!gameAnnounced) { gameAnnounced = true; log.Append(NewEvent("game-start")); }
            }
            else if (!sameRoot || commonPrefix < moves.Count) StartNewGame();
            if (position is null) { rootFen = fen; position = ChessPosition.FromFen(fen); }
            // A move list can be a prefix after an undo or GUI restart; rebuild safely and give it a fresh ID.
            foreach (var move in incomingMoves.Skip(moves.Count))
            {
                var facts = position.ApplyUci(move);
                moves.Add(move);
                RecordMove(facts);
            }
        }
        catch (Exception exception) when (exception is FormatException or InvalidOperationException or IndexOutOfRangeException)
        {
            // Incomplete or unsupported position lines are ignored; the UCI line still reaches the engine.
        }
    }

    private void BeginSearch()
    {
        if (position is null) return;
        searchSideIsWhite = position.WhiteToMove;
        if (engineIsWhite is null)
        {
            engineIsWhite = searchSideIsWhite;
            foreach (var pending in pendingMoves) WriteMove(pending);
            pendingMoves.Clear();
        }
        searchScoreWhiteCp = null; searchMateWhite = null;
    }

    private void ObserveInfo(string line)
    {
        if (searchSideIsWhite is null) return;
        var tokens = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        for (var i = 0; i + 2 < tokens.Length; i++)
        {
            if (tokens[i] != "score" || tokens.Contains("lowerbound") || tokens.Contains("upperbound")) continue;
            var isWhitePerspective = searchSideIsWhite.Value;
            if (tokens[i + 1] == "cp" && int.TryParse(tokens[i + 2], NumberStyles.Integer, CultureInfo.InvariantCulture, out var cp))
                searchScoreWhiteCp = isWhitePerspective ? cp : -cp;
            else if (tokens[i + 1] == "mate" && int.TryParse(tokens[i + 2], NumberStyles.Integer, CultureInfo.InvariantCulture, out var mate))
                searchMateWhite = isWhitePerspective ? mate : -mate;
            break;
        }
    }

    private void ObserveBestMove(string line)
    {
        if (position is null) return;
        var tokens = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (tokens.Length < 2 || !IsUciMove(tokens[1])) return;
        try
        {
            // bestmove is the engine's committed move; adding it here means the opponent's next
            // position command only contributes the newly played reply, not a duplicate.
            var facts = position.ApplyUci(tokens[1]);
            moves.Add(tokens[1]);
            RecordMove(facts);
            if (searchScoreWhiteCp is int cp)
            {
                var swing = lastEvaluationWhiteCp is int previous ? cp - previous : (int?)null;
                log.Append(NewEvent("evaluation") with
                {
                    EvaluationWhiteCp = cp, EvaluationMateWhite = searchMateWhite,
                    EvaluationSwingWhiteCp = swing, MaterialBalanceWhiteCp = position.MaterialBalanceWhiteCp(),
                    EngineIsWhite = engineIsWhite
                });
                lastEvaluationWhiteCp = cp;
            }
            else if (searchMateWhite is int mate)
                log.Append(NewEvent("evaluation") with { EvaluationMateWhite = mate, EngineIsWhite = engineIsWhite });
        }
        catch (Exception exception) when (exception is FormatException or InvalidOperationException or IndexOutOfRangeException)
        {
            // Search results such as "bestmove (none)" and malformed output are not moves.
        }
    }

    private void RecordMove(MoveFacts facts)
    {
        if (engineIsWhite is null) { pendingMoves.Add(facts); return; }
        WriteMove(facts);
    }

    private void WriteMove(MoveFacts facts)
    {
        var malfoidMove = facts.MoverIsWhite == engineIsWhite;
        var malfoidDelta = malfoidMove ? facts.MaterialDeltaWhiteCp * (facts.MoverIsWhite ? 1 : -1)
            : -facts.MaterialDeltaWhiteCp * (facts.MoverIsWhite ? 1 : -1);
        log.Append(NewEvent("move") with
        {
            Ply = facts.Ply, MoveNumber = facts.MoveNumber, Side = facts.MoverIsWhite ? "White" : "Black",
            UciMove = facts.Uci, Piece = facts.Piece, CapturedPiece = facts.CapturedPiece,
            IsCheck = facts.IsCheck, IsCheckmate = facts.IsCheckmate, IsMalfoidMove = malfoidMove,
            EngineIsWhite = engineIsWhite, MaterialBalanceWhiteCp = facts.MaterialBalanceWhiteCp,
            MalfoidMaterialDeltaCp = malfoidDelta
        });
    }

    private DialogueEvent NewEvent(string kind) => new()
    { GameId = gameId, Sequence = ++sequence, Kind = kind, EngineIsWhite = engineIsWhite };

    private static bool IsUciMove(string value) =>
        value.Length is 4 or 5 && value[0] is >= 'a' and <= 'h' && value[1] is >= '1' and <= '8' &&
        value[2] is >= 'a' and <= 'h' && value[3] is >= '1' and <= '8';
}



