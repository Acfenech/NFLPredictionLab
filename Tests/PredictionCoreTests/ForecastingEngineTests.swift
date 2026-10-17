import Testing
@testable import PredictionCore

@Test func historicalValidationUsesTenCompletedSeasons() {
    let seasons = HistoricalValidationWindow.seasons(before: 2026)
    #expect(seasons == 2016...2025)
    #expect(seasons.count == 10)
}

@Test func americanOddsCalculateProfitReturnAndParlay() {
    #expect(OddsMath.profit(stake: 100, american: 150) == 150)
    #expect(abs((OddsMath.totalReturn(stake: 100, american: -110) ?? 0) - 190.909) < 0.01)
    #expect(abs((OddsMath.impliedProbability(american: -110) ?? 0) - 0.5238) < 0.001)
    #expect(OddsMath.parlayAmerican([-110, -110]) == 264)
}

@Test func strongerHomeTeamIsFavored() {
    let weak = Team(abbreviation: "W", name: "Weak", offensiveRating: -5, defensiveRating: -5)
    let strong = Team(abbreviation: "S", name: "Strong", offensiveRating: 5, defensiveRating: 5)
    let prediction = ForecastingEngine().predict(Matchup(week: 1, kickoff: .now, away: weak, home: strong), simulations: 20_000)
    #expect(prediction.homeWinProbability > 0.65)
    #expect(prediction.homeScore > prediction.awayScore)
}

@Test func simulationIsDeterministicWithSeed() {
    let a = Team(abbreviation: "A", name: "A", offensiveRating: 1, defensiveRating: 1)
    let b = Team(abbreviation: "B", name: "B", offensiveRating: 2, defensiveRating: 2)
    let matchup = Matchup(week: 1, kickoff: .now, away: a, home: b)
    let engine = ForecastingEngine()
    #expect(engine.predict(matchup, seed: 99).homeWinProbability == engine.predict(matchup, seed: 99).homeWinProbability)
}

@Test func simulationIncludesUsefulScoreRanges() {
    let away = Team(abbreviation: "A", name: "Away", offensiveRating: 0, defensiveRating: 0)
    let home = Team(abbreviation: "H", name: "Home", offensiveRating: 0, defensiveRating: 0)
    let prediction = ForecastingEngine().predict(Matchup(week: 1, kickoff: .now, away: away, home: home), simulations: 2_000)
    let summary = prediction.simulationSummary
    #expect(summary != nil)
    #expect(summary!.awayLow <= summary!.awayHigh)
    #expect(summary!.homeLow <= summary!.homeHigh)
    #expect(summary!.mostLikelyAwayScore >= 0)
    #expect(summary!.mostLikelyHomeScore >= 0)
}

@Test func balancedMetricWeightsWinnerAndScoreEqually() {
    let team = Team(abbreviation: "T", name: "Team", offensiveRating: 0, defensiveRating: 0)
    let matchup = Matchup(week: 1, kickoff: .now, away: team, home: team)
    let prediction = Prediction(matchup: matchup, homeScore: 24, awayScore: 20, homeWinProbability: 0.6, simulations: 1)
    let grade = GradedPrediction(prediction: prediction, actualHomeScore: 24, actualAwayScore: 20)
    #expect(grade.balancedAccuracy == 1)
}

@Test func recordIsConvertedToCenteredRating() {
    #expect(ESPNScoreboardFeed.rating(from: "5-0") == 5)
    #expect(ESPNScoreboardFeed.rating(from: "0-5") == -5)
    #expect(ESPNScoreboardFeed.rating(from: "2-2") == 0)
}

