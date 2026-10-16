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
        let weatherPoints = matchup.context?.weatherPoints ?? 0
        let travelEdge = matchup.context?.travelPoints ?? 0
        let modelHome = max(3, leagueAverage + homeMatchupEdge + configuration.homeFieldAdvantage + formEdge / 2 + restEdge / 2 + availabilityEdge / 2 + advancedEdge / 2 + travelEdge / 2 + weatherPoints / 2)
        let modelAway = max(3, leagueAverage + awayMatchupEdge - formEdge / 2 - restEdge / 2 - availabilityEdge / 2 - advancedEdge / 2 - travelEdge / 2 + weatherPoints / 2)
        let modelMargin = modelHome - modelAway
        let modelTotal = modelHome + modelAway
        let marketMarginWeight = matchup.bettingLine?.homeSpread == nil ? 0 : configuration.marketMarginWeight
        let marketTotalWeight = matchup.bettingLine?.total == nil ? 0 : configuration.marketTotalWeight
        let expectedMargin = modelMargin * (1 - marketMarginWeight) + (matchup.bettingLine?.homeSpread ?? modelMargin) * marketMarginWeight
        let expectedTotal = modelTotal * (1 - marketTotalWeight) + (matchup.bettingLine?.total ?? modelTotal) * marketTotalWeight
        let expectedHome = max(3, (expectedTotal + expectedMargin) / 2)
        let expectedAway = max(3, (expectedTotal - expectedMargin) / 2)
        let matchupVolatility = configuration.scoreDeviation + min(2.5, abs(homeMatchupEdge - awayMatchupEdge) * 0.12)
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
            let home = max(0, expectedHome + pace + gaussian(using: &rng) * matchupVolatility)
            let away = max(0, expectedAway + pace + gaussian(using: &rng) * matchupVolatility)
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
            ProjectionFactor(name: "QB / injuries", detail: matchup.context?.quarterbackSummary ?? matchup.home.availabilityNote ?? matchup.away.availabilityNote ?? "No confirmed availability adjustment.", homeEdge: availabilityEdge),
            ProjectionFactor(name: "Play-by-play efficiency", detail: advancedEdge == 0 ? "No external EPA/success-rate edge is currently configured." : "EPA, success, explosive-play, pressure, and turnover-regression inputs contribute \(advancedEdge.formatted(signedOneDecimal)) points.", homeEdge: advancedEdge),
            ProjectionFactor(name: "Weather / travel", detail: matchup.context?.weatherSummary ?? (matchup.context?.travelMiles.map { "Away travel: \($0.formatted()) miles." } ?? "No material weather or travel adjustment."), homeEdge: travelEdge),
            ProjectionFactor(name: "Market ensemble", detail: matchup.bettingLine == nil ? "Market inputs unavailable; projection is model-only." : "Consensus spread receives \((marketMarginWeight).formatted(.percent.precision(.fractionLength(0)))) weight and total receives \((marketTotalWeight).formatted(.percent.precision(.fractionLength(0)))) weight.", homeEdge: expectedMargin - modelMargin)
        ]
        let rawHomeProbability = homeWinCredits / Double(count)
        return Prediction(
            matchup: matchup,
            homeScore: homeTotal / Double(count),
            awayScore: awayTotal / Double(count),
            homeWinProbability: calibrated(rawHomeProbability),
            simulations: count,
            simulationSummary: summary, modelVersion: "MVP 0.8", factors: factors,
            modelOnlyHomeSpread: modelMargin, modelOnlyTotal: modelTotal
        )
    }

    private func calibrated(_ probability: Double) -> Double {
        let points = configuration.calibrationPoints.sorted { $0.predicted < $1.predicted }
        guard !points.isEmpty else { return probability }
        guard let upperIndex = points.firstIndex(where: { $0.predicted >= probability }) else {
            return min(0.98, max(0.02, points.last!.observed))
        }
        guard upperIndex > 0 else { return min(0.98, max(0.02, points[0].observed)) }
        let lower = points[upperIndex - 1], upper = points[upperIndex]
        let width = max(0.0001, upper.predicted - lower.predicted)
        let weight = (probability - lower.predicted) / width
        return min(0.98, max(0.02, lower.observed + (upper.observed - lower.observed) * weight))
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
            ModelConfiguration(homeFieldAdvantage: 1.2, ratingWeight: 0.45, formWeight: 0.12, scoreDeviation: 8.5, marketMarginWeight: 0.25, marketTotalWeight: 0.15),
            .baseline,
            ModelConfiguration(homeFieldAdvantage: 1.8, ratingWeight: 0.55, formWeight: 0.22, scoreDeviation: 7.8, marketMarginWeight: 0.45, marketTotalWeight: 0.30)
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
        let trainingGrades = grades(training, selected)
        let calibrated = ModelConfiguration(homeFieldAdvantage: selected.homeFieldAdvantage,
                                            ratingWeight: selected.ratingWeight,
                                            formWeight: selected.formWeight,
                                            scoreDeviation: selected.scoreDeviation,
                                            calibrationPoints: ProbabilityCalibrator.fit(trainingGrades),
                                            marketMarginWeight: selected.marketMarginWeight,
                                            marketTotalWeight: selected.marketTotalWeight)
        var rollingGrades: [GradedPrediction] = []
        var rollingSeasons: [Int] = []
        for heldOut in seasons.dropFirst() {
            let prior = games.filter { $0.season < heldOut }
            let fold = games.filter { $0.season == heldOut }
            guard !prior.isEmpty, !fold.isEmpty else { continue }
            let foldPoints = ProbabilityCalibrator.fit(grades(prior, selected))
            let foldConfiguration = ModelConfiguration(homeFieldAdvantage: selected.homeFieldAdvantage,
                ratingWeight: selected.ratingWeight, formWeight: selected.formWeight,
                scoreDeviation: selected.scoreDeviation, calibrationPoints: foldPoints,
                marketMarginWeight: selected.marketMarginWeight, marketTotalWeight: selected.marketTotalWeight)
            rollingGrades.append(contentsOf: grades(fold, foldConfiguration))
            rollingSeasons.append(heldOut)
        }
        return ModelValidationReport(configuration: calibrated, trainingGames: training.count,
                                     validationSeason: validationSeason, grades: grades(validation, calibrated),
                                     rollingGrades: rollingGrades, rollingSeasons: rollingSeasons)
    }
}

