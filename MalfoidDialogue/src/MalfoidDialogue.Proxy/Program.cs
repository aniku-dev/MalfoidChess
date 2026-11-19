using System.Diagnostics;
using MalfoidDialogue.Core;

var options = ProxyOptions.Parse(args);
if (options is null)
{
    Console.Error.WriteLine("Usage: MalfoidDialogue.Proxy.exe --engine <engine.exe> [--events <path>] [--engine-arg <arg> ...]");
    return 2;
}

var startInfo = new ProcessStartInfo(options.EnginePath)
{
    UseShellExecute = false,
    RedirectStandardInput = true,
    RedirectStandardOutput = true,
    RedirectStandardError = true,
    CreateNoWindow = true
};
foreach (var argument in options.EngineArguments) startInfo.ArgumentList.Add(argument);

using var engine = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
try
{
    if (!engine.Start())
    {
        Console.Error.WriteLine("Could not start the configured chess engine.");
        return 2;
    }
}
catch (Exception exception)
{
    Console.Error.WriteLine($"Could not start engine '{options.EnginePath}': {exception.Message}");
    return 2;
}

var observer = new UciGameObserver(new EventLogWriter(options.EventPath));
var stdoutTask = ForwardEngineOutputAsync(engine, observer);
var stderrTask = ForwardEngineErrorsAsync(engine);
try
{
    while (await Console.In.ReadLineAsync() is { } line)
    {
        ObserveSafely(observer, line);
        await engine.StandardInput.WriteLineAsync(line);
        await engine.StandardInput.FlushAsync();
        if (line.Trim().Equals("quit", StringComparison.OrdinalIgnoreCase)) break;
    }
}
catch (IOException exception)
{
    Console.Error.WriteLine($"UCI pipe closed: {exception.Message}");
}
finally
{
    try { engine.StandardInput.Close(); } catch (IOException) { }
}

try { await engine.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5)); }
catch (TimeoutException) { engine.Kill(entireProcessTree: true); }
await Task.WhenAll(stdoutTask, stderrTask);
return engine.ExitCode;

static void ObserveSafely(UciGameObserver observer, string line)
{
    try { lock (observer) observer.Observe(line); }
    catch (Exception exception) { Console.Error.WriteLine($"Dialogue observer error: {exception.Message}"); }
}

static async Task ForwardEngineOutputAsync(Process engine, UciGameObserver observer)
{
    while (await engine.StandardOutput.ReadLineAsync() is { } line)
    {
        ObserveSafely(observer, line);
        Console.Out.WriteLine(line);
        Console.Out.Flush(); // Keep UCI replies timely for Cute Chess.
    }
}

static async Task ForwardEngineErrorsAsync(Process engine)
{
    while (await engine.StandardError.ReadLineAsync() is { } line)
    {
        Console.Error.WriteLine(line);
        Console.Error.Flush();
    }
}

sealed record ProxyOptions(string EnginePath, string? EventPath, IReadOnlyList<string> EngineArguments)
{
    public static ProxyOptions? Parse(string[] args)
    {
        string? enginePath = null, eventPath = null;
        var engineArguments = new List<string>();
        for (var index = 0; index < args.Length; index++)
        {
            switch (args[index])
            {
                case "--engine" when index + 1 < args.Length: enginePath = args[++index]; break;
                case "--events" when index + 1 < args.Length: eventPath = args[++index]; break;
                case "--engine-arg" when index + 1 < args.Length: engineArguments.Add(args[++index]); break;
                default: return null;
            }
        }
        if (string.IsNullOrWhiteSpace(enginePath) || !File.Exists(enginePath)) return null;
        return new ProxyOptions(Path.GetFullPath(enginePath), eventPath, engineArguments);
    }
}


