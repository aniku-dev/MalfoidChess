enum PersonalityProfile: String, CaseIterable {
    case composed
    case irritated
    case tilted
    case meltdownProne = "meltdown-prone"

    var lossSensitivity: Int {
        switch self {
        case .composed: 2
        case .irritated: 4
        case .tilted: 7
        case .meltdownProne: 12
        }
    }

    var rewardSensitivity: Int {
        switch self {
        case .composed: 3
        case .irritated: 4
        case .tilted: 5
        case .meltdownProne: 6
        }
    }

    var failedAttackSensitivity: Int {
        switch self {
        case .composed: 2
        case .irritated: 5
        case .tilted: 8
        case .meltdownProne: 12
        }
    }
}

struct PersonalityProbabilities {
    var composed = 30
    var irritated = 30
    var tilted = 20
    var meltdownProne = 20

    var totalWeight: Int {
        max(0, composed) + max(0, irritated) + max(0, tilted) + max(0, meltdownProne)
    }

    func profile(forRoll roll: Int) -> PersonalityProfile {
        let total = totalWeight
        guard total > 0 else { return .composed }
        var remainder = ((roll % total) + total) % total
        for (profile, weight) in [
            (PersonalityProfile.composed, max(0, composed)),
            (.irritated, max(0, irritated)),
            (.tilted, max(0, tilted)),
            (.meltdownProne, max(0, meltdownProne))
        ] {
            if remainder < weight { return profile }
            remainder -= weight
        }
        return .composed
    }
}

struct PersonalityConfiguration {
    var enabled = true
    var probabilities = PersonalityProbabilities()
    var irritatedChancePercent = 8
    var tiltedChancePercent = 14
    var meltdownChancePercent = 22
    var irritatedDeviationCp = 80
    var tiltedDeviationCp = 170
    var meltdownDeviationCp = 260
    var maximumDeviationCp = 400
}

enum ComposureEvent {
    case lostMaterial(centipawns: Int)
    case wonMaterial(centipawns: Int)
    case failedAttack
    case strongDefense
    case counterattack
}

struct PersonalityMoveCandidate {
    let move: Move
    let score: Int
    let isActive: Bool
    let isRisky: Bool
    let allowsMateInOne: Bool
    let isStrongDefense: Bool
    let isCounterattack: Bool
}

struct MoveSelection {
    let candidate: PersonalityMoveCandidate
    let usedPersonalityDeviation: Bool
    let usedMateSafeguard: Bool
}

/// Facts from a move that actually appeared in the UCI position history.
struct ObservedMoveFacts {
    let move: Move
    let mover: Color
    let materialDeltaForMoverCp: Int
    let wasInCheck: Bool
    let gaveCheck: Bool
    let hangingMaterialBeforeCp: Int
    let hangingMaterialAfterCp: Int
    let malfoidAttackedValuableSquares: Set<Int>
}

/// Owns the random profile and emotional state, independently of board evaluation.
final class ComposureSystem {
    private var random: any RandomNumberGenerator
    private(set) var profile: PersonalityProfile?
    private(set) var composure = 100
    private var lastOwnMove: Move?
    private var pendingAttackSquares: Set<Int> = []
    private var pendingCheck = false

    init(seed: UInt64? = nil) {
        if let seed {
            random = SeededRandomNumberGenerator(seed: seed)
        } else {
            random = SystemRandomNumberGenerator()
        }
    }

    func startNewGame(configuration: PersonalityConfiguration) {
        composure = 100
        lastOwnMove = nil
        pendingAttackSquares = []
        pendingCheck = false
        guard configuration.enabled else {
            profile = nil
            return
        }
        let total = max(1, configuration.probabilities.totalWeight)
        profile = configuration.probabilities.profile(forRoll: randomInt(upperBound: total))
    }

    func apply(_ event: ComposureEvent) {
        guard let profile else { return }
        let change: Int
        switch event {
        case .lostMaterial(let centipawns):
            let pawns = max(1, centipawns / 100)
            change = -pawns * profile.lossSensitivity
        case .wonMaterial(let centipawns):
            let pawns = max(1, centipawns / 100)
            change = pawns * profile.rewardSensitivity
        case .failedAttack:
            change = -profile.failedAttackSensitivity
        case .strongDefense:
            change = profile.rewardSensitivity + 2
        case .counterattack:
            change = profile.rewardSensitivity
        }
        composure = min(100, max(0, composure + change))
    }

