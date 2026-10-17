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

public enum OddsMath {
    public static func decimal(fromAmerican odds: Int) -> Double? {
        guard odds != 0 else { return nil }
        return odds > 0 ? 1 + Double(odds) / 100 : 1 + 100 / Double(abs(odds))
    }

    public static func american(fromDecimal odds: Double) -> Int? {
        guard odds > 1 else { return nil }
        return odds >= 2 ? Int(((odds - 1) * 100).rounded()) : -Int((100 / (odds - 1)).rounded())
    }

    public static func impliedProbability(american odds: Int) -> Double? {
        decimal(fromAmerican: odds).map { 1 / $0 }
    }

    public static func profit(stake: Double, american odds: Int) -> Double? {
        decimal(fromAmerican: odds).map { max(0, stake) * ($0 - 1) }
    }

    public static func totalReturn(stake: Double, american odds: Int) -> Double? {
        decimal(fromAmerican: odds).map { max(0, stake) * $0 }
    }

    public static func parlayAmerican(_ legs: [Int]) -> Int? {
        guard !legs.isEmpty else { return nil }
        let decimals = legs.compactMap(decimal(fromAmerican:))
        guard decimals.count == legs.count else { return nil }
        return american(fromDecimal: decimals.reduce(1, *))
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

public struct PlayerPropQuote: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(player)|\(marketKey)|\(selection)|\(point)" }
    public let player: String
    public let marketKey: String
    public let marketName: String
    public let selection: String
    public let point: Double
    public let odds: Int
    public let bookmakers: Int
    public let updatedAt: Date?

    public init(player: String, marketKey: String, marketName: String, selection: String,
                point: Double, odds: Int, bookmakers: Int, updatedAt: Date? = nil) {
        self.player = player
        self.marketKey = marketKey
        self.marketName = marketName
        self.selection = selection
        self.point = point
        self.odds = odds
        self.bookmakers = bookmakers
        self.updatedAt = updatedAt
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
    public let playerProps: [PlayerPropQuote]?

    public var predictedWinner: Team { homeWinProbability >= 0.5 ? matchup.home : matchup.away }
    public var confidence: Double { max(homeWinProbability, 1 - homeWinProbability) }

    public init(id: UUID = UUID(), matchup: Matchup, homeScore: Double, awayScore: Double, homeWinProbability: Double, simulations: Int, generatedAt: Date = .now, simulationSummary: SimulationSummary? = nil, modelVersion: String? = "MVP 1.2", dataSourceUpdatedAt: Date? = .now, recalculatedAt: Date? = .now, factors: [ProjectionFactor]? = nil, previousHomeWinProbability: Double? = nil, previousHomeScore: Double? = nil, previousAwayScore: Double? = nil, modelOnlyHomeSpread: Double? = nil, modelOnlyTotal: Double? = nil, previousMarketHomeSpread: Double? = nil, previousMarketTotal: Double? = nil, playerProps: [PlayerPropQuote]? = nil) {
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
        self.playerProps = playerProps
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
            let modelOnlyEdge = (modelOnlyHomeSpread ?? projectedHomeSpread) - marketMargin
            let team = edge >= 0 ? matchup.home.abbreviation : matchup.away.abbreviation
            let conventionalLine = edge >= 0 ? -marketMargin : marketMargin
            let label = "\(team) \(conventionalLine.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))))"
            let probability = Self.coverProbability(edgePoints: abs(edge), deviation: 13.5)
            let expectedValue = probability * (100.0 / 110.0 + 1) - 1
            let agrees = edge * modelOnlyEdge > 0
            let strength: BetStrength = agrees && abs(modelOnlyEdge) >= 7.5 && abs(edge) >= 7.5 && expectedValue >= 0.05
                ? .strong : agrees && abs(modelOnlyEdge) >= 5.5 && abs(edge) >= 5.5 && expectedValue > 0 ? .lean : .pass
            recommendations.append(BetRecommendation(kind: .spread, selection: label,
                edge: abs(edge), strength: strength,
                rationale: "Projected margin differs by \(abs(edge).formatted(.number.precision(.fractionLength(1)))) points; estimated cover chance \(probability.formatted(.percent.precision(.fractionLength(1)))) and value \(expectedValue.formatted(.percent.precision(.fractionLength(1)))).",
                strategyID: "spread-confirmed-value", estimatedWinProbability: probability, expectedValue: expectedValue))
        }
        if let marketTotal = line.total {
            let edge = projectedTotal - marketTotal
            let modelOnlyEdge = (modelOnlyTotal ?? projectedTotal) - marketTotal
            let selection = edge >= 0 ? "Over \(marketTotal.formatted(.number.precision(.fractionLength(1))))" : "Under \(marketTotal.formatted(.number.precision(.fractionLength(1))))"
            let probability = Self.coverProbability(edgePoints: abs(edge), deviation: 14.5)
            let expectedValue = probability * (100.0 / 110.0 + 1) - 1
            let agrees = edge * modelOnlyEdge > 0
            let strength: BetStrength = agrees && abs(modelOnlyEdge) >= 10 && abs(edge) >= 10 && expectedValue >= 0.05
                ? .strong : agrees && abs(modelOnlyEdge) >= 5.5 && abs(edge) >= 5.5 && expectedValue > 0 ? .lean : .pass
            recommendations.append(BetRecommendation(kind: .total, selection: selection,
                edge: abs(edge), strength: strength,
                rationale: "Projected total is \(abs(edge).formatted(.number.precision(.fractionLength(1)))) points \(edge >= 0 ? "above" : "below") consensus; estimated hit chance \(probability.formatted(.percent.precision(.fractionLength(1)))) and value \(expectedValue.formatted(.percent.precision(.fractionLength(1)))).",
                strategyID: "total-confirmed-value", estimatedWinProbability: probability, expectedValue: expectedValue))
        }
        if let homeOdds = line.homeMoneyline, let awayOdds = line.awayMoneyline {
            let homeRaw = Self.impliedProbability(homeOdds), awayRaw = Self.impliedProbability(awayOdds)
            let total = homeRaw + awayRaw
            let marketHome = total > 0 ? homeRaw / total : 0.5
            let homeEdge = homeWinProbability - marketHome
            let chooseHome = homeEdge >= 0
            let edge = abs(homeEdge)
            let odds = chooseHome ? homeOdds : awayOdds
            let probability = chooseHome ? homeWinProbability : 1 - homeWinProbability
            let decimalOdds = odds < 0 ? 1 + 100 / Double(-odds) : 1 + Double(odds) / 100
            let expectedValue = probability * decimalOdds - 1
            let acceptablePrice = (-300...300).contains(odds)
            let strength: BetStrength = acceptablePrice && edge >= 0.10 && expectedValue >= 0.08 && probability >= 0.55
                ? .strong : acceptablePrice && edge >= 0.06 && expectedValue >= 0.03 ? .lean : .pass
            recommendations.append(BetRecommendation(kind: .moneyline,
                selection: "\(chooseHome ? matchup.home.abbreviation : matchup.away.abbreviation) moneyline \(odds.formatted(.number.sign(strategy: .always())))",
                edge: edge * 100, strength: strength,
                rationale: "No-vig edge \(edge.formatted(.percent.precision(.fractionLength(1)))); expected value \(expectedValue.formatted(.percent.precision(.fractionLength(1)))) at \(odds.formatted(.number.sign(strategy: .always()))).",
                strategyID: "moneyline-price-aware-value", estimatedWinProbability: probability, expectedValue: expectedValue))
        }
        return recommendations.sorted { lhs, rhs in
            if lhs.strength != rhs.strength { return lhs.strength.sortOrder > rhs.strength.sortOrder }
            return lhs.edge > rhs.edge
        }
    }

    private static func impliedProbability(_ americanOdds: Int) -> Double {
        americanOdds < 0 ? Double(-americanOdds) / Double(-americanOdds + 100) : 100 / Double(americanOdds + 100)
    }

    private static func coverProbability(edgePoints: Double, deviation: Double) -> Double {
        let normalCDF = 0.5 * (1 + erf(edgePoints / (deviation * sqrt(2))))
        // Shrink theoretical probabilities toward 50% because forecast residuals
        // are noisier than a single normal distribution implies.
        return 0.5 + (normalCDF - 0.5) * 0.75
    }
}

public enum BetKind: String, Codable, Hashable, Sendable { case spread = "Spread"; case total = "Total"; case moneyline = "Moneyline" }

public enum HistoricalValidationWindow {
    /// A decade balances a useful number of rare strong-edge bets with relevance to
    /// the current NFL scoring and betting environment.
    public static let completedSeasons = 10

