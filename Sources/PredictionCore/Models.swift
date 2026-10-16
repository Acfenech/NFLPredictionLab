import Foundation

public struct Team: Codable, Hashable, Sendable {
    public let abbreviation: String
    public let name: String
    public let offensiveRating: Double
    public let defensiveRating: Double

    public init(abbreviation: String, name: String, offensiveRating: Double, defensiveRating: Double) {
        self.abbreviation = abbreviation
        self.name = name
        self.offensiveRating = offensiveRating
        self.defensiveRating = defensiveRating
    }
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

    public var predictedWinner: Team { homeWinProbability >= 0.5 ? matchup.home : matchup.away }
    public var confidence: Double { max(homeWinProbability, 1 - homeWinProbability) }

    public init(id: UUID = UUID(), matchup: Matchup, homeScore: Double, awayScore: Double, homeWinProbability: Double, simulations: Int, generatedAt: Date = .now, simulationSummary: SimulationSummary? = nil) {
        self.id = id
        self.matchup = matchup
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.homeWinProbability = homeWinProbability
        self.simulations = simulations
        self.generatedAt = generatedAt
        self.simulationSummary = simulationSummary
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