@Test func brierScoreRewardsCalibratedCorrectForecast() {
    let team = Team(abbreviation: "T", name: "Team", offensiveRating: 0, defensiveRating: 0)
    let matchup = Matchup(week: 1, kickoff: .now, away: team, home: team)
    let strong = GradedPrediction(prediction: Prediction(matchup: matchup, homeScore: 24, awayScore: 20, homeWinProbability: 0.9, simulations: 1), actualHomeScore: 24, actualAwayScore: 20)
    let weak = GradedPrediction(prediction: Prediction(matchup: matchup, homeScore: 24, awayScore: 20, homeWinProbability: 0.6, simulations: 1), actualHomeScore: 24, actualAwayScore: 20)
    #expect(strong.brierScore < weak.brierScore)
}

@Test func backtestSummaryAggregatesGrades() {
    let team = Team(abbreviation: "T", name: "Team", offensiveRating: 0, defensiveRating: 0)
    let matchup = Matchup(week: 1, kickoff: .now, away: team, home: team)
    let grade = GradedPrediction(prediction: Prediction(matchup: matchup, homeScore: 21, awayScore: 17, homeWinProbability: 0.75, simulations: 1), actualHomeScore: 21, actualAwayScore: 17)
    let summary = Backtester.summarize([grade])
    #expect(summary?.games == 1)
    #expect(summary?.winnerAccuracy == 1)
    #expect(summary?.meanAbsoluteScoreError == 0)
}

@Test func calibrationGroupsForecastConfidence() {
    let team = Team(abbreviation: "T", name: "Team", offensiveRating: 0, defensiveRating: 0)
    let matchup = Matchup(week: 1, kickoff: .now, away: team, home: team)
    let grades = [
        GradedPrediction(prediction: Prediction(matchup: matchup, homeScore: 24, awayScore: 20, homeWinProbability: 0.72, simulations: 1), actualHomeScore: 24, actualAwayScore: 20),
        GradedPrediction(prediction: Prediction(matchup: matchup, homeScore: 24, awayScore: 20, homeWinProbability: 0.76, simulations: 1), actualHomeScore: 17, actualAwayScore: 20)
    ]
    let bucket = Backtester.calibration(grades).first
    #expect(bucket?.games == 2)
    #expect(bucket?.observedRate == 0.5)
}

@Test func predictionExplainsItsPrimaryFactors() {
    let away = Team(abbreviation: "A", name: "Away", offensiveRating: -2, defensiveRating: -1, recentForm: -3, restDays: 6)
    let home = Team(abbreviation: "H", name: "Home", offensiveRating: 3, defensiveRating: 2, recentForm: 4, restDays: 9)
    let prediction = ForecastingEngine().predict(Matchup(week: 4, kickoff: .now, away: away, home: home), simulations: 500)
    #expect(prediction.factors?.count == 8)
    #expect(prediction.factors?.contains(where: { $0.name == "Recent form" }) == true)
    #expect(!prediction.confidenceExplanation.isEmpty)
}

@Test func marketAwareEnsembleMovesProjectionTowardConsensus() {
    let away = Team(abbreviation: "A", name: "Away", offensiveRating: 0, defensiveRating: 0)
    let home = Team(abbreviation: "H", name: "Home", offensiveRating: 0, defensiveRating: 0)
    let noMarket = ForecastingEngine().predict(Matchup(week: 1, kickoff: .now, away: away, home: home), simulations: 1_000, seed: 5)
    let market = ForecastingEngine().predict(Matchup(week: 1, kickoff: .now, away: away, home: home,
        bettingLine: BettingLine(homeSpread: 10, total: 52)), simulations: 1_000, seed: 5)
    #expect(market.projectedHomeSpread > noMarket.projectedHomeSpread)
    #expect(market.projectedTotal > noMarket.projectedTotal)
    #expect(market.modelOnlyHomeSpread != nil)
}

@Test func largeMarketDisagreementIsFlagged() {
    let team = Team(abbreviation: "T", name: "Team", offensiveRating: 0, defensiveRating: 0)
    let matchup = Matchup(week: 1, kickoff: .now, away: team, home: team,
        bettingLine: BettingLine(homeSpread: -7, total: 60))
    let prediction = Prediction(matchup: matchup, homeScore: 24, awayScore: 20,
        homeWinProbability: 0.6, simulations: 1)
    #expect(prediction.reviewFlag != nil)
}