    public static func seasons(before season: Int) -> ClosedRange<Int> {
        (season - completedSeasons)...(season - 1)
    }
}

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
    public let strategyID: String?
    public let estimatedWinProbability: Double?
    public let expectedValue: Double?
    public var id: String { "\(kind.rawValue)-\(selection)" }
    public init(kind: BetKind, selection: String, edge: Double, strength: BetStrength, rationale: String,
                strategyID: String? = nil, estimatedWinProbability: Double? = nil, expectedValue: Double? = nil) {
        self.kind = kind; self.selection = selection; self.edge = edge; self.strength = strength; self.rationale = rationale
        self.strategyID = strategyID; self.estimatedWinProbability = estimatedWinProbability; self.expectedValue = expectedValue
    }
}

public struct BettingPerformance: Sendable, Hashable {
    public let graded: Int
    public let wins: Int
    public let losses: Int
    public let pushes: Int
    public let netUnits: Double
    public var winRate: Double { wins + losses == 0 ? 0 : Double(wins) / Double(wins + losses) }
    public var returnOnStake: Double { graded == 0 ? 0 : netUnits / Double(graded) }
}

public struct BetValidationPolicy: Sendable, Hashable {
    public let minimumBets: Int
    public let minimumWinRate: Double?
    public let minimumReturnOnStake: Double
    public let minimumSeasons: Int