public enum ProbabilityCalibrator {
    public static func fit(_ grades: [GradedPrediction]) -> [CalibrationPoint] {
        struct Block { var predicted: Double; var observed: Double; var count: Int }
        var blocks: [Block] = stride(from: 0.0, to: 1.0, by: 0.1).compactMap { lower in
            let selected = grades.filter { $0.prediction.homeWinProbability >= lower && $0.prediction.homeWinProbability < lower + 0.1 }
            guard !selected.isEmpty else { return nil }
            let count = Double(selected.count)
            let predicted = selected.map { $0.prediction.homeWinProbability }.reduce(0, +) / count
            let outcomes = selected.map { $0.actualHomeScore > $0.actualAwayScore ? 1.0 : $0.actualHomeScore == $0.actualAwayScore ? 0.5 : 0.0 }
            // Modest prior shrinkage avoids extreme calibration from thin bins.
            let observed = (outcomes.reduce(0, +) + predicted * 4) / (count + 4)
            return Block(predicted: predicted, observed: observed, count: selected.count)
        }
        var index = 0
        while index + 1 < blocks.count {
            if blocks[index].observed <= blocks[index + 1].observed { index += 1; continue }
            let lhs = blocks[index], rhs = blocks[index + 1]
            let total = lhs.count + rhs.count
            blocks[index] = Block(predicted: (lhs.predicted * Double(lhs.count) + rhs.predicted * Double(rhs.count)) / Double(total),
                                  observed: (lhs.observed * Double(lhs.count) + rhs.observed * Double(rhs.count)) / Double(total),
                                  count: total)
            blocks.remove(at: index + 1)
            if index > 0 { index -= 1 }
        }
        return blocks.map { CalibrationPoint(predicted: $0.predicted, observed: $0.observed) }
    }
}
