# MalfoidChess

MalfoidChess is a material-focused chess engine written in Swift. It communicates through UCI and uses a compact, passive opening book.

The project has no explicit imports or third-party dependencies. Source files compile together using only Swift's standard library.

## Build and run

Requires Swift 6 or newer and a working Swift compiler (swiftc).

On Windows PowerShell:

~~~powershell
.\build.ps1
.\.build\MalfoidChess.exe
~~~

Run the dependency-free test harness:

~~~powershell
.\test.ps1
~~~

On macOS or Linux:

~~~sh
swiftc Sources/Chess/*.swift Sources/MalfoidChess/*.swift -o MalfoidChess
swiftc Sources/Chess/*.swift Tests/TestMain.swift -o MalfoidChessTests
./MalfoidChessTests
~~~

## UCI example

Start the executable and send these commands as an example:

~~~text
uci
isready
position startpos moves e2e4 e7e5
go depth 4
~~~

The engine supports uci, isready, ucinewgame, position startpos, position fen, go depth, go movetime, common clock fields, setoption, stop, and quit. Searches run synchronously and are bounded by depth or time. To keep the process responsive in simple environments, go infinite uses a short default depth and returns a move.

## Architecture and evaluation

- **ChessTypes.swift and Board.swift** implement pieces, FEN, legal moves, check detection, castling, en passant, and promotion.
- **Search.swift** uses material values, small piece-square bonuses, iterative deepening, negamax with alpha-beta pruning, move ordering, quiescence search, and the loss-position behavior.
- **OpeningBook.swift** contains a few quiet lines from the initial position. Positions outside those lines are searched.
- **UCI.swift** parses commands and flushes each protocol response for GUI clients.
- **Personality.swift** supplies optional meme-inspired dialogue, disabled unless explicitly enabled.

Material values are pawn 100, knight 320, bishop 330, rook 500, and queen 900 centipawns. If a completed search puts the side to move at -600 centipawns or worse, the engine might deliberately choose a move that leaves its valuable pieces undefended depending on its composure level. The quiet opening book remains enabled.

## Tests and limits

The custom test runner covers initial-position perft counts through depth three, FEN round-tripping, castling, castling through attack, pinned pieces, en passant, promotion, opening-book replies, and a mate-in-one search.

This is a small starter engine, not a tournament engine. It has no transposition table, repetition or fifty-move draw handling, tablebases, ponder support, or broad opening book. Its search is shallow and its time management is basic; it can miss tactics and blunder.

## Additional info

I had Codex generate the initial project as a side project for fun, and any additional changes may be done by me or any other willing contributor.