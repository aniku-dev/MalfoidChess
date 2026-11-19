namespace MalfoidDialogue.Window;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        var eventPath = args.Length > 0 ? args[0] : MalfoidDialogue.Core.EventLogWriter.DefaultPath;
        Application.Run(new MainForm(eventPath));
    }
}
