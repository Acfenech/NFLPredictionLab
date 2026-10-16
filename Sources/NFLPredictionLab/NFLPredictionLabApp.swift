import SwiftUI
import Charts
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
    @State private var selection: AppDestination? = .dashboard
    @StateObject private var model = AppModel()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("This Week") {
                    DestinationRow(.dashboard)
                    DestinationRow(.forecasts)
                    DestinationRow(.bets)
                }
                Section("Analysis") {
                    DestinationRow(.simulations)
                    DestinationRow(.accuracy)
                    DestinationRow(.history)
                }
                Section("System") {
                    DestinationRow(.model)
                    DestinationRow(.guide)
                }
            }
            .navigationTitle("NFL Prediction Lab")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            Group {
                switch selection ?? .dashboard {
                case .dashboard: WeeklyDashboardView(model: model, navigate: { selection = $0 })
                case .forecasts: PredictionsView(predictions: model.predictions, season: model.season, week: model.week, feedStatus: model.status, isRefreshing: model.isRefreshing) { Task { await model.refresh() } }
                case .bets: BettingView(predictions: model.predictions, grades: model.gradedPredictions)
                case .simulations: SimulationView(predictions: model.predictions)
                case .accuracy: AccuracyView(grades: model.gradedPredictions, archiveCount: model.archiveCount,
                                             validationSummary: model.validationSummary, validationSeason: model.validationSeason,
                                             trainingGames: model.trainingGames,
                                             rollingValidationSummary: model.rollingValidationSummary,
                                             rollingValidationSeasons: model.rollingValidationSeasons)
                case .history: HistoryView(bundles: model.archiveBundles)
                case .model: SettingsView(model: model)
                case .guide: UserGuideView()
                }
            }
        }
        .tint(AppTheme.accent)
        .frame(minWidth: 900, minHeight: 620)
        .task { await model.refresh() }
    }
}

enum AppDestination: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard", forecasts = "Matchups", bets = "Betting"
    case simulations = "Simulations", accuracy = "Accuracy", history = "History"
    case model = "Model & Data", guide = "User Guide"
    var id: Self { self }
    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .forecasts: "sportscourt.fill"
        case .bets: "chart.bar.doc.horizontal.fill"
        case .simulations: "waveform.path.ecg"
        case .accuracy: "chart.line.uptrend.xyaxis"
        case .history: "clock.arrow.circlepath"
        case .model: "slider.horizontal.3"
        case .guide: "book.closed.fill"
        }
    }
}

private struct DestinationRow: View {
    let destination: AppDestination
    init(_ destination: AppDestination) { self.destination = destination }
    var body: some View { Label(destination.rawValue, systemImage: destination.icon).tag(destination) }
}

