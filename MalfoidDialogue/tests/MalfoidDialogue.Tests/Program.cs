using System.Text.Json;
using MalfoidDialogue.Core;

var testCount = 0;
TestStartPositionAndCapture();
TestEnPassant();
TestCheckmateDetection();
TestUciObservationAndDeduplication();
TestPartialJsonLine();
TestDialogueForEveryMoveAndLosingThreshold();
TestExplicitGameReset();
Console.WriteLine($"Passed {testCount} Malfoid Dialogue tests.");

void Assert(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException("FAILED: " + message);
    testCount++;
}

void TestStartPositionAndCapture()
{
    var position = ChessPosition.StartPosition();
    Assert(position.MaterialBalanceWhiteCp() == 0, "starting material balances");
    position.ApplyUci("e2e4");
    position.ApplyUci("d7d5");
    var capture = position.ApplyUci("e4d5");
    Assert(capture.CapturedPiece == "pawn", "normal capture identifies the captured pawn");
    Assert(capture.MaterialBalanceWhiteCp == 100 && capture.MaterialDeltaWhiteCp == 100, "capture updates white material");
    Assert(capture.Ply == 3 && capture.MoveNumber == 2, "ply and full-move number are correct");
}

void TestEnPassant()
{
    var position = ChessPosition.StartPosition();
    foreach (var move in new[] { "e2e4", "a7a6", "e4e5", "d7d5" }) position.ApplyUci(move);
    var capture = position.ApplyUci("e5d6");
    Assert(capture.CapturedPiece == "pawn", "en passant reports the captured pawn");
    Assert(capture.MaterialBalanceWhiteCp == 100, "en passant removes material from the board");
}

void TestCheckmateDetection()
{
    var position = ChessPosition.StartPosition();
    foreach (var move in new[] { "e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6" }) position.ApplyUci(move);
    var mate = position.ApplyUci("h5f7");
    Assert(mate.IsCheck && mate.IsCheckmate, "Scholar's Mate is identified as checkmate");
}

void TestUciObservationAndDeduplication()
{
    var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".jsonl");
    try
    {
        var observer = new UciGameObserver(new EventLogWriter(path));
        observer.Observe("position startpos moves e2e4");
        observer.Observe("go wtime 300000 btime 300000");
        observer.Observe("info depth 3 score cp -15");
        observer.Observe("bestmove e7e5");
        observer.Observe("position startpos moves e2e4 e7e5");
        var events = File.ReadAllLines(path).Select(line => JsonSerializer.Deserialize<DialogueEvent>(line, new JsonSerializerOptions(JsonSerializerDefaults.Web))!).ToArray();
        Assert(events.Count(item => item.Kind == "move") == 2, "both players' moves appear exactly once");
        Assert(events.Single(item => item.UciMove == "e2e4").IsMalfoidMove == false, "the opponent's move is labeled correctly for a black engine");
        Assert(events.Single(item => item.UciMove == "e7e5").IsMalfoidMove, "the engine's move is labeled as Malfoid's");
        Assert(events.Any(item => item.Kind == "evaluation" && item.EvaluationWhiteCp == 15), "UCI score is normalized to White's perspective");
    }
    finally { if (File.Exists(path)) File.Delete(path); }
}

void TestDialogueForEveryMoveAndLosingThreshold()
{
    var composer = new DialogueComposer(seed: 1);
    var quietWhite = new DialogueEvent { Kind = "move", Ply = 1, MoveNumber = 1, Side = "White", UciMove = "e2e4", IsMalfoidMove = false };
    var quietBlack = quietWhite with { Ply = 2, Side = "Black", UciMove = "e7e5", IsMalfoidMove = true };
    Assert(composer.Compose(quietWhite) is not null, "every quiet move receives dialogue");
    Assert(composer.Compose(quietBlack) is not null, "Malfoid quiet moves receive dialogue");
    var losing = new DialogueEvent { Kind = "evaluation", EngineIsWhite = true, EvaluationWhiteCp = -700 };
    Assert(composer.Compose(losing) == "This position is beneath me. Rematch. NOW.", "losing line triggers at seven pawns against Malfoid");
}

void TestExplicitGameReset()
{
    var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".jsonl");
    try
    {
        var observer = new UciGameObserver(new EventLogWriter(path));
        observer.Observe("ucinewgame");
        observer.Observe("position startpos moves e2e4");
        observer.Observe("go depth 1");
        observer.Observe("bestmove e7e5");
        observer.Observe("position startpos moves e2e4 e7e5");
        observer.Observe("ucinewgame");
        var events = File.ReadAllLines(path).Select(line => JsonSerializer.Deserialize<DialogueEvent>(line, new JsonSerializerOptions(JsonSerializerDefaults.Web))!).ToArray();
        Assert(events.Count(item => item.Kind == "game-start") == 2, "explicit reset starts a distinct dialogue game");
        Assert(events.Count(item => item.Kind == "move") == 2, "reset does not duplicate moves in the previous game");
    }
    finally { if (File.Exists(path)) File.Delete(path); }
}

void TestPartialJsonLine()
{
    var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".jsonl");
    try
    {
        var item = new DialogueEvent { GameId = Guid.NewGuid(), Sequence = 1, Kind = "game-start" };
        var line = JsonSerializer.Serialize(item, new JsonSerializerOptions(JsonSerializerDefaults.Web)) + "\n";
        var split = line.Length / 2;
        File.WriteAllText(path, line[..split]);
        var reader = new JsonlTailReader(path);
        Assert(reader.ReadAvailable().Count == 0, "an incomplete final JSON record is held back");
        File.AppendAllText(path, line[split..]);
        Assert(reader.ReadAvailable().Count == 1, "the completed JSON record is emitted once");
        Assert(reader.ReadAvailable().Count == 0, "polling the same file does not duplicate the record");
    }
    finally { if (File.Exists(path)) File.Delete(path); }
}