    /// Updates mood from board events, not from a repeated reading of the current score.
    func observe(_ facts: ObservedMoveFacts, engineColor: Color) {
        if facts.mover == engineColor {
            if facts.materialDeltaForMoverCp > 0 {
                apply(.wonMaterial(centipawns: facts.materialDeltaForMoverCp))
            } else if facts.materialDeltaForMoverCp < 0 {
                apply(.lostMaterial(centipawns: -facts.materialDeltaForMoverCp))
            }
            if facts.wasInCheck || facts.hangingMaterialAfterCp + 200 < facts.hangingMaterialBeforeCp {
                apply(.strongDefense)
            }
            if facts.gaveCheck || !facts.malfoidAttackedValuableSquares.isEmpty {
                apply(.counterattack)
            }
            pendingAttackSquares = facts.malfoidAttackedValuableSquares
            pendingCheck = facts.gaveCheck
            lastOwnMove = facts.move
        } else {
            let malfoidGain = -facts.materialDeltaForMoverCp
            if malfoidGain > 0 {
                apply(.wonMaterial(centipawns: malfoidGain))
            } else if malfoidGain < 0 {
                apply(.lostMaterial(centipawns: -malfoidGain))
            }
            let attackWasNeutralized = pendingCheck ||
                (!pendingAttackSquares.isEmpty &&
                 pendingAttackSquares.isDisjoint(with: facts.malfoidAttackedValuableSquares))
            if malfoidGain <= 0 && attackWasNeutralized { apply(.failedAttack) }
            pendingAttackSquares = []
            pendingCheck = false
        }
    }

    func selectMove(
        from candidates: [PersonalityMoveCandidate],
        configuration: PersonalityConfiguration
    ) -> MoveSelection? {
        guard !candidates.isEmpty else { return nil }
        guard configuration.enabled, let profile else {
            let best = candidates.max { $0.score < $1.score }!
            return MoveSelection(candidate: best, usedPersonalityDeviation: false, usedMateSafeguard: false)
        }

        // A move that permits mate in one is removed whenever any move avoids it.
        // This safety rule applies before any profile-based preferences.
        let safeCandidates = candidates.filter { !$0.allowsMateInOne }
        let choices = safeCandidates.isEmpty ? candidates : safeCandidates
        let baseline = choices.max { $0.score < $1.score }!
        let usedMateSafeguard = baseline.move != candidates.max { $0.score < $1.score }!.move
        guard profile != .composed else {
            return MoveSelection(candidate: baseline, usedPersonalityDeviation: false, usedMateSafeguard: usedMateSafeguard)
        }

        let chance = activationChance(for: profile, configuration: configuration)
        guard randomInt(upperBound: 100) < chance else {
            return MoveSelection(candidate: baseline, usedPersonalityDeviation: false, usedMateSafeguard: usedMateSafeguard)
        }

        let deviation = deviationLimit(for: profile, configuration: configuration)
        let interestingMoves = choices.filter {
            $0.move != baseline.move &&
                $0.isActive &&
                baseline.score - $0.score <= deviation &&
                !isRecentReversal($0.move)
        }
        guard !interestingMoves.isEmpty else {
            return MoveSelection(candidate: baseline, usedPersonalityDeviation: false, usedMateSafeguard: usedMateSafeguard)
        }

        let eligibleMoves: [PersonalityMoveCandidate]
        if profile == .meltdownProne {
            let riskyMoves = interestingMoves.filter(\.isRisky)
            eligibleMoves = riskyMoves.isEmpty ? interestingMoves : riskyMoves
        } else {
            eligibleMoves = interestingMoves
        }
        let chosen = eligibleMoves[randomInt(upperBound: eligibleMoves.count)]
        return MoveSelection(candidate: chosen, usedPersonalityDeviation: true, usedMateSafeguard: usedMateSafeguard)
    }

    private func activationChance(for profile: PersonalityProfile, configuration: PersonalityConfiguration) -> Int {
        let lowComposureBonus = 100 - composure
        let base: Int
        let moodFactor: Int
        switch profile {
        case .composed: return 0
        case .irritated: base = configuration.irritatedChancePercent; moodFactor = 30
        case .tilted: base = configuration.tiltedChancePercent; moodFactor = 15
        case .meltdownProne: base = configuration.meltdownChancePercent; moodFactor = 8
        }
        return min(100, max(0, base + lowComposureBonus / moodFactor))
    }

    private func deviationLimit(for profile: PersonalityProfile, configuration: PersonalityConfiguration) -> Int {
        let configured: Int
        switch profile {
        case .composed: return 0
        case .irritated: configured = configuration.irritatedDeviationCp
        case .tilted: configured = configuration.tiltedDeviationCp
        case .meltdownProne: configured = configuration.meltdownDeviationCp
        }
        // Low composure widens the risk window slightly, but the global cap remains absolute.
        let moodAdjusted = configured * (150 - composure / 2) / 100
        return max(0, min(max(0, configuration.maximumDeviationCp), moodAdjusted))
    }

    private func isRecentReversal(_ move: Move) -> Bool {
        guard let lastOwnMove else { return false }
        return move.from == lastOwnMove.to && move.to == lastOwnMove.from
    }

    private func randomInt(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int.random(in: 0..<upperBound, using: &random)
    }
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
