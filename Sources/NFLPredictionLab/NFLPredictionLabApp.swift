import SwiftUI
#if canImport(PredictionCore)
import PredictionCore
#endif

@main
struct NFLPredictionLabApp: App {
    var body: some Scene {
        WindowGroup { DashboardView() }
    }
}

struct DashboardView: View {
    @State private var selection = 0
    @StateObject private var model = AppModel()

    var body: some View {
        TabView(selection: $selection) {
            PredictionsView(predictions: model.predictions, season: model.season, week: model.week, feedStatus: model.status, isRefreshing: model.isRefreshing) { Task { await model.refresh() } }.tabItem { Label("Forecasts", systemImage: "sportscourt") }.tag(0)
            BettingView(predictions: model.predictions, grades: model.gradedPredictions).tabItem { Label("Bets", systemImage: "chart.bar.doc.horizontal") }.tag(1)
            SimulationView(predictions: model.predictions).tabItem { Label("Simulations", systemImage: "waveform.path.ecg") }.tag(2)
            AccuracyView(grades: model.gradedPredictions, archiveCount: model.archiveCount,
                         validationSummary: model.validationSummary, validationSeason: model.validationSeason,
                         trainingGames: model.trainingGames,
                         rollingValidationSummary: model.rollingValidationSummary,
                         rollingValidationSeasons: model.rollingValidationSeasons).tabItem { Label("Accuracy", systemImage: "chart.line.uptrend.xyaxis") }.tag(3)
            HistoryView(bundles: model.archiveBundles).tabItem { Label("History", systemImage: "clock.arrow.circlepath") }.tag(4)
            SettingsView(model: model).tabItem { Label("Model", systemImage: "slider.horizontal.3") }.tag(5)
            UserGuideView().tabItem { Label("Guide", systemImage: "book.closed") }.tag(6)
        }
        .frame(minWidth: 760, minHeight: 540)
        .task { await model.refresh() }
    }
}