struct WeeklyDashboardView: View {
    @ObservedObject var model: AppModel
    let navigate: (AppDestination) -> Void
    private var strongest: Prediction? { model.predictions.max { $0.confidence < $1.confidence } }
    private var closest: Prediction? { model.predictions.min { abs($0.projectedHomeSpread) < abs($1.projectedHomeSpread) } }
    private var flagged: Int { model.predictions.filter { $0.reviewFlag != nil }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.week > 0 ? "Week \(model.week) Intelligence" : "Weekly Intelligence")
                            .font(.largeTitle.bold())
                        Text(model.season > 0 ? "\(String(model.season)) regular season" : "Loading current season")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await model.refresh() } } label: {
                        Label(model.isRefreshing ? "Updating…" : "Refresh", systemImage: "arrow.clockwise")
                    }.buttonStyle(.borderedProminent).disabled(model.isRefreshing)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                    MetricCard(title: "Games", value: model.predictions.count.formatted(), subtitle: "This week", icon: "sportscourt.fill", color: .blue)
                    MetricCard(title: "Top confidence", value: strongest?.confidence.formatted(.percent.precision(.fractionLength(0))) ?? "—", subtitle: strongest.map { "\($0.predictedWinner.abbreviation) vs \($0.predictedWinner.abbreviation == $0.matchup.home.abbreviation ? $0.matchup.away.abbreviation : $0.matchup.home.abbreviation)" } ?? "Loading", icon: "shield.checkered", color: .green)
                    MetricCard(title: "Closest game", value: closest.map { abs($0.projectedHomeSpread).formatted(.number.precision(.fractionLength(1))) + " pts" } ?? "—", subtitle: closest.map { "\($0.matchup.away.abbreviation) at \($0.matchup.home.abbreviation)" } ?? "Loading", icon: "equal.circle.fill", color: .orange)
                    MetricCard(title: "Review flags", value: flagged.formatted(), subtitle: flagged == 1 ? "Market disagreement" : "Market disagreements", icon: "exclamationmark.triangle.fill", color: .purple)
                }

                if model.isRefreshing && model.predictions.isEmpty {
                    LoadingCardsView()
                } else {
                    DashboardSection(title: "Featured matchups", action: "View all") { navigate(.forecasts) } content: {
                        VStack(spacing: 12) {
                            ForEach(Array(model.predictions.prefix(3))) { MatchupCard(prediction: $0) }
                        }
                    }
                }

                DashboardSection(title: "Data health", action: "Model & Data") { navigate(.model) } content: {
                    HStack(spacing: 18) {
                        StatusPill(title: "Metrics", value: "\(model.advancedTeamsLoaded) teams", ok: model.advancedTeamsLoaded >= 30)
                        StatusPill(title: "Injuries", value: "\(model.injuryTeamsLoaded) teams", ok: model.injuryTeamsLoaded > 0)
                        StatusPill(title: "Weather", value: "\(model.weatherGamesLoaded) games", ok: model.weatherGamesLoaded > 0)
                        Spacer()
                        if let date = model.lastUpdated { Text("Updated \(date, style: .relative)").font(.caption).foregroundStyle(.secondary) }
                    }
                    .cardStyle()
                }
            }.padding(24)
        }
        .background(AppTheme.canvas)
        .navigationTitle("Dashboard")
    }
}

struct UserGuideView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Quick start") {
                    GuideItem(icon: "1.circle.fill", title: "Start with the dashboard", detail: "Review the week’s top confidence, closest matchup, review flags and data health. Use Refresh to load the latest available records.")
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
                    GuideItem(icon: "arrow.clockwise", title: "Refresh", detail: "Rechecks live sources and recalculates forecasts. If one optional source is delayed, the app continues with the remaining data and reports coverage in Model & Data.")
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
    @State private var filter = "All"
    @State private var showAllPasses = false
    private var validatedKinds: Set<BetKind> {
        Set([BetKind.spread, .total, .moneyline].filter { kind in
            let performance = Backtester.bettingPerformance(grades, kind: kind, strongOnly: true)
            return performance.graded >= 30 && performance.winRate >= 0.54
        })
    }
    private var displayedPredictions: [Prediction] {
        guard !showAllPasses else { return predictions }
        return Array(predictions
            .filter { $0.bettingRecommendations.contains { $0.strength != .pass } }
            .sorted { ($0.bettingRecommendations.map(\.edge).max() ?? 0) > ($1.bettingRecommendations.map(\.edge).max() ?? 0) }
            .prefix(5))
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if validatedKinds.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("No validated bets this week", systemImage: "shield.lefthalf.filled").font(.title3.bold()).foregroundStyle(.orange)
                            Text("Every market is currently a Pass. A market needs at least 30 held-out strong-edge samples and a 54% win rate before it can become actionable.").foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                    Picker("Market", selection: $filter) {
                        ForEach(["All", "Spread", "Total", "Moneyline"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented)
                    Toggle("Show every passed matchup", isOn: $showAllPasses)
                }
                ForEach(displayedPredictions) { prediction in
                    Section("\(prediction.matchup.away.abbreviation) at \(prediction.matchup.home.abbreviation)") {
                        if prediction.bettingRecommendations.isEmpty {
                            Text("Pass · market line unavailable").foregroundStyle(.secondary)
                        } else {
                            ForEach(prediction.bettingRecommendations.filter { filter == "All" || $0.kind.rawValue == filter }) { recommendation in
                                let validated = validatedKinds.contains(recommendation.kind)
                                let displayStrength: BetStrength = validated ? recommendation.strength : .pass
                                let evidence = Backtester.bettingPerformance(grades, kind: recommendation.kind, strongOnly: true)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(recommendation.kind.rawValue).fontWeight(.semibold)
                                        Spacer()
                                        Label(validated ? displayStrength.rawValue : "Not validated", systemImage: validated ? "checkmark.seal.fill" : "lock.fill")
                                            .foregroundStyle(displayStrength == .strong ? .green : displayStrength == .lean ? .orange : .secondary)
                                    }
                                    Text(displayStrength == .pass ? "Pass on \(recommendation.selection)" : recommendation.selection)
                                    Text(recommendation.rationale).font(.caption).foregroundStyle(.secondary)
                                    Text("Evidence: \(evidence.graded) strong-edge samples · \(evidence.winRate.formatted(.percent.precision(.fractionLength(1)))) wins")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }.padding(.vertical, 3)
                            }
                        }
                        if let flag = prediction.reviewFlag {
                            Label(flag, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                Section("Responsible use") {
                    Text("Lines can move and no projection guarantees a result. Verify the current price and player status independently. Use only amounts you can afford to lose.")
                        .font(.footnote).foregroundStyle(.secondary)
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
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(predictions) { prediction in
                        NavigationLink { MatchupDetail(prediction: prediction) } label: {
                            MatchupCard(prediction: prediction)
                        }.buttonStyle(.plain)
                    }
                }.padding(24)
            }
            .background(AppTheme.canvas)
            .navigationTitle(week > 0 ? String(format: "%d Week %d Matchups", season, week) : "NFL Matchups")
            .toolbar { Button(action: refresh) { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(isRefreshing) }
            .safeAreaInset(edge: .bottom) {
                Label(feedStatus, systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary).padding(8)
                    .background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 6)
            }
        }
    }
}

