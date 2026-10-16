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
    public let calibrationPoints: [CalibrationPoint]
    public let marketMarginWeight: Double
    public let marketTotalWeight: Double

    public init(homeFieldAdvantage: Double = 1.6, ratingWeight: Double = 0.5,
                formWeight: Double = 0.18, scoreDeviation: Double = 8.2,
                calibrationPoints: [CalibrationPoint] = [], marketMarginWeight: Double = 0.35,
                marketTotalWeight: Double = 0.20) {
        self.homeFieldAdvantage = homeFieldAdvantage
        self.ratingWeight = ratingWeight
        self.formWeight = formWeight
        self.scoreDeviation = scoreDeviation
        self.calibrationPoints = calibrationPoints
        self.marketMarginWeight = marketMarginWeight
        self.marketTotalWeight = marketTotalWeight
    }

    public static let baseline = ModelConfiguration()
}

public struct CalibrationPoint: Codable, Hashable, Sendable {
    public let predicted: Double
    public let observed: Double
    public init(predicted: Double, observed: Double) {
        self.predicted = predicted
        self.observed = observed
    }
}

public struct BettingLine: Codable, Hashable, Sendable {
    /// nflverse convention: positive means the designated home team is favored.
    public let homeSpread: Double?
    public let total: Double?
    public let homeMoneyline: Int?
    public let awayMoneyline: Int?
    public let source: String
    public let openingHomeSpread: Double?
    public let openingTotal: Double?
    public let closingHomeSpread: Double?
    public let closingTotal: Double?

    public init(homeSpread: Double? = nil, total: Double? = nil, homeMoneyline: Int? = nil,
                awayMoneyline: Int? = nil, source: String = "nflverse consensus",
                openingHomeSpread: Double? = nil, openingTotal: Double? = nil,
                closingHomeSpread: Double? = nil, closingTotal: Double? = nil) {
        self.homeSpread = homeSpread
        self.total = total
        self.homeMoneyline = homeMoneyline
        self.awayMoneyline = awayMoneyline
        self.source = source
        self.openingHomeSpread = openingHomeSpread
        self.openingTotal = openingTotal
        self.closingHomeSpread = closingHomeSpread
        self.closingTotal = closingTotal
    }
}

public struct GameContext: Codable, Hashable, Sendable {
    public let weatherSummary: String?
    public let weatherPoints: Double
    public let travelMiles: Int?
    public let travelPoints: Double
    public let quarterbackSummary: String?

    public init(weatherSummary: String? = nil, weatherPoints: Double = 0,
                travelMiles: Int? = nil, travelPoints: Double = 0,
                quarterbackSummary: String? = nil) {
        self.weatherSummary = weatherSummary
        self.weatherPoints = weatherPoints
        self.travelMiles = travelMiles
        self.travelPoints = travelPoints
        self.quarterbackSummary = quarterbackSummary
    }
}

