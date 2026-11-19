namespace MalfoidDialogue.Core;

public sealed record DialogueEvent
{
    public string EventId { get; init; } = Guid.NewGuid().ToString("N");
    public Guid GameId { get; init; }
    public long Sequence { get; init; }
    public string Kind { get; init; } = "";
    public DateTimeOffset TimestampUtc { get; init; } = DateTimeOffset.UtcNow;
    public int Ply { get; init; }
    public int MoveNumber { get; init; }
    public string? Side { get; init; }
    public string? UciMove { get; init; }
    public string? Piece { get; init; }
    public string? CapturedPiece { get; init; }
    public bool IsCheck { get; init; }
    public bool IsCheckmate { get; init; }
    public bool IsMalfoidMove { get; init; }
    public bool? EngineIsWhite { get; init; }
    public int MaterialBalanceWhiteCp { get; init; }
    public int MalfoidMaterialDeltaCp { get; init; }
    public int? EvaluationWhiteCp { get; init; }
    public int? EvaluationMateWhite { get; init; }
    public int? EvaluationSwingWhiteCp { get; init; }
    public string? Result { get; init; }
}

public sealed record MoveFacts(
    string Uci,
    int Ply,
    int MoveNumber,
    bool MoverIsWhite,
    string Piece,
    string? CapturedPiece,
    bool IsCheck,
    bool IsCheckmate,
    int MaterialBalanceWhiteCp,
    int MaterialDeltaWhiteCp);

