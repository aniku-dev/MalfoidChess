using System.Text.Json;

namespace MalfoidDialogue.Core;

/// <summary>Appends machine-readable events without writing personality text to UCI stdout.</summary>
public sealed class EventLogWriter
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly string path;
    private readonly object gate = new();

    public EventLogWriter(string? path = null)
    {
        this.path = path ?? DefaultPath;
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(this.path))!);
    }

    public static string DefaultPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MalfoidChess", "dialogue.jsonl");

    public void Append(DialogueEvent dialogueEvent)
    {
        var line = JsonSerializer.Serialize(dialogueEvent, JsonOptions) + Environment.NewLine;
        lock (gate) File.AppendAllText(path, line);
    }
}
