using MalfoidDialogue.Core;

namespace MalfoidDialogue.Window;

internal sealed class MainForm : Form
{
    private readonly RichTextBox transcript = new();
    private readonly Label status = new();
    private readonly TextBox pathBox = new();
    private DialogueComposer composer = new();
    private JsonlTailReader reader;
    private string eventPath;

    public MainForm(string eventPath)
    {
        this.eventPath = Path.GetFullPath(eventPath);
        reader = new JsonlTailReader(this.eventPath);
        Text = "Malfoid — Game Commentary";
        MinimumSize = new Size(560, 360);
        Size = new Size(760, 560);
        StartPosition = FormStartPosition.CenterScreen;
        BuildLayout();

        var pollTimer = new System.Windows.Forms.Timer { Interval = 250 };
        pollTimer.Tick += (_, _) => ReadEvents();
        pollTimer.Start();
        FormClosed += (_, _) => pollTimer.Dispose();
        ReadEvents();
    }

    private void BuildLayout()
    {
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, ColumnCount = 1, Padding = new Padding(10) };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var toolbar = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, WrapContents = false };
        toolbar.Controls.Add(new Label { Text = "Event log", AutoSize = true, Margin = new Padding(3, 8, 6, 0) });
        pathBox.Text = eventPath;
        pathBox.Width = 510;
        toolbar.Controls.Add(pathBox);
        var browse = new Button { Text = "Browse…", AutoSize = true };
        browse.Click += (_, _) => SelectLog();
        toolbar.Controls.Add(browse);

        transcript.Dock = DockStyle.Fill;
        transcript.ReadOnly = true;
        transcript.WordWrap = true;
        transcript.DetectUrls = false;
        transcript.BackColor = Color.FromArgb(30, 30, 36);
        transcript.ForeColor = Color.FromArgb(240, 232, 214);
        transcript.Font = new Font("Segoe UI", 10);
        transcript.BorderStyle = BorderStyle.FixedSingle;

        status.Text = "Waiting for a game…";
        status.AutoSize = true;
        status.Dock = DockStyle.Fill;

        layout.Controls.Add(toolbar, 0, 0);
        layout.Controls.Add(transcript, 0, 1);
        layout.Controls.Add(status, 0, 2);
        Controls.Add(layout);
    }

    private void SelectLog()
    {
        using var picker = new OpenFileDialog
        {
            Title = "Select the Malfoid dialogue JSONL log",
            Filter = "JSON Lines (*.jsonl)|*.jsonl|All files (*.*)|*.*",
            CheckFileExists = false,
            FileName = Path.GetFileName(eventPath),
            InitialDirectory = Path.GetDirectoryName(eventPath)
        };
        if (picker.ShowDialog(this) != DialogResult.OK) return;
        eventPath = Path.GetFullPath(picker.FileName);
        pathBox.Text = eventPath;
        reader = new JsonlTailReader(eventPath);
        composer = new DialogueComposer();
        transcript.Clear();
        ReadEvents();
    }

    private void ReadEvents()
    {
        try
        {
            foreach (var item in reader.ReadAvailable()) ShowEvent(item);
            status.Text = File.Exists(eventPath) ? $"Following {eventPath}" : $"Waiting for log file: {eventPath}";
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            status.Text = "The event log is temporarily unavailable.";
        }
    }

    private void ShowEvent(DialogueEvent item)
    {
        var line = composer.Compose(item);
        if (line is null) return;
        var prefix = item.Kind == "move"
            ? $"{item.MoveNumber}{(item.Side == "Black" ? "..." : ".")} {item.Side} · {item.UciMove}"
            : item.Kind == "evaluation" ? "Position · engine evaluation" : "New game";
        var timestamp = item.TimestampUtc.ToLocalTime().ToString("HH:mm:ss");
        transcript.AppendText($"[{timestamp}] {prefix}: {line}{Environment.NewLine}");
        transcript.SelectionStart = transcript.TextLength;
        transcript.ScrollToCaret();
    }
}



