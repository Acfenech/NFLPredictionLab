import Testing
@testable import PredictionCore

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