public struct Matchup: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let week: Int
    public let kickoff: Date
    public let away: Team
    public let home: Team
    public let bettingLine: BettingLine?
    public let context: GameContext?

    public init(id: UUID = UUID(), week: Int, kickoff: Date, away: Team, home: Team,
                bettingLine: BettingLine? = nil, context: GameContext? = nil) {
        self.id = id
        self.week = week
        self.kickoff = kickoff
        self.away = away
        self.home = home
        self.bettingLine = bettingLine
        self.context = context
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
    public let previousHomeWinProbability: Double?
    public let previousHomeScore: Double?
    public let previousAwayScore: Double?
    public let modelOnlyHomeSpread: Double?
    public let modelOnlyTotal: Double?
    public let previousMarketHomeSpread: Double?
    public let previousMarketTotal: Double?

    public var predictedWinner: Team { homeWinProbability >= 0.5 ? matchup.home : matchup.away }
    public var confidence: Double { max(homeWinProbability, 1 - homeWinProbability) }

    public init(id: UUID = UUID(), matchup: Matchup, homeScore: Double, awayScore: Double, homeWinProbability: Double, simulations: Int, generatedAt: Date = .now, simulationSummary: SimulationSummary? = nil, modelVersion: String? = "MVP 0.9", dataSourceUpdatedAt: Date? = .now, recalculatedAt: Date? = .now, factors: [ProjectionFactor]? = nil, previousHomeWinProbability: Double? = nil, previousHomeScore: Double? = nil, previousAwayScore: Double? = nil, modelOnlyHomeSpread: Double? = nil, modelOnlyTotal: Double? = nil, previousMarketHomeSpread: Double? = nil, previousMarketTotal: Double? = nil) {
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
        self.previousHomeWinProbability = previousHomeWinProbability
        self.previousHomeScore = previousHomeScore
        self.previousAwayScore = previousAwayScore
        self.modelOnlyHomeSpread = modelOnlyHomeSpread
        self.modelOnlyTotal = modelOnlyTotal
        self.previousMarketHomeSpread = previousMarketHomeSpread
        self.previousMarketTotal = previousMarketTotal
    }

    public var projectedHomeSpread: Double { homeScore - awayScore }
    public var projectedTotal: Double { homeScore + awayScore }

    public var marketComparison: String? {
        guard let line = matchup.bettingLine else { return nil }
        var parts: [String] = []
        if let spread = line.homeSpread {
            let difference = projectedHomeSpread - spread
            let projectedSide = projectedHomeSpread >= 0 ? matchup.home.abbreviation : matchup.away.abbreviation
            let marketSide = spread >= 0 ? matchup.home.abbreviation : matchup.away.abbreviation
            parts.append("Projected \(projectedSide) by \(abs(projectedHomeSpread).formatted(.number.precision(.fractionLength(1)))) vs market \(marketSide) by \(abs(spread).formatted(.number.precision(.fractionLength(1)))) (home-margin edge \(difference.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))) pts)")
        }
        if let total = line.total {
            parts.append("Projected total \(projectedTotal.formatted(.number.precision(.fractionLength(1)))) vs market \(total.formatted(.number.precision(.fractionLength(1))))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public var movementSummary: String? {
        guard let previousHomeWinProbability else { return nil }
        let delta = homeWinProbability - previousHomeWinProbability
        guard abs(delta) >= 0.005 else { return "Unchanged from the prior forecast." }
        let team = delta > 0 ? matchup.home.abbreviation : matchup.away.abbreviation
        return "\(team) win probability moved \(abs(delta).formatted(.percent.precision(.fractionLength(1)))) since the prior refresh."
    }

    public var lineMovementSummary: String? {
        guard let line = matchup.bettingLine else { return nil }
        let priorSpread = line.openingHomeSpread ?? previousMarketHomeSpread
        let priorTotal = line.openingTotal ?? previousMarketTotal
        var parts: [String] = []
        if let priorSpread, let current = line.homeSpread, abs(current - priorSpread) >= 0.1 {
            parts.append("spread \(priorSpread.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))) → \(current.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))))")
        }
        if let priorTotal, let current = line.total, abs(current - priorTotal) >= 0.1 {
            parts.append("total \(priorTotal.formatted(.number.precision(.fractionLength(1)))) → \(current.formatted(.number.precision(.fractionLength(1))))")
        }
        return parts.isEmpty ? nil : "Market movement: " + parts.joined(separator: " · ")
    }

    public var reviewFlag: String? {
        guard let line = matchup.bettingLine else { return nil }
        let marginGap = line.homeSpread.map { abs(projectedHomeSpread - $0) } ?? 0
        let totalGap = line.total.map { abs(projectedTotal - $0) } ?? 0
        guard marginGap >= 4 || totalGap >= 6 else { return nil }
        var reasons: [String] = []
        if marginGap >= 4 { reasons.append("side differs by \(marginGap.formatted(.number.precision(.fractionLength(1)))) points") }
        if totalGap >= 6 { reasons.append("total differs by \(totalGap.formatted(.number.precision(.fractionLength(1)))) points") }
        return "Review recommended: " + reasons.joined(separator: " and ") + "."
    }


    public var confidenceExplanation: String {
        let edge = abs(homeScore - awayScore)
        if confidence < 0.55 { return "Near toss-up: the projected scoring edge is only \(edge.formatted(.number.precision(.fractionLength(1)))) points." }
        if confidence < 0.65 { return "Moderate edge: team-strength signals favor \(predictedWinner.abbreviation), but outcome variance remains meaningful." }
        return "Stronger edge: multiple model factors favor \(predictedWinner.abbreviation) by \(edge.formatted(.number.precision(.fractionLength(1)))) projected points."
    }

    public var bettingRecommendations: [BetRecommendation] {
        guard let line = matchup.bettingLine else { return [] }
        var recommendations: [BetRecommendation] = []
        if let marketMargin = line.homeSpread {
            let edge = projectedHomeSpread - marketMargin
            let team = edge >= 0 ? matchup.home.abbreviation : matchup.away.abbreviation
            let conventionalLine = edge >= 0 ? -marketMargin : marketMargin
            let label = "\(team) \(conventionalLine.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))))"
            recommendations.append(BetRecommendation(kind: .spread, selection: label,
                edge: abs(edge), strength: BetStrength(edge: abs(edge), lean: 2.5, strong: 4.5),
                rationale: "Projected margin differs from consensus by \(abs(edge).formatted(.number.precision(.fractionLength(1)))) points."))
        }
        if let marketTotal = line.total {
            let edge = projectedTotal - marketTotal
            let selection = edge >= 0 ? "Over \(marketTotal.formatted(.number.precision(.fractionLength(1))))" : "Under \(marketTotal.formatted(.number.precision(.fractionLength(1))))"
            recommendations.append(BetRecommendation(kind: .total, selection: selection,
                edge: abs(edge), strength: BetStrength(edge: abs(edge), lean: 3.5, strong: 6.0),
                rationale: "Projected total is \(abs(edge).formatted(.number.precision(.fractionLength(1)))) points \(edge >= 0 ? "above" : "below") consensus."))
        }
        if let homeOdds = line.homeMoneyline, let awayOdds = line.awayMoneyline {
            let homeRaw = Self.impliedProbability(homeOdds), awayRaw = Self.impliedProbability(awayOdds)
            let total = homeRaw + awayRaw
            let marketHome = total > 0 ? homeRaw / total : 0.5
            let homeEdge = homeWinProbability - marketHome
            let chooseHome = homeEdge >= 0
            let edge = abs(homeEdge)
            let odds = chooseHome ? homeOdds : awayOdds
            recommendations.append(BetRecommendation(kind: .moneyline,
                selection: "\(chooseHome ? matchup.home.abbreviation : matchup.away.abbreviation) moneyline \(odds.formatted(.number.sign(strategy: .always())))",
                edge: edge * 100, strength: BetStrength(edge: edge, lean: 0.045, strong: 0.075),
                rationale: "No-vig win probability edge is \(edge.formatted(.percent.precision(.fractionLength(1))))."))
        }
        return recommendations.sorted { lhs, rhs in
            if lhs.strength != rhs.strength { return lhs.strength.sortOrder > rhs.strength.sortOrder }
            return lhs.edge > rhs.edge
        }
    }

    private static func impliedProbability(_ americanOdds: Int) -> Double {
        americanOdds < 0 ? Double(-americanOdds) / Double(-americanOdds + 100) : 100 / Double(americanOdds + 100)
    }
}

public enum BetKind: String, Codable, Hashable, Sendable { case spread = "Spread"; case total = "Total"; case moneyline = "Moneyline" }
public enum BetStrength: String, Codable, Hashable, Sendable {
    case pass = "Pass", lean = "Lean", strong = "Strong edge"
    init(edge: Double, lean: Double, strong: Double) { self = edge >= strong ? .strong : edge >= lean ? .lean : .pass }
    var sortOrder: Int { self == .strong ? 2 : self == .lean ? 1 : 0 }
}

public struct BetRecommendation: Identifiable, Codable, Hashable, Sendable {
    public let kind: BetKind
    public let selection: String
    public let edge: Double
    public let strength: BetStrength
    public let rationale: String
    public var id: String { "\(kind.rawValue)-\(selection)" }
    public init(kind: BetKind, selection: String, edge: Double, strength: BetStrength, rationale: String) {
        self.kind = kind; self.selection = selection; self.edge = edge; self.strength = strength; self.rationale = rationale
    }
}

public struct BettingPerformance: Sendable, Hashable {
    public let graded: Int
    public let wins: Int
    public let losses: Int
    public let pushes: Int
    public var winRate: Double { wins + losses == 0 ? 0 : Double(wins) / Double(wins + losses) }
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

    public static func bettingPerformance(_ grades: [GradedPrediction], kind: BetKind? = nil, strongOnly: Bool = false) -> BettingPerformance {
        var wins = 0, losses = 0, pushes = 0
        for grade in grades {
            let prediction = grade.prediction
            let actualMargin = Double(grade.actualHomeScore - grade.actualAwayScore)
            let actualTotal = Double(grade.actualHomeScore + grade.actualAwayScore)
            for recommendation in prediction.bettingRecommendations where recommendation.strength != .pass && (!strongOnly || recommendation.strength == .strong) && (kind == nil || recommendation.kind == kind) {
                let result: Int?
                switch recommendation.kind {
                case .spread:
                    guard let market = prediction.matchup.bettingLine?.homeSpread else { continue }
                    let choseHome = prediction.projectedHomeSpread - market >= 0
                    let difference = actualMargin - market
                    result = difference == 0 ? 0 : ((difference > 0) == choseHome ? 1 : -1)
                case .total:
                    guard let market = prediction.matchup.bettingLine?.total else { continue }
                    let choseOver = prediction.projectedTotal >= market
                    let difference = actualTotal - market
                    result = difference == 0 ? 0 : ((difference > 0) == choseOver ? 1 : -1)
                case .moneyline:
                    let choseHome = recommendation.selection.hasPrefix(prediction.matchup.home.abbreviation + " ")
                    guard grade.actualHomeScore != grade.actualAwayScore else { result = 0; break }
                    result = ((grade.actualHomeScore > grade.actualAwayScore) == choseHome) ? 1 : -1
                }
                if result == 1 { wins += 1 } else if result == -1 { losses += 1 } else { pushes += 1 }
            }
        }
        return BettingPerformance(graded: wins + losses + pushes, wins: wins, losses: losses, pushes: pushes)
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
    public let rollingGrades: [GradedPrediction]
    public let rollingSeasons: [Int]

    public init(configuration: ModelConfiguration, trainingGames: Int, validationSeason: Int, grades: [GradedPrediction], rollingGrades: [GradedPrediction] = [], rollingSeasons: [Int] = []) {
        self.configuration = configuration
        self.trainingGames = trainingGames
        self.validationSeason = validationSeason
        self.grades = grades
        self.rollingGrades = rollingGrades
        self.rollingSeasons = rollingSeasons
    }
}