@Test func gameContextChangesMarginAndTotal() {
    let team = Team(abbreviation: "T", name: "Team", offensiveRating: 0, defensiveRating: 0)
    let baseline = ForecastingEngine().predict(Matchup(week: 1, kickoff: .now, away: team, home: team), simulations: 1_000, seed: 9)
    let context = GameContext(weatherSummary: "Strong wind", weatherPoints: -6,
                              travelMiles: 2_400, travelPoints: 1.5,
                              quarterbackSummary: "Starters confirmed")
    let adjusted = ForecastingEngine().predict(Matchup(week: 1, kickoff: .now, away: team, home: team, context: context), simulations: 1_000, seed: 9)
    #expect(adjusted.projectedTotal < baseline.projectedTotal)
    #expect(adjusted.projectedHomeSpread > baseline.projectedHomeSpread)
}

@Test func betterDefenseSuppressesOpponentScore() {
    let offense = Team(abbreviation: "A", name: "Away", offensiveRating: 2, defensiveRating: 0)
    let weakDefense = Team(abbreviation: "W", name: "Weak D", offensiveRating: 0, defensiveRating: -5)
    let strongDefense = Team(abbreviation: "S", name: "Strong D", offensiveRating: 0, defensiveRating: 5)
    let engine = ForecastingEngine()
    let versusWeak = engine.predict(Matchup(week: 1, kickoff: .now, away: offense, home: weakDefense), simulations: 500, seed: 7)
    let versusStrong = engine.predict(Matchup(week: 1, kickoff: .now, away: offense, home: strongDefense), simulations: 500, seed: 7)
    #expect(versusStrong.awayScore < versusWeak.awayScore)
}

@Test func tiedGameIsNotCreditedAsCorrectWinner() {
    let team = Team(abbreviation: "T", name: "Team", offensiveRating: 0, defensiveRating: 0)
    let prediction = Prediction(matchup: Matchup(week: 1, kickoff: .now, away: team, home: team), homeScore: 20, awayScore: 17, homeWinProbability: 0.6, simulations: 1)
    let grade = GradedPrediction(prediction: prediction, actualHomeScore: 20, actualAwayScore: 20)
    #expect(!grade.winnerCorrect)
}

@Test func trainerUsesLatestSeasonOnlyForValidation() {
    let away = Team(abbreviation: "A", name: "Away", offensiveRating: -2, defensiveRating: -2)
    let home = Team(abbreviation: "H", name: "Home", offensiveRating: 2, defensiveRating: 2)
    let matchup = Matchup(week: 2, kickoff: .now, away: away, home: home)
    let games = [
        HistoricalGame(season: 2023, matchup: matchup, result: GameResult(awayAbbreviation: "A", homeAbbreviation: "H", awayScore: 17, homeScore: 24)),
        HistoricalGame(season: 2024, matchup: matchup, result: GameResult(awayAbbreviation: "A", homeAbbreviation: "H", awayScore: 20, homeScore: 27))
    ]
    let report = ModelTrainer.trainAndValidate(games)
    #expect(report?.trainingGames == 2)
    #expect(report?.validationSeason == 2024)
    #expect(report?.grades.count == 1)
}

@Test func probabilityCalibrationIsMonotonic() {
    let team = Team(abbreviation: "T", name: "Team", offensiveRating: 0, defensiveRating: 0)
    let matchup = Matchup(week: 1, kickoff: .now, away: team, home: team)
    let grades = stride(from: 0.05, through: 0.95, by: 0.05).enumerated().map { index, probability in
        GradedPrediction(prediction: Prediction(matchup: matchup, homeScore: 21, awayScore: 20,
                                                 homeWinProbability: probability, simulations: 1),
                         actualHomeScore: index > 8 ? 24 : 17, actualAwayScore: 20)
    }
    let points = ProbabilityCalibrator.fit(grades)
    #expect(zip(points, points.dropFirst()).allSatisfy { $0.observed <= $1.observed })
}