struct UserGuideView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Quick start") {
                    GuideItem(icon: "1.circle.fill", title: "Refresh the data", detail: "Use Refresh on Forecasts to load the latest available schedule, results, team metrics, injuries, weather and market consensus.")
                    GuideItem(icon: "2.circle.fill", title: "Open a matchup", detail: "Review the projected score, win probability and the factors that moved the projection. Treat the score as a midpoint, not an exact outcome.")
                    GuideItem(icon: "3.circle.fill", title: "Check uncertainty", detail: "Use Simulations for the likely score range and Accuracy for performance on games the model did not train on.")
                    GuideItem(icon: "4.circle.fill", title: "Use Bets last", detail: "Only consider a market when it passes the validation gate. “Not validated” and “Pass” mean the historical evidence is not strong enough to recommend a wager.")
                }

                Section("Data sources") {
                    GuideItem(icon: "football.fill", title: "nflverse", detail: "Schedule, final scores, consensus betting lines, injuries, depth charts and weekly team statistics. The app derives recent form, efficiency, success, explosiveness, pressure and turnover-regression signals from these records.")
                    GuideItem(icon: "cloud.sun.fill", title: "Open-Meteo", detail: "Forecast temperature, wind and precipitation near the stadium at kickoff. Weather may affect scoring and passing efficiency; forecasts can change as kickoff approaches.")
                    GuideItem(icon: "location.fill", title: "Stadium and travel data", detail: "Bundled stadium coordinates are used to estimate the away team’s travel distance. This is context, not live tracking.")
                    GuideItem(icon: "chart.line.uptrend.xyaxis", title: "Market consensus", detail: "Available spread, total and moneyline fields from nflverse are comparison inputs. They may lag a sportsbook and are not guaranteed to be the current or closing price.")
                    GuideItem(icon: "icloud.fill", title: "CloudKit and GitHub Actions", detail: "CloudKit synchronizes forecast bundles and history across signed-in Apple devices. Scheduled GitHub Actions performs unattended calculations because CloudKit does not run background forecasting jobs.")
                }

                Section("What the forecast means") {
                    GuideItem(icon: "number", title: "Projected score", detail: "The average scoring estimate from team strength, recent form, game context and available market inputs. Real scores naturally vary around it.")
                    GuideItem(icon: "percent", title: "Confidence", detail: "The predicted winner’s simulated win rate across 10,000 outcomes. For example, 65% means the model winner won about 6,500 simulations—not that the result is certain.")
                    GuideItem(icon: "scale.3d", title: "Factor edge", detail: "A positive factor value favors the home team; a negative value favors the away team. The detail text explains the contributing signal.")
                    GuideItem(icon: "arrow.left.and.right", title: "Model versus market", detail: "The difference between the model’s projected margin or total and the consensus line. A large disagreement is a review flag, not proof that the market is wrong.")
                    GuideItem(icon: "waveform.path.ecg", title: "80% range", detail: "Eight of ten simulated outcomes fall approximately inside this score interval. Outcomes outside the range remain possible.")
                }

                Section("Betting labels") {
                    GuideItem(icon: "hand.raised.fill", title: "Pass", detail: "The edge is too small, required data is missing, or the market has not passed historical validation. Passing is an intentional recommendation.")
                    GuideItem(icon: "lightbulb.fill", title: "Lean", detail: "The model finds a modest difference from the market, but uncertainty is still meaningful.")
                    GuideItem(icon: "bolt.fill", title: "Strong edge", detail: "The model-market difference clears the higher threshold. This label can appear as actionable only after that market records at least 30 held-out strong-edge samples and a win rate of 54% or better.")
                    Text("Moneyline probability removes the sportsbook’s estimated margin before comparison. Spread and total records count wins, losses and pushes. Historical results do not include price changes, limits, fees or the exact line available to you.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Accuracy terms") {
                    GuideItem(icon: "checkmark.circle", title: "Winner accuracy", detail: "The percentage of games where the predicted winner won.")
                    GuideItem(icon: "scope", title: "Mean score error", detail: "The average absolute difference between each team’s predicted and actual score. Lower is better.")
                    GuideItem(icon: "gauge.with.dots.needle.50percent", title: "Brier score", detail: "Measures probability accuracy and penalizes confident mistakes. Lower is better; 0 is perfect.")
                    GuideItem(icon: "equal.circle", title: "Balanced score", detail: "The app’s combined evaluation gives winner accuracy and score accuracy equal importance.")
                    GuideItem(icon: "lock.shield", title: "Held-out validation", detail: "The model is evaluated on games or seasons that were not used to select its settings. This is more trustworthy than performance on training data.")
                }

                Section("Refresh, history and adjustments") {
                    GuideItem(icon: "arrow.clockwise", title: "Refresh", detail: "Rechecks live sources and recalculates forecasts. If one optional source is delayed, the app continues with the remaining data and reports coverage in Model.")
                    GuideItem(icon: "clock.arrow.circlepath", title: "History", detail: "Stores forecast snapshots so results can be graded later without rewriting what the model originally predicted.")
                    GuideItem(icon: "slider.horizontal.3", title: "QB / injury adjustment", detail: "A manual point adjustment changes a team’s offensive outlook. Negative values represent a downgrade. Use sparingly and recalculate after editing.")
                }

                Section("Important limitations") {
                    Text("This is a private analytical tool, not financial advice. Data can be delayed, incomplete or revised; injuries and weather can change; markets can move; and every wager can lose. Verify the current line and player status independently, and never risk money you cannot afford to lose.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("User Guide")
        }
    }
}

