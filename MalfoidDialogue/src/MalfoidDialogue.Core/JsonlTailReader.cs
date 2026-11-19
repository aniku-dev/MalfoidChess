using System.Text;
using System.Text.Json;

namespace MalfoidDialogue.Core;

/// <summary>Reads complete appended JSONL records while retaining an incomplete final line.</summary>
public sealed class JsonlTailReader
{
    private readonly string path;
    private readonly HashSet<string> seen = new(StringComparer.Ordinal);
    private readonly StringBuilder pending = new();
    private long offset;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public JsonlTailReader(string path) { this.path = path; }

    public IReadOnlyList<DialogueEvent> ReadAvailable()
    {
        if (!File.Exists(path)) return [];
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        if (stream.Length < offset)
        {
            offset = 0; pending.Clear(); seen.Clear();
        }
        stream.Seek(offset, SeekOrigin.Begin);
        using var reader = new StreamReader(stream, Encoding.UTF8, true, 4096, leaveOpen: true);
        var appended = reader.ReadToEnd();
        offset = stream.Position;
        pending.Append(appended);
        var complete = pending.ToString();
        var lines = complete.Split('\n');
        pending.Clear();
        pending.Append(lines[^1]);
        var events = new List<DialogueEvent>();
        foreach (var line in lines[..^1])
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            try
            {
                var item = JsonSerializer.Deserialize<DialogueEvent>(line.TrimEnd('\r'), JsonOptions);
                if (item is not null && seen.Add(item.EventId)) events.Add(item);
            }
            catch (JsonException) { /* Ignore corrupt records without interrupting the live transcript. */ }
        }
        return events;
    }
}