@Test func bettingLineComparisonShowsMarginAndTotal() {
    let away = Team(abbreviation: "A", name: "Away", offensiveRating: 0, defensiveRating: 0)
    let home = Team(abbreviation: "H", name: "Home", offensiveRating: 0, defensiveRating: 0)
    let matchup = Matchup(week: 1, kickoff: .now, away: away, home: home,
                          bettingLine: BettingLine(homeSpread: 3.5, total: 44.5, homeMoneyline: -170, awayMoneyline: 145))
    let prediction = Prediction(matchup: matchup, homeScore: 27, awayScore: 21, homeWinProbability: 0.7, simulations: 1)
    #expect(prediction.marketComparison?.contains("market H by 3.5") == true)
    #expect(prediction.marketComparison?.contains("market 44.5") == true)
}

@Test func forecastMovementUsesPriorProbability() {
    let away = Team(abbreviation: "A", name: "Away", offensiveRating: 0, defensiveRating: 0)
    let home = Team(abbreviation: "H", name: "Home", offensiveRating: 0, defensiveRating: 0)
    let prediction = Prediction(matchup: Matchup(week: 1, kickoff: .now, away: away, home: home),
                                homeScore: 24, awayScore: 20, homeWinProbability: 0.68,
                                simulations: 1, previousHomeWinProbability: 0.60)
    #expect(prediction.movementSummary?.contains("H win probability moved") == true)
}

@Test func bettingRecommendationsRequireMeaningfulEdge() {
    let away = Team(abbreviation: "A", name: "Away", offensiveRating: 0, defensiveRating: 0)
    let home = Team(abbreviation: "H", name: "Home", offensiveRating: 0, defensiveRating: 0)
    let line = BettingLine(homeSpread: 2.5, total: 44.5, homeMoneyline: -140, awayMoneyline: 120)
    let prediction = Prediction(matchup: Matchup(week: 1, kickoff: .now, away: away, home: home, bettingLine: line),
                                homeScore: 30, awayScore: 20, homeWinProbability: 0.78, simulations: 1)
    #expect(prediction.bettingRecommendations.contains { $0.kind == .spread && $0.strength == .strong })
    #expect(prediction.bettingRecommendations.contains { $0.kind == .total && $0.strength != .pass })
    #expect(prediction.bettingRecommendations.contains { $0.kind == .moneyline && $0.selection.contains("H moneyline") })
    #expect(prediction.bettingRecommendations.allSatisfy { $0.estimatedWinProbability != nil && $0.expectedValue != nil })
}

@Test func expensiveMoneylineDoesNotBecomeARecommendedBetWithoutValue() {
    let away = Team(abbreviation: "A", name: "Away", offensiveRating: 0, defensiveRating: 0)
    let home = Team(abbreviation: "H", name: "Home", offensiveRating: 0, defensiveRating: 0)
    let line = BettingLine(homeMoneyline: -450, awayMoneyline: 340)
    let prediction = Prediction(matchup: Matchup(week: 1, kickoff: .now, away: away, home: home, bettingLine: line),
                                homeScore: 28, awayScore: 17, homeWinProbability: 0.86, simulations: 1)
    let moneyline = prediction.bettingRecommendations.first { $0.kind == .moneyline }
    #expect(moneyline?.strength == .pass)
}