private struct GuideItem: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct BettingView: View {
    let predictions: [Prediction]
    let grades: [GradedPrediction]
    private var validatedKinds: Set<BetKind> {
        Set([BetKind.spread, .total, .moneyline].filter { kind in
            let performance = Backtester.bettingPerformance(grades, kind: kind, strongOnly: true)
            return performance.graded >= 30 && performance.winRate >= 0.54
        })
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Recommendations require a measured model edge. A Pass is intentional. Lines can move, and no projection guarantees a result. Use only amounts you can afford to lose.")
                        .font(.callout).foregroundStyle(.secondary)
                    if validatedKinds.isEmpty {
                        Label("No betting market currently passes the validation gate (at least 30 strong-edge samples and 54% wins). Candidate edges remain visible, but are not recommended wagers.", systemImage: "shield.lefthalf.filled")
                            .foregroundStyle(.orange)
                    }
                }
                ForEach(predictions) { prediction in
                    Section("\(prediction.matchup.away.abbreviation) at \(prediction.matchup.home.abbreviation)") {
                        if prediction.bettingRecommendations.isEmpty {
                            Text("Pass · market line unavailable").foregroundStyle(.secondary)
                        } else {
                            ForEach(prediction.bettingRecommendations) { recommendation in
                                let validated = validatedKinds.contains(recommendation.kind)
                                let displayStrength: BetStrength = validated ? recommendation.strength : .pass
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(recommendation.kind.rawValue).fontWeight(.semibold)
                                        Spacer()
                                        Text(validated ? displayStrength.rawValue : "Not validated")
                                            .foregroundStyle(displayStrength == .strong ? .green : displayStrength == .lean ? .orange : .secondary)
                                    }
                                    Text(displayStrength == .pass ? "Pass on \(recommendation.selection)" : recommendation.selection)
                                    Text(recommendation.rationale).font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 3)
                            }
                        }
                        if let flag = prediction.reviewFlag {
                            Label(flag, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }.navigationTitle("Betting Analysis")
        }
    }
}

struct PredictionsView: View {
    let predictions: [Prediction]
    let season: Int
    let week: Int
    let feedStatus: String
    let isRefreshing: Bool
    let refresh: () -> Void
    var body: some View {
        NavigationStack {
            List(predictions) { prediction in
                NavigationLink {
                    MatchupDetail(prediction: prediction)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("\(prediction.matchup.away.abbreviation) at \(prediction.matchup.home.abbreviation)").font(.headline)
                            Spacer()
                            Text(prediction.confidence < 0.55 ? "Near toss-up" : "\(prediction.predictedWinner.abbreviation) wins")
                                .foregroundStyle(prediction.confidence < 0.55 ? .orange : .blue).fontWeight(.semibold)
                        }
                        Text("Projected: \(prediction.matchup.away.abbreviation) \(prediction.awayScore, specifier: "%.0f") – \(prediction.matchup.home.abbreviation) \(prediction.homeScore, specifier: "%.0f")")
                        Text(prediction.matchup.kickoff.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: prediction.confidence) { Text("Confidence \(prediction.confidence, format: .percent.precision(.fractionLength(0)))") }
                        Text(prediction.confidenceExplanation).font(.caption).foregroundStyle(.secondary)
                        if let comparison = prediction.marketComparison {
                            Label(comparison, systemImage: "dollarsign.arrow.circlepath").font(.caption).foregroundStyle(.purple)
                        } else {
                            Text("Market line not posted").font(.caption2).foregroundStyle(.tertiary)
                        }
                        if let flag = prediction.reviewFlag {
                            Label(flag, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                        }
                    }.padding(.vertical, 6)
                }
            }
            .navigationTitle(week > 0 ? String(format: "%d Week %d Forecasts", season, week) : "NFL Forecasts")
            .toolbar { Button(action: refresh) { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(isRefreshing) }
            .safeAreaInset(edge: .bottom) {
                Text(feedStatus).font(.caption).foregroundStyle(.secondary).padding(8)
            }
        }
    }
}

