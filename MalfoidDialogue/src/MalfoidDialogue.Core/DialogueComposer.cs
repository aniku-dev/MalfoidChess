namespace MalfoidDialogue.Core;

/// <summary>Creates short, optional personality text from already-separated game events.</summary>
public sealed class DialogueComposer
{
    private readonly Queue<string> recent = new();
    private readonly HashSet<string> seen = new(StringComparer.Ordinal);
    private readonly Random random;

    public DialogueComposer(int? seed = null) { random = seed is null ? Random.Shared : new Random(seed.Value); }

    public string? Compose(DialogueEvent item)
    {
        if (item.Kind == "game-start") return AvoidRepeat(Pick("New game. Try not to embarrass yourself, POTTAH.", "A fresh game? Do keep up this time.", "Try not to make me look bad, POTTAH."));
        if (item.Kind == "evaluation") return ComposeEvaluation(item);
        if (item.Kind != "move") return null;

        string? line = null;
        if (item.IsCheckmate)
            line = item.IsMalfoidMove ? "Checkmate. Do try to keep up." : "MY FATHER WILL HEAR ABOUT THIS!";
        else if (item.CapturedPiece is not null)
        {
            if (item.IsMalfoidMove)
                line = $"POTTAH! That {item.CapturedPiece} belongs to me now.";
            else if (item.CapturedPiece == "queen")
                line = "I WAS NOT ATTACHED TO THAT QUEEN. Stop asking.";
            else if (item.MalfoidMaterialDeltaCp < -250)
                line = "That was a tactical retreat. I meant to do that.";
            else
                line = Pick("You may keep that. For now.", "Don't look so pleased with yourself.", "A temporary setback. Obviously.");
        }
        else if (item.IsCheck)
            line = item.IsMalfoidMove ? Pick("Check. Do try to look surprised.", "Your king is looking rather uncomfortable.") :
                Pick("Check? How dramatic. I'll handle it.", "Stop checking. It's unbecoming.");
        else if (item.MalfoidMaterialDeltaCp <= -900)
            line = "I WAS NOT ATTACHED TO THAT QUEEN. Stop asking.";
        else if (item.MalfoidMaterialDeltaCp <= -300)
            line = Pick("That piece was getting on my nerves anyway.", "I meant to give you false confidence.");
        else if (item.MalfoidMaterialDeltaCp >= 300)
            line = Pick("That rook is now a family heirloom.", "A costly mistake. For you, I mean.");
        else
            line = Pick("An adequate move. Don't get smug.", "I suppose that was almost competent.", "Try to keep up, POTTAH.");
        return AvoidRepeat(line);
    }

    private string? ComposeEvaluation(DialogueEvent item)
    {
        var score = item.EvaluationWhiteCp;
        if (item.EvaluationMateWhite is int mate)
        {
            var malfoidMating = item.EngineIsWhite == true ? mate > 0 : mate < 0;
            return AvoidRepeat(malfoidMating ? "A forced mate. You can stop pretending now." : "This position is beneath me. Rematch. NOW.");
        }
        if (score is null) return null;
        var malfoidScore = item.EngineIsWhite == true ? score.Value : -score.Value;
        if (malfoidScore <= -700) return AvoidRepeat("This position is beneath me. Rematch. NOW.");
        if (malfoidScore >= 700) return AvoidRepeat("Naturally, the position favors me.");
        if (item.EvaluationSwingWhiteCp is int swing)
        {
            var malfoidSwing = item.EngineIsWhite == true ? swing : -swing;
            if (malfoidSwing >= 250) return AvoidRepeat("As expected, I am brilliant.");
            if (malfoidSwing <= -350) return AvoidRepeat("That evaluation is obviously being dramatic.");
        }
        return null;
    }

    private string Pick(params string[] lines) => lines[random.Next(lines.Length)];

    private string? AvoidRepeat(string? line)
    {
        if (line is null) return null;
        if (seen.Contains(line))
        {
            var alternatives = new[]
            {
                "Do not mistake that for generosity.",
                "I had this entirely under control.",
                "Well. That was mildly inconvenient.",
                "I refuse to discuss that move."
            }.Where(candidate => !seen.Contains(candidate)).ToArray();
            if (alternatives.Length == 0) { seen.Clear(); alternatives = ["I refuse to discuss that move."]; }
            line = alternatives[random.Next(alternatives.Length)];
        }
        seen.Add(line); recent.Enqueue(line);
        if (recent.Count > 14) seen.Remove(recent.Dequeue());
        return line;
    }
}




