import Foundation

public struct Team: Codable, Hashable, Sendable {
    public let abbreviation: String
    public let name: String
    public let offensiveRating: Double
    public let defensiveRating: Double
    public let recentForm: Double?
    public let restDays: Int?
    public let availabilityAdjustment: Double?
    public let availabilityNote: String?
    public let advancedEfficiency: Double?

    public init(abbreviation: String, name: String, offensiveRating: Double, defensiveRating: Double,
                recentForm: Double? = nil, restDays: Int? = nil,
                availabilityAdjustment: Double? = nil, availabilityNote: String? = nil,
                advancedEfficiency: Double? = nil) {
        self.abbreviation = abbreviation
        self.name = name
        self.offensiveRating = offensiveRating
        self.defensiveRating = defensiveRating
        self.recentForm = recentForm
        self.restDays = restDays
        self.availabilityAdjustment = availabilityAdjustment
        self.availabilityNote = availabilityNote
        self.advancedEfficiency = advancedEfficiency
    }
}

public struct ProjectionFactor: Codable, Identifiable, Hashable, Sendable {
    public let name: String
    public let detail: String
    public let homeEdge: Double
    public var id: String { name }

    public init(name: String, detail: String, homeEdge: Double) {
        self.name = name
        self.detail = detail
        self.homeEdge = homeEdge
    }
}

public struct ModelConfiguration: Codable, Hashable, Sendable {
    public let homeFieldAdvantage: Double
    public let ratingWeight: Double
    public let formWeight: Double
    public let scoreDeviation: Double

    public init(homeFieldAdvantage: Double = 1.6, ratingWeight: Double = 0.5,
                formWeight: Double = 0.18, scoreDeviation: Double = 8.2) {
        self.homeFieldAdvantage = homeFieldAdvantage
        self.ratingWeight = ratingWeight
        self.formWeight = formWeight
        self.scoreDeviation = scoreDeviation
    }

    public static let baseline = ModelConfiguration()
}

public struct Matchup: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let week: Int
    public let kickoff: Date
    public let away: Team
    public let home: Team

    public init(id: UUID = UUID(), week: Int, kickoff: Date, away: Team, home: Team) {
        self.id = id
        self.week = week
        self.kickoff = kickoff
        self.away = away
        self.home = home
    }

    public var gameKey: String {
        "\(week)-\(away.abbreviation)-\(home.abbreviation)-\(Int(kickoff.timeIntervalSince1970))"
    }
}

public struct Prediction: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let matchup: Matchup
    public let homeScore: Double
    public let awayScore: Double
    public let homeWinProbability: Double
    public let simulations: Int
    public let generatedAt: Date
    public let simulationSummary: SimulationSummary?
    public let modelVersion: String?
    public let dataSourceUpdatedAt: Date?
    public let recalculatedAt: Date?
    public let factors: [ProjectionFactor]?

    public var predictedWinner: Team { homeWinProbability >= 0.5 ? matchup.home : matchup.away }
    public var confidence: Double { max(homeWinProbability, 1 - homeWinProbability) }

    public init(id: UUID = UUID(), matchup: Matchup, homeScore: Double, awayScore: Double, homeWinProbability: Double, simulations: Int, generatedAt: Date = .now, simulationSummary: SimulationSummary? = nil, modelVersion: String? = "MVP 0.4", dataSourceUpdatedAt: Date? = .now, recalculatedAt: Date? = .now, factors: [ProjectionFactor]? = nil) {
        self.id = id
        self.matchup = matchup
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.homeWinProbability = homeWinProbability
        self.simulations = simulations
        self.generatedAt = generatedAt
        self.simulationSummary = simulationSummary
        self.modelVersion = modelVersion
        self.dataSourceUpdatedAt = dataSourceUpdatedAt
        self.recalculatedAt = recalculatedAt
        self.factors = factors
    }


    public var confidenceExplanation: String {
        let edge = abs(homeScore - awayScore)
        if confidence < 0.55 { return "Near toss-up: the projected scoring edge is only \(edge.formatted(.number.precision(.fractionLength(1)))) points." }
        if confidence < 0.65 { return "Moderate edge: team-strength signals favor \(predictedWinner.abbreviation), but outcome variance remains meaningful." }
        return "Stronger edge: multiple model factors favor \(predictedWinner.abbreviation) by \(edge.formatted(.number.precision(.fractionLength(1)))) projected points."
    }
}

public struct SimulationSummary: Codable, Hashable, Sendable {
    public let awayLow: Double
    public let awayHigh: Double
    public let homeLow: Double
    public let homeHigh: Double
    public let mostLikelyAwayScore: Int
    public let mostLikelyHomeScore: Int

