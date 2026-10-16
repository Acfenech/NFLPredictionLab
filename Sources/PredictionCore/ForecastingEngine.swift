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
    public let configuration: ModelConfiguration
    public init(homeFieldAdvantage: Double = 1.6) {
        configuration = ModelConfiguration(homeFieldAdvantage: homeFieldAdvantage)
    }
    public init(configuration: ModelConfiguration) { self.configuration = configuration }

    public func predict(_ matchup: Matchup, simulations: Int = 10_000, seed: UInt64 = 42) -> Prediction {
        let count = max(simulations, 1)
        let leagueAverage = 22.5
        let homeMatchupEdge = (matchup.home.offensiveRating - matchup.away.defensiveRating) * configuration.ratingWeight
        let awayMatchupEdge = (matchup.away.offensiveRating - matchup.home.defensiveRating) * configuration.ratingWeight
        let formEdge = ((matchup.home.recentForm ?? 0) - (matchup.away.recentForm ?? 0)) * configuration.formWeight
        let restEdge = Double((matchup.home.restDays ?? 7) - (matchup.away.restDays ?? 7)) * 0.12
        let availabilityEdge = (matchup.home.availabilityAdjustment ?? 0) - (matchup.away.availabilityAdjustment ?? 0)
        let advancedEdge = (matchup.home.advancedEfficiency ?? 0) - (matchup.away.advancedEfficiency ?? 0)
        let expectedHome = max(3, leagueAverage + homeMatchupEdge + configuration.homeFieldAdvantage + formEdge / 2 + restEdge / 2 + availabilityEdge / 2 + advancedEdge / 2)
        let expectedAway = max(3, leagueAverage + awayMatchupEdge - formEdge / 2 - restEdge / 2 - availabilityEdge / 2 - advancedEdge / 2)
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
            let home = max(0, expectedHome + pace + gaussian(using: &rng) * configuration.scoreDeviation)
            let away = max(0, expectedAway + pace + gaussian(using: &rng) * configuration.scoreDeviation)
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

        let signedOneDecimal = FloatingPointFormatStyle<Double>.number.sign(strategy: .always()).precision(.fractionLength(1))
        let factors = [
            ProjectionFactor(name: "Offense vs. defense", detail: "\(matchup.home.abbreviation) matchup edge \(homeMatchupEdge.formatted(signedOneDecimal)); \(matchup.away.abbreviation) \(awayMatchupEdge.formatted(signedOneDecimal))", homeEdge: homeMatchupEdge - awayMatchupEdge),
            ProjectionFactor(name: "Recent form", detail: "Recency-weighted scoring margin contributes \(formEdge.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))) points to the home edge.", homeEdge: formEdge),
            ProjectionFactor(name: "Rest", detail: "Rest differential contributes \(restEdge.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))) points.", homeEdge: restEdge),
            ProjectionFactor(name: "Home field", detail: "Home-field baseline contributes \(configuration.homeFieldAdvantage.formatted(.number.precision(.fractionLength(1)))) points.", homeEdge: configuration.homeFieldAdvantage),
            ProjectionFactor(name: "QB / injuries", detail: matchup.home.availabilityNote ?? matchup.away.availabilityNote ?? "No confirmed availability adjustment.", homeEdge: availabilityEdge)
            ,ProjectionFactor(name: "Play-by-play efficiency", detail: advancedEdge == 0 ? "No external EPA/success-rate edge is currently configured." : "EPA, success, explosive-play, pressure, and turnover-regression inputs contribute \(advancedEdge.formatted(signedOneDecimal)) points.", homeEdge: advancedEdge)
        ]
        return Prediction(
            matchup: matchup,
            homeScore: homeTotal / Double(count),
            awayScore: awayTotal / Double(count),
            homeWinProbability: homeWinCredits / Double(count),
            simulations: count,
            simulationSummary: summary, modelVersion: "MVP 0.4", factors: factors
        )
    }

    private func gaussian<R: RandomNumberGenerator>(using rng: inout R) -> Double {
        let u1 = max(Double.random(in: 0..<1, using: &rng), .leastNonzeroMagnitude)
        let u2 = Double.random(in: 0..<1, using: &rng)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

public enum ModelTrainer {
    public static func trainAndValidate(_ games: [HistoricalGame]) -> ModelValidationReport? {
        let seasons = Set(games.map(\.season)).sorted()
        guard seasons.count >= 2, let validationSeason = seasons.last else { return nil }
        let training = games.filter { $0.season < validationSeason }
        let validation = games.filter { $0.season == validationSeason }
        guard !training.isEmpty, !validation.isEmpty else { return nil }
        let candidates = [
            ModelConfiguration(homeFieldAdvantage: 1.2, ratingWeight: 0.45, formWeight: 0.12, scoreDeviation: 8.5),
            .baseline,
            ModelConfiguration(homeFieldAdvantage: 1.8, ratingWeight: 0.55, formWeight: 0.22, scoreDeviation: 7.8)
        ]
        func grades(_ sample: [HistoricalGame], _ config: ModelConfiguration) -> [GradedPrediction] {
            let engine = ForecastingEngine(configuration: config)
            return sample.enumerated().map { index, game in
                let prediction = engine.predict(game.matchup, simulations: 600, seed: UInt64(index + 1))
                return GradedPrediction(prediction: prediction, actualHomeScore: game.result.homeScore, actualAwayScore: game.result.awayScore)
            }
        }
        let selected = candidates.max { lhs, rhs in
            (Backtester.summarize(grades(training, lhs))?.balancedAccuracy ?? 0) <
            (Backtester.summarize(grades(training, rhs))?.balancedAccuracy ?? 0)
        } ?? .baseline
        return ModelValidationReport(configuration: selected, trainingGames: training.count,
                                     validationSeason: validationSeason, grades: grades(validation, selected))
    }
}