struct MatchupDetail: View {
    let prediction: Prediction
    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Text(prediction.matchup.kickoff.formatted(date: .complete, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 20) {
                        TeamMark(abbreviation: prediction.matchup.away.abbreviation, highlighted: prediction.predictedWinner.abbreviation == prediction.matchup.away.abbreviation)
                        Text(prediction.awayScore.formatted(.number.precision(.fractionLength(0)))).font(.system(size: 42, weight: .bold, design: .rounded))
                        Text("–").font(.title).foregroundStyle(.tertiary)
                        Text(prediction.homeScore.formatted(.number.precision(.fractionLength(0)))).font(.system(size: 42, weight: .bold, design: .rounded))
                        TeamMark(abbreviation: prediction.matchup.home.abbreviation, highlighted: prediction.predictedWinner.abbreviation == prediction.matchup.home.abbreviation)
                    }
                    Label("\(prediction.predictedWinner.name) · \(prediction.confidence.formatted(.percent.precision(.fractionLength(1)))) confidence", systemImage: "shield.checkered")
                        .font(.headline).foregroundStyle(AppTheme.confidence(prediction.confidence))
                    HStack(spacing: 24) {
                        LabeledContent("Away win", value: (1 - prediction.homeWinProbability).formatted(.percent.precision(.fractionLength(1))))
                        LabeledContent("Home win", value: prediction.homeWinProbability.formatted(.percent.precision(.fractionLength(1))))
                    }.font(.caption)
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
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
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: factor.homeEdge >= 0 ? "arrow.right.circle.fill" : "arrow.left.circle.fill")
                            .foregroundStyle(abs(factor.homeEdge) >= 2 ? AppTheme.accent : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            LabeledContent(factor.name, value: factor.homeEdge.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))))
                        Text(factor.detail).font(.caption).foregroundStyle(.secondary)
                        }
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
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(predictions) { p in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("\(p.matchup.away.abbreviation) at \(p.matchup.home.abbreviation)").font(.headline)
                                Spacer()
                                Text("\(p.simulations.formatted()) runs").font(.caption).foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("\(p.matchup.away.abbreviation) \((1 - p.homeWinProbability).formatted(.percent.precision(.fractionLength(1))))").fontWeight(.semibold)
                                Spacer()
                                Text("\(p.matchup.home.abbreviation) \(p.homeWinProbability.formatted(.percent.precision(.fractionLength(1))))").fontWeight(.semibold)
                            }
                            GeometryReader { proxy in
                                HStack(spacing: 0) {
                                    Rectangle().fill(awayColor(p)).frame(width: proxy.size.width * (1 - p.homeWinProbability))
                                    Rectangle().fill(homeColor(p))
                                }.clipShape(Capsule())
                            }.frame(height: 10).accessibilityLabel("\(p.matchup.away.abbreviation) \((1 - p.homeWinProbability).formatted(.percent)), \(p.matchup.home.abbreviation) \(p.homeWinProbability.formatted(.percent))")
                            Text("Upset probability: \((1 - p.confidence).formatted(.percent.precision(.fractionLength(1))))")
                                .font(.caption).foregroundStyle(.secondary)
                    if let s = p.simulationSummary {
                        Text("80% range: \(p.matchup.away.abbreviation) \(s.awayLow.formatted(.number.precision(.fractionLength(0))))–\(s.awayHigh.formatted(.number.precision(.fractionLength(0)))) · \(p.matchup.home.abbreviation) \(s.homeLow.formatted(.number.precision(.fractionLength(0))))–\(s.homeHigh.formatted(.number.precision(.fractionLength(0))))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Most common score: \(p.matchup.away.abbreviation) \(s.mostLikelyAwayScore) – \(p.matchup.home.abbreviation) \(s.mostLikelyHomeScore)")
                            .font(.caption)
                    }
                        }.cardStyle()
                    }
                }.padding(24)
            }.background(AppTheme.canvas).navigationTitle("Simulation Center")
        }
    }
    private func awayColor(_ p: Prediction) -> Color { p.homeWinProbability < 0.5 ? AppTheme.accent : .secondary.opacity(0.35) }
    private func homeColor(_ p: Prediction) -> Color { p.homeWinProbability >= 0.5 ? AppTheme.accent : .secondary.opacity(0.35) }
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
                let calibrationBuckets = Backtester.calibration(grades)
                List {
                    Section("Performance overview") {
                        HStack(spacing: 28) {
                            VStack(alignment: .leading) {
                                Text(summary.winnerAccuracy.formatted(.percent.precision(.fractionLength(0)))).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(AppTheme.accent)
                                Text("Winner accuracy").font(.caption).foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading) {
                                Text(summary.meanAbsoluteScoreError.formatted(.number.precision(.fractionLength(1)))).font(.system(size: 34, weight: .bold, design: .rounded))
                                Text("Mean score error").font(.caption).foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading) {
                                Text(summary.meanBrierScore.formatted(.number.precision(.fractionLength(3)))).font(.system(size: 34, weight: .bold, design: .rounded))
                                Text("Brier score · lower is better").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 8)
                    }
                    Section("Probability calibration") {
                        Chart {
                            ForEach(calibrationBuckets) { bucket in
                                LineMark(x: .value("Predicted", (bucket.lowerBound + bucket.upperBound) / 2), y: .value("Observed", bucket.observedRate))
                                PointMark(x: .value("Predicted", (bucket.lowerBound + bucket.upperBound) / 2), y: .value("Observed", bucket.observedRate))
                                    .symbolSize(Double(max(30, bucket.games * 2)))
                            }
                            RuleMark(y: .value("Perfect", 0.5)).foregroundStyle(.secondary.opacity(0.25))
                        }
                        .frame(height: 210)
                        Text("Dot size reflects sample size. A well-calibrated model's observed results rise with its predicted confidence.").font(.caption).foregroundStyle(.secondary)
                    }
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
                        LabeledContent("MVP 1.0 winner accuracy", value: summary.winnerAccuracy.formatted(.percent.precision(.fractionLength(0))))
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
                        ForEach(calibrationBuckets) { bucket in
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
    @State private var search = ""
    @State private var adjustedOnly = false
    @State private var confirmReset = false
    private var teams: [String] {
        Set(model.predictions.flatMap { [$0.matchup.away.abbreviation, $0.matchup.home.abbreviation] })
            .filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
            .filter { !adjustedOnly || model.adjustment(for: $0) != 0 }
            .sorted()
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    LabeledContent("Version", value: "MVP 1.0")
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
                    TextField("Search teams", text: $search)
                    Toggle("Show adjusted teams only", isOn: $adjustedOnly)
                    ForEach(teams, id: \.self) { team in
                        Stepper(value: Binding(get: { model.adjustment(for: team) }, set: { model.setAdjustment($0, for: team) }), in: -10...10, step: 0.5) {
                            LabeledContent(team, value: model.adjustment(for: team).formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))))
                        }
                    }
                    HStack {
                        Button("Reset all", role: .destructive) { confirmReset = true }.disabled(model.teamAdjustments.isEmpty)
                        Spacer()
                        Button("Recalculate forecasts") { Task { await model.refresh() } }.buttonStyle(.borderedProminent)
                    }
                }
            }.navigationTitle("Model Control")
                .confirmationDialog("Reset every manual team adjustment?", isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Reset all adjustments", role: .destructive) { model.resetAllAdjustments() }
                    Button("Cancel", role: .cancel) { }
                }
        }
    }
}

