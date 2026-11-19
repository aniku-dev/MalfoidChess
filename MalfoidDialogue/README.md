# Malfoid Dialogue Companion

A small Windows desktop transcript for MalfoidChess. It runs as two independent pieces:

1. **UCI proxy** — configure Cute Chess to launch this instead of the chess engine. It forwards UCI commands and engine replies unchanged, while observing the stream and appending structured events to JSON Lines.
2. **Dialogue window** — a separate WinForms app that follows the event log and displays short, move-numbered lines.

The companion does not modify the Swift engine, its evaluation, its search, or its UCI stdout. Personality text is only shown in the companion window.

## Integration choice and limits

Cute Chess supports UCI engines, so the companion uses a transparent UCI proxy rather than assuming a private GUI API. Cute Chess does not stream a live PGN; its maintainers have described PGN as a completed-game save. That makes polling PGN unsuitable for live per-move commentary. See [Cute Chess issue #184](https://github.com/cutechess/cutechess/issues/184) and the [Cute Chess repository](https://github.com/cutechess/cutechess).

The UCI position command usually carries the full move history, which lets the proxy report both players' moves. It reports captures, check, checkmate, and material directly from that history. Scores are included when the engine emits info score; score swings are described as swings, not automatically blamed on an individual move.

**Limitation:** UCI does not send a game-result notification. If the opponent's final move checkmates Malfoid, Cute Chess may never ask the engine to process that final position, so the proxy cannot see that move. Malfoid's own delivered checkmate moves are detected. To report every opponent checkmate, a completed PGN/result source would need to be connected; Cute Chess's regular PGN save is not live. This version does not claim to detect that unobserved final move.

If the GUI sends only a fresh FEN without the move history, past moves cannot be reconstructed from UCI. The current position can still be used as the observer's starting point, but that move itself will not be described.

## Requirements

- Windows 10/11
- .NET 10 SDK to build (and .NET 10 Desktop Runtime to run framework-dependent builds)
- Existing MalfoidChess Windows executable

No NuGet dependencies are used.

## Build

From this directory in PowerShell:

    .\build.ps1

Build outputs:

- src\MalfoidDialogue.Proxy\bin\Release\net10.0\MalfoidDialogue.Proxy.exe
- src\MalfoidDialogue.Window\bin\Release\net10.0-windows\MalfoidDialogue.Window.exe

Run the automated checks:

    .\test.ps1

The test runner is a plain .NET console app, so it needs no test framework package.

## Cute Chess setup

1. Build the companion.
2. In Cute Chess, add a UCI engine and point its executable/command to MalfoidDialogue.Proxy.exe.
3. Use these command-line arguments (adjust the engine path):

       --engine "C:\path\to\MalfoidChess.exe"

   If Cute Chess has separate executable and arguments fields, put only the proxy path in the executable field and the rest in arguments. If it accepts one command string, quote paths containing spaces.
4. Launch MalfoidDialogue.Window.exe independently. With no extra arguments, both programs use the same default log under your Local AppData folder. For a custom event log, pass the same absolute path to the window and as the value of --events to the proxy.

The proxy accepts extra engine arguments through repeatable options:

    --engine-arg "argument"

The proxy and window can also be started directly from PowerShell:

    & ".\src\MalfoidDialogue.Proxy\bin\Release\net10.0\MalfoidDialogue.Proxy.exe" --engine "C:\path\to\MalfoidChess.exe"
    & ".\src\MalfoidDialogue.Window\bin\Release\net10.0-windows\MalfoidDialogue.Window.exe"

## Architecture

- MalfoidDialogue.Core/ChessPosition.cs — FEN/UCI move application, material accounting, attacks, and legal-move checks for checkmate detection.
- MalfoidDialogue.Core/UciGameObserver.cs — watches both sides' moves and engine scores without changing UCI output.
- MalfoidDialogue.Core/EventLogWriter.cs — appends independent JSONL events.
- MalfoidDialogue.Core/DialogueComposer.cs — short, varied haughty/greedy/tsundere lines with a small recent-line memory.
- MalfoidDialogue.Core/JsonlTailReader.cs — reads only complete log records and deduplicates event IDs.
- MalfoidDialogue.Proxy — child-process UCI bridge.
- MalfoidDialogue.Window — standalone, scrollable Windows Forms transcript.
- MalfoidDialogue.Tests — dependency-free executable checks for core behavior.

The dramatic “losing badly” line is triggered by a reported engine evaluation of at least 7 pawns against Malfoid (about -700 cp from Malfoid's perspective), or a reported forced mate against her. This affects dialogue only; it never changes how the engine plays. Material losses are identified from the actual board changes, while evaluation swings are not assumed to identify a specific blunder.

## Troubleshooting

- If Cute Chess times out, point its engine entry to the proxy executable and verify the --engine path. The proxy keeps UCI stdout clean and flushes each forwarded engine line immediately.
- Check %LOCALAPPDATA%\MalfoidChess\dialogue.jsonl for observed events.
- Run the companion window with the exact same custom log path used by the proxy.
- The proxy writes its own diagnostics to stderr, never to UCI stdout.


