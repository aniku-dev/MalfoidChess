if CommandLine.arguments.contains("--personality-demo") {
    print(Personality.demoLine)
} else {
    let commentaryEnabled = CommandLine.arguments.contains("--commentary")
    let personalitySeed = CommandLine.arguments.firstIndex(of: "--personality-seed")
        .flatMap { index in
            CommandLine.arguments.indices.contains(index + 1) ? UInt64(CommandLine.arguments[index + 1]) : nil
        }
    UCIEngine(commentaryEnabled: commentaryEnabled, personalitySeed: personalitySeed).run()
}