enum AppTheme {
    static let accent = Color(red: 0.08, green: 0.38, blue: 0.78)
    static let canvas = Color.primary.opacity(0.035)
    static func confidence(_ value: Double) -> Color {
        value >= 0.70 ? .green : value >= 0.58 ? accent : .orange
    }
}

private extension View {
    func cardStyle() -> some View {
        self.padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

private struct TeamMark: View {
    let abbreviation: String
    let highlighted: Bool
    var body: some View {
        Text(abbreviation)
            .font(.headline.monospaced().bold())
            .foregroundStyle(highlighted ? .white : .primary)
            .frame(width: 48, height: 48)
            .background(highlighted ? AppTheme.accent : Color.secondary.opacity(0.12), in: Circle())
            .accessibilityLabel(abbreviation)
    }
}

struct MatchupCard: View {
    let prediction: Prediction
    private var awayWins: Bool { prediction.predictedWinner.abbreviation == prediction.matchup.away.abbreviation }
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label(prediction.matchup.kickoff.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(prediction.confidence < 0.55 ? "TOSS-UP" : "\(prediction.predictedWinner.abbreviation) FAVORED")
                    .font(.caption2.bold()).tracking(0.6)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .foregroundStyle(AppTheme.confidence(prediction.confidence))
                    .background(AppTheme.confidence(prediction.confidence).opacity(0.12), in: Capsule())
            }
            HStack(spacing: 18) {
                TeamMark(abbreviation: prediction.matchup.away.abbreviation, highlighted: awayWins)
                VStack(spacing: 2) {
                    Text(prediction.awayScore.formatted(.number.precision(.fractionLength(0))))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("AWAY").font(.caption2).foregroundStyle(.secondary)
                }
                Text("–").font(.title2).foregroundStyle(.tertiary)
                VStack(spacing: 2) {
                    Text(prediction.homeScore.formatted(.number.precision(.fractionLength(0))))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("HOME").font(.caption2).foregroundStyle(.secondary)
                }
                TeamMark(abbreviation: prediction.matchup.home.abbreviation, highlighted: !awayWins)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(prediction.confidence.formatted(.percent.precision(.fractionLength(0))))
                        .font(.title2.bold()).foregroundStyle(AppTheme.confidence(prediction.confidence))
                    Text("confidence").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(spacing: 18) {
                if let line = prediction.matchup.bettingLine {
                    if let spread = line.homeSpread { Label("Market \(spread.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))))", systemImage: "arrow.left.and.right") }
                    if let total = line.total { Label("O/U \(total.formatted(.number.precision(.fractionLength(1))))", systemImage: "sum") }
                } else { Label("Line pending", systemImage: "clock") }
                Spacer()
                if let weather = prediction.matchup.context?.weatherSummary { Label(weather, systemImage: "cloud.sun") }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let flag = prediction.reviewFlag {
                Label(flag, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.cardStyle()
    }
}

private struct MetricCard: View {
    let title: String, value: String, subtitle: String, icon: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: icon).foregroundStyle(color); Spacer(); Text(title).font(.caption).foregroundStyle(.secondary) }
            Text(value).font(.title.bold()).contentTransition(.numericText())
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.cardStyle()
    }
}

private struct DashboardSection<Content: View>: View {
    let title: String, action: String
    let handler: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(title).font(.title2.bold()); Spacer(); Button(action, action: handler).buttonStyle(.plain).foregroundStyle(AppTheme.accent) }
            content()
        }
    }
}

private struct StatusPill: View {
    let title: String, value: String
    let ok: Bool
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(ok ? .green : .orange).frame(width: 8, height: 8)
            VStack(alignment: .leading) { Text(title).font(.caption2).foregroundStyle(.secondary); Text(value).font(.caption.bold()) }
        }
    }
}

private struct LoadingCardsView: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16).fill(.secondary.opacity(0.10)).frame(height: 150).overlay { ProgressView() }
            }
        }.accessibilityLabel("Loading matchup data")
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
