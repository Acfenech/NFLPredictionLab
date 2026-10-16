import Foundation

public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public struct ForecastingEngine: Sendable {
    public let homeFieldAdvantage: Double
    public init(homeFieldAdvantage: Double = 1.6) { self.homeFieldAdvantage = homeFieldAdvantage }

    public func predict(_ matchup: Matchup, simulations: Int = 10_000, seed: UInt64 = 42) -> Prediction {
        let count = max(simulations, 1)
        let leagueAverage = 22.5
        let expectedHome = max(3, leagueAverage + (matchup.home.offensiveRating - matchup.away.defensiveRating) / 2 + homeFieldAdvantage)
        let expectedAway = max(3, leagueAverage + (matchup.away.offensiveRating - matchup.home.defensiveRating) / 2)
        var rng = SeededGenerator(seed: seed)
        var homeWinCredits = 0.0
        var homeTotal = 0.0
        var awayTotal = 0.0
        var homeScores: [Double] = []
        var awayScores: [Double] = []
        var scorePairs: [String: Int] = [:]
        homeScores.reserveCapacity(count)
        awayScores.reserveCapacity(count)

        for _ in 0..<count {
            // A shared pace factor introduces realistic score correlation; team-specific
            // variation then determines the result.
            let pace = gaussian(using: &rng) * 4.0
            let home = max(0, expectedHome + pace + gaussian(using: &rng) * 8.2)
            let away = max(0, expectedAway + pace + gaussian(using: &rng) * 8.2)
            homeTotal += home
            awayTotal += away
            homeScores.append(home)
            awayScores.append(away)
            scorePairs["\(Int(away.rounded()))-\(Int(home.rounded()))", default: 0] += 1
            if home > away { homeWinCredits += 1 }
            else if home == away { homeWinCredits += 0.5 }
        }

        homeScores.sort()
        awayScores.sort()
        let lowIndex = Int(Double(count - 1) * 0.10)
        let highIndex = Int(Double(count - 1) * 0.90)
        let likely = scorePairs.max { $0.value < $1.value }?.key.split(separator: "-").compactMap { Int($0) } ?? [0, 0]
        let summary = SimulationSummary(
            awayLow: awayScores[lowIndex], awayHigh: awayScores[highIndex],
            homeLow: homeScores[lowIndex], homeHigh: homeScores[highIndex],
            mostLikelyAwayScore: likely[0], mostLikelyHomeScore: likely[1]
        )

        return Prediction(
            matchup: matchup,
            homeScore: homeTotal / Double(count),
            awayScore: awayTotal / Double(count),
            homeWinProbability: homeWinCredits / Double(count),
            simulations: count,
            simulationSummary: summary
        )
    }

    private func gaussian<R: RandomNumberGenerator>(using rng: inout R) -> Double {
        let u1 = max(Double.random(in: 0..<1, using: &rng), .leastNonzeroMagnitude)
        let u2 = Double.random(in: 0..<1, using: &rng)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}