    public init(awayLow: Double, awayHigh: Double, homeLow: Double, homeHigh: Double,
                mostLikelyAwayScore: Int, mostLikelyHomeScore: Int) {
        self.awayLow = awayLow
        self.awayHigh = awayHigh
        self.homeLow = homeLow
        self.homeHigh = homeHigh
        self.mostLikelyAwayScore = mostLikelyAwayScore
        self.mostLikelyHomeScore = mostLikelyHomeScore
    }
}

public struct GradedPrediction: Codable, Identifiable, Sendable {
    public let id: UUID
    public let prediction: Prediction
    public let actualHomeScore: Int
    public let actualAwayScore: Int

    public init(id: UUID = UUID(), prediction: Prediction, actualHomeScore: Int, actualAwayScore: Int) {
        self.id = id
        self.prediction = prediction
        self.actualHomeScore = actualHomeScore
        self.actualAwayScore = actualAwayScore
    }

    public var winnerCorrect: Bool {
        actualHomeScore != actualAwayScore &&
        (prediction.homeWinProbability >= 0.5) == (actualHomeScore > actualAwayScore)
    }

    public var meanAbsoluteScoreError: Double {
        (abs(prediction.homeScore - Double(actualHomeScore)) + abs(prediction.awayScore - Double(actualAwayScore))) / 2
    }

    /// Equal weighting: winner correctness and normalized score accuracy each contribute 50%.
    public var balancedAccuracy: Double {
        let winnerComponent = winnerCorrect ? 1.0 : 0.0
        let scoreComponent = max(0, 1 - meanAbsoluteScoreError / 21)
        return 0.5 * winnerComponent + 0.5 * scoreComponent
    }

    public var brierScore: Double {
        let outcome = actualHomeScore > actualAwayScore ? 1.0 : actualHomeScore == actualAwayScore ? 0.5 : 0.0
        return pow(prediction.homeWinProbability - outcome, 2)
    }
}

public struct BacktestSummary: Sendable, Hashable {
    public let games: Int
    public let winnerAccuracy: Double
    public let meanAbsoluteScoreError: Double
    public let meanBrierScore: Double
    public let balancedAccuracy: Double
}

public struct CalibrationBucket: Identifiable, Sendable, Hashable {
    public let lowerBound: Double
    public let upperBound: Double
    public let games: Int
    public let predictedRate: Double
    public let observedRate: Double
    public var id: Double { lowerBound }
}

public enum Backtester {
    public static func summarize(_ grades: [GradedPrediction]) -> BacktestSummary? {
        guard !grades.isEmpty else { return nil }
        let count = Double(grades.count)
        return BacktestSummary(
            games: grades.count,
            winnerAccuracy: Double(grades.filter(\.winnerCorrect).count) / count,
            meanAbsoluteScoreError: grades.map(\.meanAbsoluteScoreError).reduce(0, +) / count,
            meanBrierScore: grades.map(\.brierScore).reduce(0, +) / count,
            balancedAccuracy: grades.map(\.balancedAccuracy).reduce(0, +) / count
        )
    }

    public static func calibration(_ grades: [GradedPrediction]) -> [CalibrationBucket] {
        stride(from: 0.5, to: 1.0, by: 0.1).compactMap { lower in
            let upper = min(1, lower + 0.1)
            let selected = grades.filter { grade in
                let confidence = grade.prediction.confidence
                return confidence >= lower && (upper == 1 ? confidence <= upper : confidence < upper)
            }
            guard !selected.isEmpty else { return nil }
            return CalibrationBucket(
                lowerBound: lower, upperBound: upper, games: selected.count,
                predictedRate: selected.map { $0.prediction.confidence }.reduce(0, +) / Double(selected.count),
                observedRate: Double(selected.filter(\.winnerCorrect).count) / Double(selected.count)
            )
        }
    }
}

public struct GameResult: Codable, Hashable, Sendable {
    public let awayAbbreviation: String
    public let homeAbbreviation: String
    public let awayScore: Int
    public let homeScore: Int

    public init(awayAbbreviation: String, homeAbbreviation: String, awayScore: Int, homeScore: Int) {
        self.awayAbbreviation = awayAbbreviation
        self.homeAbbreviation = homeAbbreviation
        self.awayScore = awayScore
        self.homeScore = homeScore
    }
}

public struct HistoricalGame: Sendable, Hashable {
    public let season: Int
    public let matchup: Matchup
    public let result: GameResult

    public init(season: Int, matchup: Matchup, result: GameResult) {
        self.season = season
        self.matchup = matchup
        self.result = result
    }
}

public struct ModelValidationReport: Sendable {
    public let configuration: ModelConfiguration
    public let trainingGames: Int
    public let validationSeason: Int
    public let grades: [GradedPrediction]

    public init(configuration: ModelConfiguration, trainingGames: Int, validationSeason: Int, grades: [GradedPrediction]) {
        self.configuration = configuration
        self.trainingGames = trainingGames
        self.validationSeason = validationSeason
        self.grades = grades
    }
}