@Test func bettingBacktestGradesSpreadTotalAndMoneyline() {
    let away = Team(abbreviation: "A", name: "Away", offensiveRating: 0, defensiveRating: 0)
    let home = Team(abbreviation: "H", name: "Home", offensiveRating: 0, defensiveRating: 0)
    let line = BettingLine(homeSpread: 2.5, total: 44.5, homeMoneyline: -140, awayMoneyline: 120)
    let prediction = Prediction(matchup: Matchup(week: 1, kickoff: .now, away: away, home: home, bettingLine: line),
                                homeScore: 30, awayScore: 20, homeWinProbability: 0.78, simulations: 1)
    let grade = GradedPrediction(prediction: prediction, actualHomeScore: 31, actualAwayScore: 17)
    let performance = Backtester.bettingPerformance([grade])
    #expect(performance.graded == 3)
    #expect(performance.wins == 3)
    #expect(performance.losses == 0)
    #expect(performance.netUnits > 2.5)
}

@Test func moneylinePerformanceUsesPriceAdjustedReturn() {
    let away = Team(abbreviation: "A", name: "Away", offensiveRating: 0, defensiveRating: 0)
    let home = Team(abbreviation: "H", name: "Home", offensiveRating: 0, defensiveRating: 0)
    let line = BettingLine(homeMoneyline: 200, awayMoneyline: -240)
    let prediction = Prediction(matchup: Matchup(week: 1, kickoff: .now, away: away, home: home, bettingLine: line),
                                homeScore: 28, awayScore: 20, homeWinProbability: 0.55, simulations: 1)
    let win = GradedPrediction(prediction: prediction, actualHomeScore: 24, actualAwayScore: 20)
    let loss = GradedPrediction(prediction: prediction, actualHomeScore: 17, actualAwayScore: 20)
    let performance = Backtester.bettingPerformance([win, loss], kind: .moneyline)
    #expect(performance.winRate == 0.5)
    #expect(performance.netUnits == 1)
    #expect(performance.returnOnStake == 0.5)
}

@Test func validationRequiresOutOfSampleEvidenceAcrossThreeSeasons() {
    let away = Team(abbreviation: "A", name: "Away", offensiveRating: 0, defensiveRating: 0)
    let home = Team(abbreviation: "H", name: "Home", offensiveRating: 0, defensiveRating: 0)
    let line = BettingLine(homeSpread: 2.5, total: 44.5, homeMoneyline: -140, awayMoneyline: 120)
    let prediction = Prediction(matchup: Matchup(week: 1, kickoff: .now, away: away, home: home, bettingLine: line),
                                homeScore: 30, awayScore: 20, homeWinProbability: 0.78, simulations: 1)
    let twoSeasons = (0..<30).map { index in
        GradedPrediction(prediction: prediction, actualHomeScore: 31, actualAwayScore: 17,
                         evaluationSeason: index < 15 ? 2023 : 2024)
    }
    let incomplete = Backtester.bettingValidation(twoSeasons, kind: .spread)
    #expect(!incomplete.isValidated)
    #expect(incomplete.seasonsTested == 2)

    let threeSeasons = (0..<30).map { index in
        GradedPrediction(prediction: prediction, actualHomeScore: 31, actualAwayScore: 17,
                         evaluationSeason: 2022 + index / 10)
    }
    let complete = Backtester.bettingValidation(threeSeasons, kind: .spread)
    #expect(complete.isValidated)
    #expect(complete.profitableSeasons == 3)
}

@Test func walkForwardGradesRetainTheirEvaluationSeason() {
    let away = Team(abbreviation: "A", name: "Away", offensiveRating: -2, defensiveRating: -2)
    let home = Team(abbreviation: "H", name: "Home", offensiveRating: 2, defensiveRating: 2)
    let matchup = Matchup(week: 2, kickoff: .now, away: away, home: home)
    let games = [2022, 2023, 2024].map {
        HistoricalGame(season: $0, matchup: matchup,
                       result: GameResult(awayAbbreviation: "A", homeAbbreviation: "H", awayScore: 17, homeScore: 24))
    }
    let report = ModelTrainer.trainAndValidate(games)
    #expect(Set(report?.rollingGrades.compactMap(\.evaluationSeason) ?? []) == Set([2023, 2024]))
}