    public static func standard(for kind: BetKind) -> Self {
        kind == .moneyline
            ? Self(minimumBets: 100, minimumWinRate: nil, minimumReturnOnStake: 0.03, minimumSeasons: 3)
            : Self(minimumBets: 30, minimumWinRate: 0.54, minimumReturnOnStake: 0, minimumSeasons: 3)
    }
}

public struct BetValidationResult: Sendable, Hashable {
    public let kind: BetKind
    public let performance: BettingPerformance
    public let seasonsTested: Int
    public let profitableSeasons: Int
    public let requiredProfitableSeasons: Int
    public let policy: BetValidationPolicy
    public let isValidated: Bool

    public var progress: Double {
        let sample = min(1, Double(performance.graded) / Double(policy.minimumBets))
        let seasons = min(1, Double(seasonsTested) / Double(policy.minimumSeasons))
        let stability = requiredProfitableSeasons == 0 ? 0 : min(1, Double(profitableSeasons) / Double(requiredProfitableSeasons))
        let quality: Double
        if let minimumWinRate = policy.minimumWinRate {
            quality = min(1, performance.winRate / minimumWinRate)
        } else {
            quality = policy.minimumReturnOnStake == 0 ? 1 : min(1, max(0, performance.returnOnStake) / policy.minimumReturnOnStake)
        }
        return (sample + seasons + stability + quality) / 4
    }

    public var unmetRequirements: [String] {
        var reasons: [String] = []
        if performance.graded < policy.minimumBets { reasons.append("\(performance.graded)/\(policy.minimumBets) bets") }
        if let target = policy.minimumWinRate, performance.winRate < target {
            reasons.append("\(performance.winRate.formatted(.percent.precision(.fractionLength(1))))/\(target.formatted(.percent.precision(.fractionLength(0)))) win rate")
        }
        if performance.returnOnStake < policy.minimumReturnOnStake {
            reasons.append("\(performance.returnOnStake.formatted(.percent.precision(.fractionLength(1))))/\(policy.minimumReturnOnStake.formatted(.percent.precision(.fractionLength(0)))) return")
        }
        if performance.netUnits <= 0 { reasons.append("profit must be positive") }
        if seasonsTested < policy.minimumSeasons { reasons.append("\(seasonsTested)/\(policy.minimumSeasons) seasons") }
        if profitableSeasons < requiredProfitableSeasons { reasons.append("\(profitableSeasons)/\(requiredProfitableSeasons) profitable seasons") }
        return reasons
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
    public let evaluationSeason: Int?

    public init(id: UUID = UUID(), prediction: Prediction, actualHomeScore: Int, actualAwayScore: Int, evaluationSeason: Int? = nil) {
        self.id = id
        self.prediction = prediction
        self.actualHomeScore = actualHomeScore
        self.actualAwayScore = actualAwayScore
        self.evaluationSeason = evaluationSeason
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
        var netUnits = 0.0
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
                if result == 1 {
                    wins += 1
                    let americanOdds: Int
                    if recommendation.kind == .moneyline {
                        let choseHome = recommendation.selection.hasPrefix(prediction.matchup.home.abbreviation + " ")
                        americanOdds = choseHome ? (prediction.matchup.bettingLine?.homeMoneyline ?? -110)
                                                  : (prediction.matchup.bettingLine?.awayMoneyline ?? -110)
                    } else { americanOdds = -110 }
                    netUnits += (OddsMath.decimal(fromAmerican: americanOdds) ?? 1) - 1
                } else if result == -1 {
                    losses += 1; netUnits -= 1
                } else { pushes += 1 }
            }
        }
        return BettingPerformance(graded: wins + losses + pushes, wins: wins, losses: losses,
                                  pushes: pushes, netUnits: netUnits)
    }

    public static func bettingValidation(_ grades: [GradedPrediction], kind: BetKind,
                                         policy: BetValidationPolicy? = nil) -> BetValidationResult {
        let policy = policy ?? .standard(for: kind)
        let performance = bettingPerformance(grades, kind: kind, strongOnly: true)
        let seasonal = Dictionary(grouping: grades.compactMap { grade in
            grade.evaluationSeason.map { ($0, grade) }
        }, by: { $0.0 }).mapValues { pairs in
            bettingPerformance(pairs.map(\.1), kind: kind, strongOnly: true)
        }.filter { $0.value.graded > 0 }
        let requiredProfitableSeasons = max(2, Int(ceil(Double(seasonal.count) / 2)))
        let profitableSeasons = seasonal.values.filter { $0.netUnits > 0 }.count
        let meetsQuality = policy.minimumWinRate.map { performance.winRate >= $0 } ?? true
        let validated = performance.graded >= policy.minimumBets
            && meetsQuality
            && performance.returnOnStake >= policy.minimumReturnOnStake
            && performance.netUnits > 0
            && seasonal.count >= policy.minimumSeasons
            && profitableSeasons >= requiredProfitableSeasons
        return BetValidationResult(kind: kind, performance: performance,
            seasonsTested: seasonal.count, profitableSeasons: profitableSeasons,
            requiredProfitableSeasons: requiredProfitableSeasons, policy: policy,
            isValidated: validated)
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