struct MatchupDetail: View {
    let prediction: Prediction
    var body: some View {
        Form {
            Section("Prediction") {
                LabeledContent("Winner", value: prediction.predictedWinner.name)
                LabeledContent("Score", value: "\(prediction.matchup.away.abbreviation) \(prediction.awayScore.formatted(.number.precision(.fractionLength(0)))) – \(prediction.matchup.home.abbreviation) \(prediction.homeScore.formatted(.number.precision(.fractionLength(0))))")
                LabeledContent("Home win probability", value: prediction.homeWinProbability.formatted(.percent.precision(.fractionLength(1))))
                if let margin = prediction.modelOnlyHomeSpread, let total = prediction.modelOnlyTotal {
                    LabeledContent("Model-only baseline", value: "margin \(margin.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1)))) · total \(total.formatted(.number.precision(.fractionLength(1))))")
                }
            }
            Section("Matchup intelligence") {
                LabeledContent("Home offense / defense", value: "\(prediction.matchup.home.offensiveRating.formatted(.number.precision(.fractionLength(1)))) / \(prediction.matchup.home.defensiveRating.formatted(.number.precision(.fractionLength(1))))")
                LabeledContent("Away offense / defense", value: "\(prediction.matchup.away.offensiveRating.formatted(.number.precision(.fractionLength(1)))) / \(prediction.matchup.away.defensiveRating.formatted(.number.precision(.fractionLength(1))))")
            }
            Section("Why this projection") {
                Text(prediction.confidenceExplanation).font(.callout)
                ForEach(prediction.factors ?? []) { factor in
                    VStack(alignment: .leading, spacing: 3) {
                        LabeledContent(factor.name, value: factor.homeEdge.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))))
                        Text(factor.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Confidence is the simulated win rate across \(prediction.simulations.formatted()) outcomes—not a guarantee.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Market comparison") {
                if let line = prediction.matchup.bettingLine, let comparison = prediction.marketComparison {
                    Text(comparison)
                    if let homeMoneyline = line.homeMoneyline { LabeledContent("\(prediction.matchup.home.abbreviation) moneyline", value: homeMoneyline.formatted(.number.sign(strategy: .always()))) }
                    if let awayMoneyline = line.awayMoneyline { LabeledContent("\(prediction.matchup.away.abbreviation) moneyline", value: awayMoneyline.formatted(.number.sign(strategy: .always()))) }
                    Text("Source: \(line.source). Lines are shown for comparison, not as betting advice.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Market line not posted", systemImage: "clock", description: Text("The comparison will appear after nflverse publishes consensus odds."))
                }
                if let movement = prediction.movementSummary {
                    Label(movement, systemImage: "arrow.up.arrow.down").font(.caption)
                }
                if let movement = prediction.lineMovementSummary {
                    Label(movement, systemImage: "chart.line.uptrend.xyaxis").font(.caption)
                }
                if let flag = prediction.reviewFlag {
                    Label(flag, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            if let context = prediction.matchup.context {
                Section("Game conditions") {
                    if let weather = context.weatherSummary { LabeledContent("Weather", value: weather) }
                    if let miles = context.travelMiles { LabeledContent("Away travel", value: "\(miles.formatted()) miles") }
                    if let quarterbacks = context.quarterbackSummary { LabeledContent("Quarterbacks", value: quarterbacks) }
                }
            }
        }.navigationTitle("Matchup")
    }
}

struct SimulationView: View {
    let predictions: [Prediction]
    var body: some View {
        NavigationStack {
            List(predictions) { p in
                VStack(alignment: .leading, spacing: 5) {
                    LabeledContent("\(p.matchup.away.abbreviation) at \(p.matchup.home.abbreviation)", value: "\(p.simulations.formatted()) runs")
                    Text("\(p.matchup.home.abbreviation) win \(p.homeWinProbability.formatted(.percent.precision(.fractionLength(1)))) · Upset \((1 - p.confidence).formatted(.percent.precision(.fractionLength(1))))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let s = p.simulationSummary {
                        Text("80% range: \(p.matchup.away.abbreviation) \(s.awayLow.formatted(.number.precision(.fractionLength(0))))–\(s.awayHigh.formatted(.number.precision(.fractionLength(0)))) · \(p.matchup.home.abbreviation) \(s.homeLow.formatted(.number.precision(.fractionLength(0))))–\(s.homeHigh.formatted(.number.precision(.fractionLength(0))))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Most common score: \(p.matchup.away.abbreviation) \(s.mostLikelyAwayScore) – \(p.matchup.home.abbreviation) \(s.mostLikelyHomeScore)")
                            .font(.caption)
                    }
                }.padding(.vertical, 4)
            }.navigationTitle("Simulation Center")
        }
    }
}

struct AccuracyView: View {
    let grades: [GradedPrediction]
    let archiveCount: Int
    let validationSummary: BacktestSummary?
    let validationSeason: Int?
    let trainingGames: Int
    let rollingValidationSummary: BacktestSummary?
    let rollingValidationSeasons: [Int]
    var body: some View {
        NavigationStack {
            if grades.isEmpty {
                ContentUnavailableView("Awaiting completed games", systemImage: "chart.bar", description: Text("\(archiveCount) archived forecast snapshots are ready to grade when final scores arrive."))
            } else {
                let summary = Backtester.summarize(grades)!
                let marketGrades = grades.filter { $0.prediction.matchup.bettingLine?.homeSpread != nil }
                let homeBaseline = Double(grades.filter { $0.actualHomeScore > $0.actualAwayScore }.count) / Double(grades.count)
                let marketCorrect = marketGrades.filter { grade in
                    guard let margin = grade.prediction.matchup.bettingLine?.homeSpread else { return false }
                    return (margin >= 0) == (grade.actualHomeScore > grade.actualAwayScore)
                }.count
                let closingGrades = grades.filter { $0.prediction.matchup.bettingLine?.closingHomeSpread != nil }
                List {
                    if let validationSummary, let validationSeason {
                        Section("Out-of-sample validation · \(String(validationSeason))") {
                            LabeledContent("Training games", value: trainingGames.formatted())
                            LabeledContent("Validation games", value: validationSummary.games.formatted())
                            LabeledContent("Winner accuracy", value: validationSummary.winnerAccuracy.formatted(.percent.precision(.fractionLength(0))))
                            LabeledContent("Mean score error", value: validationSummary.meanAbsoluteScoreError.formatted(.number.precision(.fractionLength(1))))
                            LabeledContent("Brier score", value: validationSummary.meanBrierScore.formatted(.number.precision(.fractionLength(3))))
                            Text("Model weights were selected on earlier seasons; this season was held out from tuning.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let rollingValidationSummary, !rollingValidationSeasons.isEmpty {
                        Section("Rolling-season validation") {
                            LabeledContent("Held-out seasons", value: rollingValidationSeasons.map(String.init).joined(separator: ", "))
                            LabeledContent("Games", value: rollingValidationSummary.games.formatted())
                            LabeledContent("Winner accuracy", value: rollingValidationSummary.winnerAccuracy.formatted(.percent.precision(.fractionLength(0))))
                            LabeledContent("Mean score error", value: rollingValidationSummary.meanAbsoluteScoreError.formatted(.number.precision(.fractionLength(1))))
                            LabeledContent("Brier score", value: rollingValidationSummary.meanBrierScore.formatted(.number.precision(.fractionLength(3))))
                            Text("Each season is evaluated using only information from earlier seasons.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section("Performance") {
                        LabeledContent("Forecasts graded", value: summary.games.formatted())
                        LabeledContent("Winner accuracy", value: summary.winnerAccuracy.formatted(.percent.precision(.fractionLength(0))))
                        LabeledContent("Mean score error", value: summary.meanAbsoluteScoreError.formatted(.number.precision(.fractionLength(1))))
                        LabeledContent("Brier score", value: summary.meanBrierScore.formatted(.number.precision(.fractionLength(3))))
                        LabeledContent("Balanced score", value: summary.balancedAccuracy.formatted(.percent.precision(.fractionLength(0))))
                    }
                    Section("Benchmark comparison") {
                        LabeledContent("MVP 0.9 winner accuracy", value: summary.winnerAccuracy.formatted(.percent.precision(.fractionLength(0))))
                        LabeledContent("Always choose home", value: homeBaseline.formatted(.percent.precision(.fractionLength(0))))
                        if !marketGrades.isEmpty {
                            LabeledContent("Market favorite", value: (Double(marketCorrect) / Double(marketGrades.count)).formatted(.percent.precision(.fractionLength(0))))
                            LabeledContent("Games with market lines", value: marketGrades.count.formatted())
                        }
                        if !closingGrades.isEmpty {
                            let closingDifference = closingGrades.compactMap { grade -> Double? in
                                guard let close = grade.prediction.matchup.bettingLine?.closingHomeSpread else { return nil }
                                return abs(grade.prediction.projectedHomeSpread - close)
                            }.reduce(0, +) / Double(closingGrades.count)
                            LabeledContent("Avg projection vs closing spread", value: "\(closingDifference.formatted(.number.precision(.fractionLength(1)))) pts")
                        }
                    }
                    Section("Calibration") {
                        ForEach(Backtester.calibration(grades)) { bucket in
                            LabeledContent("\(bucket.lowerBound.formatted(.percent.precision(.fractionLength(0))))–\(bucket.upperBound.formatted(.percent.precision(.fractionLength(0)))) · \(bucket.games) games",
                                           value: "Observed \(bucket.observedRate.formatted(.percent.precision(.fractionLength(0))))")
                        }
                    }
                    Section("Recommendation backtest") {
                        let allBets = Backtester.bettingPerformance(grades)
                        let strongBets = Backtester.bettingPerformance(grades, strongOnly: true)
                        if allBets.graded == 0 {
                            Text("No qualifying historical recommendations yet.").foregroundStyle(.secondary)
                        } else {
                            LabeledContent("Qualified recommendations", value: allBets.graded.formatted())
                            LabeledContent("Record", value: "\(allBets.wins)-\(allBets.losses)-\(allBets.pushes)")
                            LabeledContent("Win rate excluding pushes", value: allBets.winRate.formatted(.percent.precision(.fractionLength(1))))
                            LabeledContent("Strong-edge record", value: "\(strongBets.wins)-\(strongBets.losses)-\(strongBets.pushes) · \(strongBets.winRate.formatted(.percent.precision(.fractionLength(1))))")
                            ForEach([BetKind.spread, .total, .moneyline], id: \.self) { kind in
                                let result = Backtester.bettingPerformance(grades, kind: kind)
                                let strong = Backtester.bettingPerformance(grades, kind: kind, strongOnly: true)
                                LabeledContent(kind.rawValue, value: result.graded == 0 ? "—" : "all \(result.winRate.formatted(.percent.precision(.fractionLength(0)))) · strong \(strong.winRate.formatted(.percent.precision(.fractionLength(0)))) (\(strong.graded))")
                            }
                            Text("Historical results use the same minimum edge thresholds shown in the Bets screen. They do not include sportsbook limits, line movement after publication, or transaction costs.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.navigationTitle("Accuracy")
            }
        }
    }
}

struct HistoryView: View {
    let bundles: [[Prediction]]
    var body: some View {
        NavigationStack {
            if bundles.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "clock", description: Text("Scheduled cloud runs will add immutable forecast snapshots here."))
            } else {
                List {
                    ForEach(Array(bundles.enumerated()), id: \.offset) { _, bundle in
                        if let first = bundle.first {
                            Section("\(first.generatedAt.formatted(date: .abbreviated, time: .shortened)) · \(first.modelVersion ?? "Legacy")") {
                                ForEach(bundle) { prediction in
                                    LabeledContent("\(prediction.matchup.away.abbreviation) at \(prediction.matchup.home.abbreviation)",
                                                   value: "\(prediction.predictedWinner.abbreviation) · \(prediction.confidence.formatted(.percent.precision(.fractionLength(0))))")
                                }
                            }
                        }
                    }
                }.navigationTitle("Forecast History")
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    private var teams: [String] {
        Set(model.predictions.flatMap { [$0.matchup.away.abbreviation, $0.matchup.home.abbreviation] }).sorted()
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    LabeledContent("Version", value: "MVP 0.9")
                    LabeledContent("Objective", value: "50% winner · 50% score")
                    LabeledContent("Runs per matchup", value: "10,000")
                    Text("Separate margin and total estimates combine team ratings with consensus market inputs. Confidence is recalibrated from prior seasons; weather, travel, QB and injury context are included when a configured feed supplies them.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Persistence") {
                    LabeledContent("Storage", value: model.storageLabel)
                    LabeledContent("Cloud sync", value: model.syncStatus)
                    if let lastUpdated = model.lastUpdated {
                        LabeledContent("Forecast generated", value: lastUpdated.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Freshness", value: Date.now.timeIntervalSince(lastUpdated) < 21_600 ? "Current" : "Refresh recommended")
                    }
                    if let sourceUpdatedAt = model.sourceUpdatedAt {
                        LabeledContent("Source data checked", value: sourceUpdatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let summary = model.validationSummary, let season = model.validationSeason {
                        LabeledContent("Held-out validation", value: "\(season) · \(summary.games) games")
                    }
                    Text("GitHub Actions runs the scheduled forecast; CloudKit synchronizes the published results.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Free data coverage") {
                    LabeledContent("Advanced metrics", value: "\(model.advancedTeamsLoaded) teams")
                    LabeledContent("Current injury impacts", value: "\(model.injuryTeamsLoaded) teams")
                    LabeledContent("Kickoff weather", value: "\(model.weatherGamesLoaded) games")
                    Text("Sources: nflverse injuries, depth charts and team summaries; Open-Meteo weather; locally calculated stadium travel. No subscription or API key required.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("QB / injury adjustments") {
                    Text("Adjust a team's offense from −10 to +10 points, then refresh forecasts. Use negative values for an unavailable quarterback or major offensive injuries.").font(.footnote).foregroundStyle(.secondary)
                    ForEach(teams, id: \.self) { team in
                        Stepper(value: Binding(get: { model.adjustment(for: team) }, set: { model.setAdjustment($0, for: team) }), in: -10...10, step: 0.5) {
                            LabeledContent(team, value: model.adjustment(for: team).formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))))
                        }
                    }
                    Button("Recalculate with adjustments") { Task { await model.refresh() } }
                }
            }.navigationTitle("Model Control")
        }
    }
}

enum SampleData {
    // Official NFL Week 6 schedule as of October 16, 2026. Ratings remain neutral
    // until a live performance-data pipeline is connected.
    static let matchups: [Matchup] = [
        game("HOU", "Houston Texans", at: "JAX", "Jacksonville Jaguars", kickoff: "2026-10-18T09:30:00-04:00"),
        game("CHI", "Chicago Bears", at: "ATL", "Atlanta Falcons", kickoff: "2026-10-18T13:00:00-04:00"),
        game("BAL", "Baltimore Ravens", at: "CLE", "Cleveland Browns", kickoff: "2026-10-18T13:00:00-04:00"),
        game("TEN", "Tennessee Titans", at: "IND", "Indianapolis Colts", kickoff: "2026-10-18T13:00:00-04:00"),
        game("NYJ", "New York Jets", at: "NE", "New England Patriots", kickoff: "2026-10-18T13:00:00-04:00"),
        game("NO", "New Orleans Saints", at: "NYG", "New York Giants", kickoff: "2026-10-18T13:00:00-04:00"),
        game("CAR", "Carolina Panthers", at: "PHI", "Philadelphia Eagles", kickoff: "2026-10-18T13:00:00-04:00"),
        game("PIT", "Pittsburgh Steelers", at: "TB", "Tampa Bay Buccaneers", kickoff: "2026-10-18T13:00:00-04:00"),
        game("ARI", "Arizona Cardinals", at: "LA", "Los Angeles Rams", kickoff: "2026-10-18T16:05:00-04:00"),
        game("LAC", "Los Angeles Chargers", at: "KC", "Kansas City Chiefs", kickoff: "2026-10-18T16:25:00-04:00"),
        game("BUF", "Buffalo Bills", at: "LV", "Las Vegas Raiders", kickoff: "2026-10-18T16:25:00-04:00"),
        game("DAL", "Dallas Cowboys", at: "GB", "Green Bay Packers", kickoff: "2026-10-18T20:20:00-04:00"),
        game("WAS", "Washington Commanders", at: "SF", "San Francisco 49ers", kickoff: "2026-10-19T20:15:00-04:00")
    ]

    private static func game(
        _ awayAbbreviation: String,
        _ awayName: String,
        at homeAbbreviation: String,
        _ homeName: String,
        kickoff: String
    ) -> Matchup {
        Matchup(
            week: 6,
            kickoff: ISO8601DateFormatter().date(from: kickoff)!,
            away: Team(abbreviation: awayAbbreviation, name: awayName, offensiveRating: 0, defensiveRating: 0),
            home: Team(abbreviation: homeAbbreviation, name: homeName, offensiveRating: 0, defensiveRating: 0)
        )
    }
}
