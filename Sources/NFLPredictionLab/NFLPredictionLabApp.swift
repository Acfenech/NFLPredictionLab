import SwiftUI
import Charts
#if canImport(PredictionCore)
import PredictionCore
#endif

@main
struct NFLPredictionLabApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(\.sizeCategory, .extraLarge)
        }
    }
}

struct DashboardView: View {
    @State private var selection: AppDestination? = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @StateObject private var model = AppModel()
    @StateObject private var bankroll = BankrollStore()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section("Betting") {
                    DestinationRow(.dashboard)
                    DestinationRow(.forecasts)
                    DestinationRow(.bets)
                    DestinationRow(.accuracy)
                }
                Section("Research") {
                    DestinationRow(.simulations)
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
                case .dashboard: WeeklyDashboardView(model: model, bankroll: bankroll, navigate: { selection = $0 })
                case .forecasts: PredictionsView(predictions: model.predictions, season: model.season, week: model.week, feedStatus: model.status, isRefreshing: model.isRefreshing) { Task { await model.refresh() } }
                case .bets: BettingView(predictions: model.predictions, grades: model.historicalValidationGrades, bankroll: bankroll)
                case .simulations: SimulationView(predictions: model.predictions)
                case .accuracy: AccuracyView(grades: model.gradedPredictions, archiveCount: model.archiveCount,
                                             validationSummary: model.validationSummary, validationSeason: model.validationSeason,
                                             trainingGames: model.trainingGames,
                                             rollingValidationSummary: model.rollingValidationSummary,
                                             rollingValidationSeasons: model.rollingValidationSeasons,
                                             historicalValidationGrades: model.historicalValidationGrades)
                case .history: HistoryView(bundles: model.archiveBundles)
                case .model: SettingsView(model: model)
                case .guide: UserGuideView()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(AppTheme.accent)
        .frame(minWidth: 1200, minHeight: 620)
        .onAppear {
#if os(macOS)
            columnVisibility = .detailOnly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { columnVisibility = .all }
#endif
        }
        .onChange(of: selection) { _, _ in
#if os(macOS)
            columnVisibility = .detailOnly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { columnVisibility = .all }
#endif
        }
        .task { await model.refresh() }
    }
}

enum AppDestination: String, CaseIterable, Identifiable {
    case dashboard = "This Week", forecasts = "Picks", bets = "Bet Slip"
    case simulations = "Simulations", accuracy = "Results", history = "History"
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

private struct DashboardWagerCard: View {
    let title: String
    let category: String
    let detail: String
    let rationale: String
    let stake: Double
    let odds: Int
    let probability: Double
    let tint: Color
    let badge: String?
    let status: String
    let source: String
    let weakestLeg: String?

    var body: some View {
        let profit = OddsMath.profit(stake: stake, american: odds) ?? 0
        let totalReturn = OddsMath.totalReturn(stake: stake, american: odds) ?? 0
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    Text(category.uppercased())
                        .font(.caption2.bold()).foregroundStyle(tint)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(tint.opacity(0.12), in: Capsule())
                    Text(status.uppercased())
                        .font(.caption2.bold()).foregroundStyle(status == "Validated" ? Color.green : Color.orange)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background((status == "Validated" ? Color.green : Color.orange).opacity(0.12), in: Capsule())
                    if let badge {
                        Label(badge, systemImage: "star.fill")
                            .font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(AppTheme.accent, in: Capsule())
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(rationale).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let weakestLeg { Text("Weakest leg: \(weakestLeg)").font(.caption2).foregroundStyle(.orange) }
                Label(source, systemImage: "clock.badge.checkmark")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("WIN → \(totalReturn.formatted(.currency(code: "USD"))) returned (+\(profit.formatted(.currency(code: "USD")))) · LOSS → $0 returned (-\(stake.formatted(.currency(code: "USD"))))")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                Text(stake.formatted(.currency(code: "USD"))).font(.title3.bold()).monospacedDigit()
                Text("suggested stake").font(.caption2).foregroundStyle(.secondary)
                Text(odds.formatted(.number.sign(strategy: .always()))).font(.headline.monospacedDigit())
                Text("\(probability.formatted(.percent.precision(.fractionLength(1)))) win estimate")
                    .font(.caption2).foregroundStyle(tint).monospacedDigit()
            }
        }
        .cardStyle()
    }
}

struct WeeklyDashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var bankroll: BankrollStore
    let navigate: (AppDestination) -> Void
    @State private var showSingles = true
    @State private var showGameParlays = true
    @State private var showPlayerParlays = true
    private var strongest: Prediction? { model.predictions.max { $0.confidence < $1.confidence } }
    private var closest: Prediction? { model.predictions.min { abs($0.projectedHomeSpread) < abs($1.projectedHomeSpread) } }
    private var flagged: Int { model.predictions.filter { $0.reviewFlag != nil }.count }
    private var validatedKinds: Set<BetKind> {
        Set([BetKind.spread, .total, .moneyline].filter { kind in
            Backtester.bettingValidation(model.historicalValidationGrades, kind: kind).isValidated
        })
    }
    private var strongestBets: [(prediction: Prediction, recommendation: BetRecommendation, probability: Double)] {
        var ranked: [(prediction: Prediction, recommendation: BetRecommendation, probability: Double)] = []
        for prediction in model.predictions {
            for recommendation in prediction.bettingRecommendations {
                let probability: Double
                if let estimated = recommendation.estimatedWinProbability {
                    probability = estimated
                } else {
                switch recommendation.kind {
                case .moneyline:
                    probability = recommendation.selection.hasPrefix(prediction.matchup.home.abbreviation) ? prediction.homeWinProbability : 1 - prediction.homeWinProbability
                case .spread: probability = min(0.90, max(0.50, 1 / (1 + exp(-recommendation.edge / 7.0))))
                case .total: probability = min(0.90, max(0.50, 1 / (1 + exp(-recommendation.edge / 9.0))))
                }
                }
                ranked.append((prediction: prediction, recommendation: recommendation, probability: probability))
            }
        }
        ranked.sort {
            ($0.recommendation.expectedValue ?? 0) + $0.recommendation.edge / 1_000 >
            ($1.recommendation.expectedValue ?? 0) + $1.recommendation.edge / 1_000
        }
        let strong = ranked.filter { $0.recommendation.strength == BetStrength.strong }
        return strong.isEmpty ? Array(ranked.prefix(5)) : Array(strong.prefix(5))
    }
    private var fundedWeeklyAmount: Double { min(max(0, bankroll.weeklyBudget), max(0, bankroll.bankroll)) }
    private var marketUpdateLabel: String {
        guard let latestMarketUpdate else { return "update pending" }
        return "updated \(latestMarketUpdate.formatted(date: .abbreviated, time: .shortened))"
    }
    private func defaultOdds(for item: (prediction: Prediction, recommendation: BetRecommendation, probability: Double)) -> Int {
        let fallback: Int
        if item.recommendation.kind == .moneyline, let line = item.prediction.matchup.bettingLine {
            fallback = item.recommendation.selection.hasPrefix(item.prediction.matchup.home.abbreviation)
            ? (line.homeMoneyline ?? -110) : (line.awayMoneyline ?? -110)
        } else { fallback = -110 }
        return bankroll.odds(for: "\(item.prediction.matchup.gameKey)-\(item.recommendation.id)", default: fallback)
    }
    private var singleStakes: [String: Double] {
        let weights = strongestBets.map {
            let concentration = pow(max(0.1, $0.recommendation.edge), 0.35 + bankroll.riskLevel * 1.65)
            let upside = $0.recommendation.kind == .moneyline ? 1 + bankroll.returnLevel : 1 + bankroll.returnLevel * 0.2
            return 2 * concentration * upside
        }
        let total = weights.reduce(0, +)
        return Dictionary(uniqueKeysWithValues: zip(strongestBets, weights).map { item, weight in
            ("\(item.prediction.matchup.gameKey)-\(item.recommendation.id)", total > 0 ? fundedWeeklyAmount * 0.75 * weight / total : 0)
        })
    }
    private var dashboardGameParlays: [(id: String, title: String, legs: [(prediction: Prediction, recommendation: BetRecommendation, probability: Double)], share: Double)] {
        let candidates = model.predictions.flatMap { prediction in
            prediction.bettingRecommendations.filter { $0.strength == .strong }.map { recommendation in
                (prediction: prediction, recommendation: recommendation, probability: recommendation.estimatedWinProbability ?? {
                    switch recommendation.kind {
                    case .moneyline: return recommendation.selection.hasPrefix(prediction.matchup.home.abbreviation) ? prediction.homeWinProbability : 1 - prediction.homeWinProbability
                    case .spread: return min(0.90, max(0.50, 1 / (1 + exp(-recommendation.edge / 7.0))))
                    case .total: return min(0.90, max(0.50, 1 / (1 + exp(-recommendation.edge / 9.0))))
                    }
                }())
            }
        }
        func uniqueGames(_ source: [(prediction: Prediction, recommendation: BetRecommendation, probability: Double)], count: Int) -> [(prediction: Prediction, recommendation: BetRecommendation, probability: Double)] {
            var games = Set<String>()
            return source.filter { games.insert($0.prediction.matchup.gameKey).inserted }.prefix(count).map { $0 }
        }
        let lower = uniqueGames(candidates.filter { $0.recommendation.kind != .moneyline }
            .sorted { $0.recommendation.edge > $1.recommendation.edge }, count: 2)
        let balanced = uniqueGames(candidates.sorted {
            $0.recommendation.edge * ($0.recommendation.kind == .moneyline ? 0.85 : 1) >
            $1.recommendation.edge * ($1.recommendation.kind == .moneyline ? 0.85 : 1)
        }, count: 3)
        let upside = uniqueGames(candidates.sorted {
            $0.recommendation.edge * ($0.recommendation.kind == .moneyline ? 1 + bankroll.returnLevel : 1) >
            $1.recommendation.edge * ($1.recommendation.kind == .moneyline ? 1 + bankroll.returnLevel : 1)
        }, count: 4)
        return [
            ("lower", "Lower Variance · 2 legs", lower, 0.07),
            ("balanced", "Balanced · 3 legs", balanced, 0.06),
            ("upside", "High Upside · 4 legs", upside, 0.04)
        ].filter { !$0.legs.isEmpty }
    }
    private var dashboardPlayerParlays: [RecommendedPlayerParlay] {
        SharedBettingPlan.playerParlays(predictions: model.predictions)
    }
    private var dashboardPlanOutcomes: [(stake: Double, odds: Int, probability: Double)] {
        let singles = strongestBets.map { item in
            (singleStakes["\(item.prediction.matchup.gameKey)-\(item.recommendation.id)"] ?? 0,
             defaultOdds(for: item), item.probability)
        }
        let games = dashboardGameParlays.map { parlay in
            let multiplier = parlay.id == "lower" ? 1.25 - bankroll.riskLevel * 0.5 : parlay.id == "upside" ? 0.5 + bankroll.riskLevel : 1
            return (fundedWeeklyAmount * parlay.share * multiplier,
                    bankroll.odds(for: "parlay-\(parlay.id)", default: OddsMath.parlayAmerican(parlay.legs.map { defaultOdds(for: $0) }) ?? 100),
                    parlay.legs.map(\.probability).reduce(1, *))
        }
        let players = dashboardPlayerParlays.map { parlay in
            (fundedWeeklyAmount * parlay.budgetShare,
             OddsMath.parlayAmerican(parlay.legs.map(\.quote.odds)) ?? 100,
             parlay.legs.map(\.fairProbability).reduce(1, *))
        }
        return singles + games + players
    }
    private var completeProjectedWins: Int {
        min(dashboardPlanOutcomes.count, max(0, Int(dashboardPlanOutcomes.map(\.probability).reduce(0, +).rounded())))
    }
    private var completeScenarioReturn: Double {
        dashboardPlanOutcomes.sorted { $0.probability > $1.probability }.prefix(completeProjectedWins).reduce(0) {
            $0 + (OddsMath.totalReturn(stake: $1.stake, american: $1.odds) ?? 0)
        }
    }
    private var completeStake: Double { dashboardPlanOutcomes.map(\.stake).reduce(0, +) }
    private var singlesStake: Double { strongestBets.reduce(0) { $0 + (singleStakes["\($1.prediction.matchup.gameKey)-\($1.recommendation.id)"] ?? 0) } }
    private var gameParlayStake: Double {
        dashboardGameParlays.reduce(0) { result, parlay in
            let multiplier = parlay.id == "lower" ? 1.25 - bankroll.riskLevel * 0.5 : parlay.id == "upside" ? 0.5 + bankroll.riskLevel : 1
            return result + fundedWeeklyAmount * parlay.share * multiplier
        }
    }
    private var playerParlayStake: Double { dashboardPlayerParlays.reduce(0) { $0 + fundedWeeklyAmount * $1.budgetShare } }
    private var latestMarketUpdate: Date? {
        model.predictions.flatMap { $0.playerProps ?? [] }.compactMap(\.updatedAt).max() ?? model.lastUpdated
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.week > 0 ? "Week \(model.week) Betting Plan" : "Weekly Betting Plan")
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
                    MetricCard(title: "Weekly budget", value: bankroll.weeklyBudget.formatted(.currency(code: "USD")), subtitle: "of \(bankroll.bankroll.formatted(.currency(code: "USD"))) bankroll", icon: "dollarsign.circle.fill", color: .blue)
                    MetricCard(title: "Planned wagers", value: dashboardPlanOutcomes.count.formatted(), subtitle: "Singles and parlays", icon: "bolt.fill", color: .orange)
                    MetricCard(title: "Projected record", value: dashboardPlanOutcomes.isEmpty ? "—" : "\(completeProjectedWins)–\(max(0, dashboardPlanOutcomes.count - completeProjectedWins))", subtitle: "Complete-plan scenario", icon: "checkmark.circle.fill", color: .green)
                    MetricCard(title: "Risk warnings", value: flagged.formatted(), subtitle: flagged == 1 ? "Market disagreement" : "Market disagreements", icon: "exclamationmark.triangle.fill", color: .purple)
                }

                if model.isRefreshing && model.predictions.isEmpty {
                    LoadingCardsView()
                } else {
                    DashboardSection(title: "Complete weekly recommendations", action: "Open Bet Slip") { navigate(.bets) } content: {
                        VStack(spacing: 12) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                                MetricCard(title: "Total planned stake", value: completeStake.formatted(.currency(code: "USD")), subtitle: "Across every wager", icon: "banknote.fill", color: .blue)
                                MetricCard(title: "Likely weekly result", value: dashboardPlanOutcomes.isEmpty ? "—" : "\(completeProjectedWins) wins · \(dashboardPlanOutcomes.count - completeProjectedWins) losses", subtitle: "Probability-ranked scenario", icon: "chart.bar.fill", color: .green)
                                MetricCard(title: "Scenario return", value: completeScenarioReturn.formatted(.currency(code: "USD")), subtitle: "Net \((completeScenarioReturn - completeStake).formatted(.currency(code: "USD")))", icon: "arrow.turn.up.right", color: .purple)
                                MetricCard(title: "Plan mix", value: "\(singlesStake.formatted(.currency(code: "USD"))) · \(gameParlayStake.formatted(.currency(code: "USD"))) · \(playerParlayStake.formatted(.currency(code: "USD")))", subtitle: "Singles · game · player; \(max(0, fundedWeeklyAmount - completeStake).formatted(.currency(code: "USD"))) held back", icon: "chart.pie.fill", color: .orange)
                            }
                            if strongestBets.isEmpty {
                                ContentUnavailableView("Recommendations are loading", systemImage: "arrow.clockwise", description: Text("The complete weekly plan will appear after matchup and market data arrive."))
                            } else {
                                DisclosureGroup(isExpanded: $showSingles) {
                                    VStack(spacing: 10) {
                                        ForEach(Array(strongestBets.enumerated()), id: \.offset) { index, item in
                                            let key = "\(item.prediction.matchup.gameKey)-\(item.recommendation.id)"
                                            let validated = validatedKinds.contains(item.recommendation.kind)
                                            Button { navigate(.bets) } label: {
                                                DashboardWagerCard(
                                                    title: item.recommendation.selection,
                                                    category: "Single · \(item.recommendation.kind.rawValue)",
                                                    detail: "\(item.prediction.matchup.away.abbreviation) at \(item.prediction.matchup.home.abbreviation)",
                                                    rationale: item.recommendation.rationale,
                                                    stake: singleStakes[key] ?? 0,
                                                    odds: defaultOdds(for: item),
                                                    probability: item.probability,
                                                    tint: validated ? .green : .orange,
                                                    badge: index == 0 ? "BEST BET" : nil,
                                                    status: validated ? "Validated" : "Model-ranked",
                                                    source: "\(item.prediction.matchup.bettingLine?.source ?? "Consensus market") · \(marketUpdateLabel)",
                                                    weakestLeg: nil
                                                )
                                            }.buttonStyle(.plain)
                                        }
                                    }.padding(.top, 8)
                                } label: {
                                    Label("Single-game bets · \(strongestBets.count)", systemImage: "sportscourt.fill").font(.headline)
                                }
                            }
                            if !dashboardGameParlays.isEmpty {
                                DisclosureGroup(isExpanded: $showGameParlays) {
                                    VStack(spacing: 10) {
                                        ForEach(Array(dashboardGameParlays.enumerated()), id: \.offset) { _, parlay in
                                            let odds = bankroll.odds(for: "parlay-\(parlay.id)", default: OddsMath.parlayAmerican(parlay.legs.map { defaultOdds(for: $0) }) ?? 100)
                                            let probability = parlay.legs.map(\.probability).reduce(1, *)
                                            let multiplier = parlay.id == "lower" ? 1.25 - bankroll.riskLevel * 0.5 : parlay.id == "upside" ? 0.5 + bankroll.riskLevel : 1
                                            let stake = fundedWeeklyAmount * parlay.share * multiplier
                                            let weakest = parlay.legs.min { $0.probability < $1.probability }
                                            let validated = parlay.legs.allSatisfy { validatedKinds.contains($0.recommendation.kind) }
                                            Button { navigate(.bets) } label: {
                                                DashboardWagerCard(
                                                    title: parlay.title, category: "Game Parlay",
                                                    detail: parlay.legs.map { $0.recommendation.selection }.joined(separator: " + "),
                                                    rationale: "Combines \(parlay.legs.count) model-ranked selections from separate games; every leg must win.",
                                                    stake: stake, odds: odds, probability: probability,
                                                    tint: .purple, badge: nil,
                                                    status: validated ? "Validated" : "Model-ranked",
                                                    source: "Calculated from displayed leg prices · \(marketUpdateLabel)",
                                                    weakestLeg: weakest.map { "\($0.recommendation.selection) · \($0.probability.formatted(.percent.precision(.fractionLength(1))))" }
                                                )
                                            }.buttonStyle(.plain)
                                        }
                                    }.padding(.top, 8)
                                } label: {
                                    Label("Game parlays · \(dashboardGameParlays.count)", systemImage: "square.stack.3d.up.fill").font(.headline)
                                }
                            }
                            if !dashboardPlayerParlays.isEmpty {
                                DisclosureGroup(isExpanded: $showPlayerParlays) {
                                    VStack(spacing: 10) {
                                        ForEach(Array(dashboardPlayerParlays.enumerated()), id: \.offset) { _, parlay in
                                            let odds = OddsMath.parlayAmerican(parlay.legs.map(\.quote.odds)) ?? 100
                                            let probability = parlay.legs.map(\.fairProbability).reduce(1, *)
                                            let stake = fundedWeeklyAmount * parlay.budgetShare
                                            let weakest = parlay.legs.min { $0.fairProbability < $1.fairProbability }
                                            Button { navigate(.bets) } label: {
                                                DashboardWagerCard(
                                                    title: parlay.title, category: "Player Parlay",
                                                    detail: parlay.legs.map { "\($0.quote.player) \($0.quote.selection) \($0.quote.point.formatted(.number.precision(.fractionLength(1))))" }.joined(separator: " + "),
                                                    rationale: parlay.rationale,
                                                    stake: stake, odds: odds, probability: probability,
                                                    tint: .blue, badge: nil,
                                                    status: "Market-ranked",
                                                    source: "Consensus player-prop prices · \(marketUpdateLabel)",
                                                    weakestLeg: weakest.map { "\($0.quote.player) \($0.quote.selection) \($0.quote.point.formatted(.number.precision(.fractionLength(1)))) · \($0.fairProbability.formatted(.percent.precision(.fractionLength(1))))" }
                                                )
                                            }.buttonStyle(.plain)
                                        }
                                    }.padding(.top, 8)
                                } label: {
                                    Label("Player parlays · \(dashboardPlayerParlays.count)", systemImage: "person.3.fill").font(.headline)
                                }
                            }
                        }
                    }
                }

                Button { navigate(.bets) } label: {
                    Label("Open Bet Slip & Weekly Outcome", systemImage: "list.clipboard.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)

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
        .navigationTitle("This Week")
    }
}

struct UserGuideView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Quick start") {
                    GuideItem(icon: "1.circle.fill", title: "Start with This Week", detail: "Review the weekly budget, number of strong candidates, projected record, risk warnings and the five best opportunities. Use Refresh before making decisions.")
                    GuideItem(icon: "2.circle.fill", title: "Review Picks", detail: "Filter to Recommended or Needs Review, sort by opportunity, confidence or game time, then open a matchup to compare its game prediction, best available bet, market line and supporting factors.")
                    GuideItem(icon: "3.circle.fill", title: "Build the Bet Slip", detail: "Choose Historically Validated or Model-Ranked recommendations, confirm your strategy, review suggested stakes and replace estimated odds with the current bet365 price.")
                    GuideItem(icon: "4.circle.fill", title: "Check the weekly outcome", detail: "Use the decision summary to review predicted wins, losses, total returned and net result before entering any wagers at the sportsbook.")
                }

                Section("Screen guide") {
                    GuideItem(icon: "calendar", title: "This Week", detail: "The betting command center. It surfaces the strongest opportunities, bankroll exposure, projected weekly record and warnings that need attention.")
                    GuideItem(icon: "sportscourt.fill", title: "Picks", detail: "The sortable, filterable matchup board. Each card separates the predicted game winner from the best available wager and shows the market line with its home-team label.")
                    GuideItem(icon: "list.clipboard.fill", title: "Bet Slip", detail: "A three-tab planning workspace: Weekly Plan contains bankroll controls and suggested singles, Parlays isolates multi-leg options, and All Markets provides detailed evidence, odds and manual wager entry for every matchup.")
                    GuideItem(icon: "chart.line.uptrend.xyaxis", title: "Results", detail: "Historical grading, validation records, calibration and performance by market. Use this evidence to judge whether a recommendation type deserves trust.")
                    GuideItem(icon: "slider.horizontal.3", title: "Model & Data", detail: "Data freshness, coverage, source status and manual injury or quarterback adjustments. Resolve warnings here before relying on a projection.")
                }

                Section("Data sources") {
                    GuideItem(icon: "football.fill", title: "nflverse", detail: "Schedule, final scores, consensus betting lines, injuries, depth charts and weekly team statistics. The app derives recent form, efficiency, success, explosiveness, pressure and turnover-regression signals from these records.")
                    GuideItem(icon: "cloud.sun.fill", title: "Open-Meteo", detail: "Forecast temperature, wind and precipitation near the stadium at kickoff. Weather may affect scoring and passing efficiency; forecasts can change as kickoff approaches.")
                    GuideItem(icon: "location.fill", title: "Stadium and travel data", detail: "Bundled stadium coordinates are used to estimate the away team’s travel distance. This is context, not live tracking.")
                    GuideItem(icon: "chart.line.uptrend.xyaxis", title: "Market consensus", detail: "Available spread, total and moneyline fields from nflverse are comparison inputs. They may lag a sportsbook and are not guaranteed to be the current or closing price.")
                    GuideItem(icon: "dollarsign.arrow.circlepath", title: "Optional current moneylines", detail: "When the scheduled worker has a The Odds API key, the app overlays the median available US-book moneyline. This is a general comparison price, not a guaranteed bet365 quote.")
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
                    GuideItem(icon: "bolt.fill", title: "Strong edge", detail: "The model-market difference clears the higher threshold. Spreads and totals become actionable only after 30 held-out samples and a 54% win rate. Moneylines require 100 samples and at least a 3% price-adjusted return on historical stakes.")
                    Text("Moneyline probability removes the sportsbook’s estimated margin before comparison. Spread and total records count wins, losses and pushes. Historical results do not include price changes, limits, fees or the exact line available to you.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Bankroll planner") {
                    GuideItem(icon: "dollarsign.circle.fill", title: "Bankroll", detail: "Enter the amount reserved for betting. It is stored privately on this device and is never transferred or connected to a sportsbook.")
                    GuideItem(icon: "calendar.badge.clock", title: "Weekly wager amount", detail: "Enter an exact dollar amount and select Update (or press Return). The betting plan recalculates only after you submit the amount, while user-entered wager fields show how much remains and warn when the plan exceeds the weekly amount or bankroll.")
                    GuideItem(icon: "slider.horizontal.2.square", title: "Risk level", detail: "Choose Conservative, Balanced or Aggressive to control how strongly the weekly amount is concentrated in the largest model edges. It does not change forecast probabilities.")
                    GuideItem(icon: "arrow.up.right.circle.fill", title: "Return target", detail: "Choose Steady, Balanced or Upside to control preference for steadier allocations versus higher-payout markets. Higher upside also means greater variance and does not imply better expected results.")
                    GuideItem(icon: "arrow.counterclockwise.circle.fill", title: "Reset to Recommended", detail: "Restores the balanced planning defaults: 35% risk and 40% return preference. It does not change the bankroll, weekly amount, wagers, or entered odds.")
                    GuideItem(icon: "lock.shield.fill", title: "Validated recommendations", detail: "Allocates money only when a market passes its historical sample and performance gate. If none qualifies, the validated recommendation remains $0 regardless of strategy settings.")
                    GuideItem(icon: "eye.trianglebadge.exclamationmark", title: "Model-ranked recommendations", detail: "The Bet Slip segmented control reveals this week’s strongest model edges even when they failed historical validation. They can receive suggested stakes, remain orange and explicitly marked Unvalidated, and do not gain credibility merely because this mode is enabled.")
                    GuideItem(icon: "star.fill", title: "Best Bet badge", detail: "The highest model edge receives a BEST BET badge inside the single-game allocation list, keeping it in context with the complete weekly plan. Expand that wager to review its probability, odds, outcome amounts and rationale. Best Bet means highest-ranked—not guaranteed.")
                    GuideItem(icon: "rectangle.3.group.fill", title: "Unified weekly plan", detail: "Weekly Plan combines single-game bets, game parlays and player parlays under one funded weekly limit. When both parlay types are available, the balanced starting mix is approximately 75% singles, 17% game parlays and 8% player parlays; risk settings adjust game-parlay weights. The combined scenario record, return and net include every displayed allocation.")
                    GuideItem(icon: "checklist", title: "Pre-bet checklist", detail: "Before placing a wager, enter the exact Bet365 price, confirm weekly exposure remains inside the budget, check that forecast data are current, and note whether the market has passed its historical grade. An incomplete item is a warning for review, not an automatic prediction of failure.")
                    GuideItem(icon: "square.stack.3d.up.fill", title: "Three parlay plans", detail: "Lower Variance uses two side/total legs, Balanced uses three diversified edges, and High Upside uses four legs with extra moneyline preference. Games are not repeated inside one parlay. Suggested stakes require validation unless you explicitly enable speculative recommendations.")
                    GuideItem(icon: "person.crop.circle.badge.plus", title: "Player Parlays", detail: "Open Bet Slip, then Player Parlays to compare Lower Variance, Balanced and High Upside plans. The ranker evaluates available Over and Under prices, removes estimated vig using the opposing side, scores freshness and sportsbook coverage, and searches diversified cross-game combinations. Expand a plan to review each leg’s no-vig probability, then replace every line and combined price with the exact Bet365 offer. These are top market-ranked combinations, not validated player-performance projections.")
                    GuideItem(icon: "equal.square.fill", title: "Odds and returns", detail: "Every wager settles in one of two ways: a win returns the full stake plus profit, while a loss returns $0. The weekly outlook rounds the combined win probabilities to a projected win count, assigns those wins to the highest-probability selections, and totals their full returns. It is a scenario forecast, not a guarantee. Enter the exact American odds shown by your sportsbook because every displayed return changes with the price.")
                    GuideItem(icon: "chart.pie.fill", title: "Weekly exposure footer", detail: "The bottom bar changes with the selected Bet Slip tab and always shows total user-entered exposure against the funded weekly limit. Player Parlays displays its own suggested exposure and all-win return rather than repeating the singles scenario.")
                }

                Section("Accuracy terms") {
                    GuideItem(icon: "checkmark.circle", title: "Winner accuracy", detail: "The percentage of games where the predicted winner won.")
                    GuideItem(icon: "scope", title: "Mean score error", detail: "The average absolute difference between each team’s predicted and actual score. Lower is better.")
                    GuideItem(icon: "gauge.with.dots.needle.50percent", title: "Brier score", detail: "Measures probability accuracy and penalizes confident mistakes. Lower is better; 0 is perfect.")
                    GuideItem(icon: "equal.circle", title: "Balanced score", detail: "The app’s combined evaluation gives winner accuracy and score accuracy equal importance.")
                    GuideItem(icon: "lock.shield", title: "Held-out validation", detail: "The model is evaluated on games or seasons that were not used to select its settings. This is more trustworthy than performance on training data.")
                    GuideItem(icon: "calendar.badge.checkmark", title: "Five-season walk-forward training", detail: "Candidate settings are compared season by season using only earlier results, with more recent validation seasons receiving more weight. The newest completed season remains an outer holdout for the displayed evaluation; after grading, all completed seasons are used to fit the next production forecast.")
                }

                Section("Refresh, history and adjustments") {
                    GuideItem(icon: "arrow.clockwise", title: "Refresh", detail: "Rechecks live sources and recalculates forecasts. If one optional source is delayed, the app continues with the remaining data and reports coverage in Model & Data.")
                    GuideItem(icon: "clock.arrow.circlepath", title: "History", detail: "Stores forecast snapshots so results can be graded later without rewriting what the model originally predicted.")
                    GuideItem(icon: "slider.horizontal.3", title: "QB / injury adjustment", detail: "A manual point adjustment changes a team’s offensive outlook. Negative values represent a downgrade. Use sparingly and recalculate after editing.")
                }

                Section("Important limitations") {
                    Text("This is a private decision-support tool, not financial advice or a sportsbook connection. The app never places bets. Data can be delayed, incomplete or revised; injuries and weather can change; markets can move; weekly predicted outcomes will often be wrong; and every wager can lose. Verify the current line and player status independently, and never risk money you cannot afford to lose.")
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

@MainActor
final class BankrollStore: ObservableObject {
    static let recommendedRisk = 0.35
    static let recommendedReturn = 0.40
    @Published var bankroll: Double { didSet { save() } }
    @Published var weeklyBudget: Double { didSet { save() } }
    @Published var riskLevel: Double { didSet { save() } }
    @Published var returnLevel: Double { didSet { save() } }
    @Published var manualStakes: [String: Double] { didSet { save() } }
    @Published var enteredOdds: [String: Int] { didSet { save() } }

    private static let key = "bankrollPlanner.v1"
    private struct Snapshot: Codable {
        let bankroll, weeklyBudget, riskLevel, returnLevel: Double
        let manualStakes: [String: Double]
        let enteredOdds: [String: Int]?
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            bankroll = saved.bankroll; weeklyBudget = saved.weeklyBudget
            riskLevel = saved.riskLevel; returnLevel = saved.returnLevel; manualStakes = saved.manualStakes
            enteredOdds = saved.enteredOdds ?? [:]
        } else {
            bankroll = 1_000; weeklyBudget = 50
            riskLevel = Self.recommendedRisk; returnLevel = Self.recommendedReturn
            manualStakes = [:]; enteredOdds = [:]
        }
    }

    var manualTotal: Double { manualStakes.values.reduce(0, +) }
    func stakeBinding(for key: String) -> Binding<Double> {
        Binding(get: { self.manualStakes[key] ?? 0 }, set: { value in
            self.manualStakes[key] = max(0, value)
        })
    }
    func odds(for key: String, default fallback: Int) -> Int { enteredOdds[key] ?? fallback }
    func oddsBinding(for key: String, default fallback: Int) -> Binding<Int> {
        Binding(get: { self.enteredOdds[key] ?? fallback }, set: { value in
            if value != 0 { self.enteredOdds[key] = value }
        })
    }
    func clearWeeklyWagers() { manualStakes = [:] }
    func resetAllocationPreferences() {
        riskLevel = Self.recommendedRisk
        returnLevel = Self.recommendedReturn
    }
    private func save() {
        let snapshot = Snapshot(bankroll: max(0, bankroll), weeklyBudget: max(0, weeklyBudget), riskLevel: riskLevel, returnLevel: returnLevel, manualStakes: manualStakes, enteredOdds: enteredOdds)
        if let data = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

private struct RecommendedAllocation: Identifiable {
    let id: String
    let matchup: String
    let recommendation: BetRecommendation
    let amount: Double
    let odds: Int
    let modelWinProbability: Double
}

private struct ParlayLeg: Identifiable {
    let id: String
    let matchup: String
    let recommendation: BetRecommendation
    let validated: Bool
    let odds: Int
    let modelWinProbability: Double
}

private struct ParlayPlan: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let risk: String
    let legs: [ParlayLeg]
    let budgetShare: Double
    var isValidated: Bool { !legs.isEmpty && legs.allSatisfy(\.validated) }
    func isFundable(showingUnvalidated: Bool) -> Bool { isValidated || (showingUnvalidated && !legs.isEmpty) }
}

private struct ManualPlayerPropLeg: Identifiable, Hashable {
    let id = UUID()
    let player: String
    let selection: String
    let odds: Int
}

private struct PlayerPropCandidate: Identifiable {
    var id: String { "\(gameKey)|\(quote.id)" }
    let gameKey: String
    let matchup: String
    let quote: PlayerPropQuote
    let fairProbability: Double
    let estimatedHold: Double
    let qualityScore: Double
}

private struct RecommendedPlayerParlay: Identifiable {
    let id: String
    let title: String
    let rationale: String
    let legs: [PlayerPropCandidate]
    let budgetShare: Double
}

private enum SharedBettingPlan {
    static func playerParlays(predictions: [Prediction]) -> [RecommendedPlayerParlay] {
        let candidates = predictions.flatMap { prediction -> [PlayerPropCandidate] in
            let quotes = prediction.playerProps ?? []
            return quotes.compactMap { quote in
                guard quote.bookmakers >= 4, (-200...175).contains(quote.odds),
                      let rawProbability = OddsMath.impliedProbability(american: quote.odds) else { return nil }
                let oppositeName = quote.selection.caseInsensitiveCompare("Over") == .orderedSame ? "Under" : "Over"
                guard let opposite = quotes.first(where: {
                    $0.player == quote.player && $0.marketKey == quote.marketKey && abs($0.point - quote.point) < 0.01 &&
                    $0.selection.caseInsensitiveCompare(oppositeName) == .orderedSame
                }), let oppositeProbability = OddsMath.impliedProbability(american: opposite.odds) else { return nil }
                let probabilityTotal = rawProbability + oppositeProbability
                guard probabilityTotal > 0 else { return nil }
                let fairProbability = rawProbability / probabilityTotal
                let hold = max(0, probabilityTotal - 1)
                let ageHours = quote.updatedAt.map { max(0, Date.now.timeIntervalSince($0) / 3_600) } ?? 24
                let freshness = max(0.65, 1 - min(ageHours, 48) / 140)
                let coverage = min(1, Double(quote.bookmakers) / 8)
                return PlayerPropCandidate(gameKey: prediction.matchup.gameKey,
                    matchup: "\(prediction.matchup.away.abbreviation) at \(prediction.matchup.home.abbreviation)", quote: quote,
                    fairProbability: fairProbability, estimatedHold: hold,
                    qualityScore: fairProbability * 0.62 + coverage * 0.25 + freshness * 0.13 - hold * 0.30)
            }
        }
        enum Mode { case lowerVariance, balanced, upside }
        func bestCombination(count: Int, mode: Mode) -> [PlayerPropCandidate] {
            let pool = Array(candidates.sorted { $0.qualityScore > $1.qualityScore }.prefix(32))
            var best: [PlayerPropCandidate] = [], bestScore = -Double.infinity
            func legScore(_ candidate: PlayerPropCandidate) -> Double {
                switch mode {
                case .lowerVariance: return log(max(0.01, candidate.fairProbability)) * 1.8 + candidate.qualityScore
                case .balanced: return log(max(0.01, candidate.fairProbability)) + candidate.qualityScore * 1.3
                case .upside:
                    let payout = candidate.quote.odds > 0 ? Double(candidate.quote.odds) / 100 : 100 / Double(-candidate.quote.odds)
                    return log(max(0.01, candidate.fairProbability)) * 0.65 + log(1 + payout) * 0.55 + candidate.qualityScore
                }
            }
            func search(_ start: Int, _ chosen: [PlayerPropCandidate], _ players: Set<String>, _ games: Set<String>, _ score: Double) {
                if chosen.count == count { if score > bestScore { bestScore = score; best = chosen }; return }
                guard start < pool.count, pool.count - start >= count - chosen.count else { return }
                for index in start..<pool.count {
                    let candidate = pool[index]
                    guard !players.contains(candidate.quote.player), !games.contains(candidate.gameKey) else { continue }
                    search(index + 1, chosen + [candidate], players.union([candidate.quote.player]), games.union([candidate.gameKey]), score + legScore(candidate))
                }
            }
            search(0, [], [], [], 0)
            return best
        }
        return [
            RecommendedPlayerParlay(id: "player-lower", title: "Lower Variance · 2 legs", rationale: "Top two no-vig probabilities with strong market coverage from separate games.", legs: bestCombination(count: 2, mode: .lowerVariance), budgetShare: 0.04),
            RecommendedPlayerParlay(id: "player-balanced", title: "Balanced · 3 legs", rationale: "Top combined price, coverage and no-vig probability across separate matchups.", legs: bestCombination(count: 3, mode: .balanced), budgetShare: 0.025),
            RecommendedPlayerParlay(id: "player-upside", title: "High Upside · 4 legs", rationale: "Higher-payout sides that retain the strongest available market-quality scores.", legs: bestCombination(count: 4, mode: .upside), budgetShare: 0.015)
        ].filter { !$0.legs.isEmpty }
    }
}

private struct SubmittedCurrencyEditor: View {
    let label: String
    let value: Double
    let onCommit: (Double) -> Void
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(_ label: String, value: Double, onCommit: @escaping (Double) -> Void) {
        self.label = label
        self.value = value
        self.onCommit = onCommit
        self._draft = State(initialValue: value.formatted(.number.precision(.fractionLength(2))))
    }

    private var parsedValue: Double? {
        let cleaned = draft
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Double(cleaned), amount >= 0 else { return nil }
        return amount
    }

    private var hasUncommittedChange: Bool {
        guard let parsedValue else { return false }
        return abs(parsedValue - value) >= 0.005
    }

    var body: some View {
        HStack {
            Text("$")
            TextField(label, text: $draft)
                .focused($isFocused)
                .frame(width: 110)
                .accessibilityLabel(label)
                .onSubmit(commit)
            Button("Update", action: commit)
                .disabled(!hasUncommittedChange)
        }
        .onChange(of: value) { _, newValue in
            guard !isFocused else { return }
            draft = newValue.formatted(.number.precision(.fractionLength(2)))
        }
    }

    private func commit() {
        guard let parsedValue else { return }
        draft = parsedValue.formatted(.number.precision(.fractionLength(2)))
        isFocused = false
        guard abs(parsedValue - value) >= 0.005 else { return }
        onCommit(parsedValue)
    }
}

struct BettingView: View {
    private enum BettingTab: String, CaseIterable {
        case plan = "Weekly Plan"
        case playerParlays = "Player Parlays"
        case gameParlays = "Game Parlays"
        case markets = "All Markets"
    }
    let predictions: [Prediction]
    let grades: [GradedPrediction]
    @ObservedObject var bankroll: BankrollStore
    private let validationByKind: [BetKind: BetValidationResult]
    private let evidenceByKind: [BetKind: BettingPerformance]
    @State private var filter = "All"
    @State private var showAllPasses = false
    @State private var showUnvalidatedRecommendations = true
    @State private var selectedTab: BettingTab = .plan
    @State private var showConfiguration = false
    @State private var showFinalReview = false
    @State private var expandedAllocationIDs: Set<String> = []
    @State private var playerName = ""
    @State private var playerPropSelection = ""
    @State private var playerPropOdds = -110
    @State private var playerPropLegs: [ManualPlayerPropLeg] = []
    @State private var playerPropSearch = ""
    @State private var playerPropMarket = "All"

    init(predictions: [Prediction], grades: [GradedPrediction], bankroll: BankrollStore) {
        self.predictions = predictions
        self.grades = grades
        self._bankroll = ObservedObject(wrappedValue: bankroll)
        let kinds: [BetKind] = [.spread, .total, .moneyline]
        self.validationByKind = Dictionary(uniqueKeysWithValues: kinds.map { kind in
            (kind, Backtester.bettingValidation(grades, kind: kind))
        })
        self.evidenceByKind = Dictionary(uniqueKeysWithValues: kinds.map { kind in
            (kind, Backtester.bettingPerformance(grades, kind: kind, strongOnly: true))
        })
    }
    private func defaultOdds(for recommendation: BetRecommendation, prediction: Prediction) -> Int {
        guard recommendation.kind == .moneyline, let line = prediction.matchup.bettingLine else { return -110 }
        return recommendation.selection.hasPrefix(prediction.matchup.home.abbreviation)
            ? (line.homeMoneyline ?? -110) : (line.awayMoneyline ?? -110)
    }
    private func estimatedWinProbability(for recommendation: BetRecommendation, prediction: Prediction) -> Double {
        if let estimated = recommendation.estimatedWinProbability { return estimated }
        switch recommendation.kind {
        case .moneyline:
            return recommendation.selection.hasPrefix(prediction.matchup.home.abbreviation)
                ? prediction.homeWinProbability : 1 - prediction.homeWinProbability
        case .spread:
            return min(0.90, max(0.50, 1 / (1 + exp(-recommendation.edge / 7.0))))
        case .total:
            return min(0.90, max(0.50, 1 / (1 + exp(-recommendation.edge / 9.0))))
        }
    }
    private var validatedKinds: Set<BetKind> {
        Set(validationByKind.compactMap { kind, validation in
            validation.isValidated ? kind : nil
        })
    }
    private var displayedPredictions: [Prediction] {
        guard !showAllPasses else { return predictions }
        return Array(predictions
            .filter { $0.bettingRecommendations.contains { $0.strength != .pass } }
            .sorted { ($0.bettingRecommendations.map(\.edge).max() ?? 0) > ($1.bettingRecommendations.map(\.edge).max() ?? 0) }
            .prefix(5))
    }
    private var availablePlayerProps: [PlayerPropQuote] {
        predictions.flatMap { $0.playerProps ?? [] }
            .sorted { lhs, rhs in
                if lhs.bookmakers != rhs.bookmakers { return lhs.bookmakers > rhs.bookmakers }
                return lhs.player < rhs.player
            }
    }
    private var filteredPlayerProps: [PlayerPropQuote] {
        availablePlayerProps.filter { quote in
            let matchesMarket = playerPropMarket == "All" || quote.marketName == playerPropMarket
            let needle = playerPropSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = needle.isEmpty || quote.player.localizedCaseInsensitiveContains(needle)
            return matchesMarket && matchesSearch
        }
    }
    private var recommendedPlayerParlays: [RecommendedPlayerParlay] {
        let candidates = predictions.flatMap { prediction -> [PlayerPropCandidate] in
            let quotes = prediction.playerProps ?? []
            return quotes.compactMap { quote in
                guard quote.bookmakers >= 4, (-200...175).contains(quote.odds),
                      let rawProbability = OddsMath.impliedProbability(american: quote.odds) else { return nil }
                let oppositeName = quote.selection.caseInsensitiveCompare("Over") == .orderedSame ? "Under" : "Over"
                guard let opposite = quotes.first(where: {
                    $0.player == quote.player && $0.marketKey == quote.marketKey &&
                    abs($0.point - quote.point) < 0.01 && $0.selection.caseInsensitiveCompare(oppositeName) == .orderedSame
                }), let oppositeProbability = OddsMath.impliedProbability(american: opposite.odds) else { return nil }
                let probabilityTotal = rawProbability + oppositeProbability
                guard probabilityTotal > 0 else { return nil }
                let fairProbability = rawProbability / probabilityTotal
                let hold = max(0, probabilityTotal - 1)
                let ageHours = quote.updatedAt.map { max(0, Date.now.timeIntervalSince($0) / 3_600) } ?? 24
                let freshness = max(0.65, 1 - min(ageHours, 48) / 140)
                let coverage = min(1, Double(quote.bookmakers) / 8)
                let quality = fairProbability * 0.62 + coverage * 0.25 + freshness * 0.13 - hold * 0.30
                return PlayerPropCandidate(
                    gameKey: prediction.matchup.gameKey,
                    matchup: "\(prediction.matchup.away.abbreviation) at \(prediction.matchup.home.abbreviation)",
                    quote: quote,
                    fairProbability: fairProbability,
                    estimatedHold: hold,
                    qualityScore: quality
                )
            }
        }

        enum RankingMode { case lowerVariance, balanced, upside }
        func bestCombination(count: Int, mode: RankingMode) -> [PlayerPropCandidate] {
            let pool = Array(candidates.sorted { $0.qualityScore > $1.qualityScore }.prefix(32))
            var best: [PlayerPropCandidate] = []
            var bestScore = -Double.infinity
            func legScore(_ candidate: PlayerPropCandidate) -> Double {
                switch mode {
                case .lowerVariance:
                    return log(max(0.01, candidate.fairProbability)) * 1.8 + candidate.qualityScore
                case .balanced:
                    return log(max(0.01, candidate.fairProbability)) + candidate.qualityScore * 1.3
                case .upside:
                    let payout = candidate.quote.odds > 0 ? Double(candidate.quote.odds) / 100 : 100 / Double(-candidate.quote.odds)
                    return log(max(0.01, candidate.fairProbability)) * 0.65 + log(1 + payout) * 0.55 + candidate.qualityScore
                }
            }
            func search(_ start: Int, _ chosen: [PlayerPropCandidate], _ players: Set<String>, _ games: Set<String>, _ score: Double) {
                if chosen.count == count {
                    if score > bestScore { bestScore = score; best = chosen }
                    return
                }
                guard start < pool.count, pool.count - start >= count - chosen.count else { return }
                for index in start..<pool.count {
                    let candidate = pool[index]
                    guard !players.contains(candidate.quote.player), !games.contains(candidate.gameKey) else { continue }
                    search(index + 1, chosen + [candidate], players.union([candidate.quote.player]), games.union([candidate.gameKey]), score + legScore(candidate))
                }
            }
            search(0, [], [], [], 0)
            return best
        }

        let plans = [
            RecommendedPlayerParlay(id: "player-lower", title: "Lower Variance · 2 legs",
                rationale: "Top two no-vig probabilities with strong market coverage from separate games.",
                legs: bestCombination(count: 2, mode: .lowerVariance), budgetShare: 0.04),
            RecommendedPlayerParlay(id: "player-balanced", title: "Balanced · 3 legs",
                rationale: "Top combined price, coverage and no-vig probability across separate matchups.",
                legs: bestCombination(count: 3, mode: .balanced), budgetShare: 0.025),
            RecommendedPlayerParlay(id: "player-upside", title: "High Upside · 4 legs",
                rationale: "Higher-payout sides that retain the strongest available market-quality scores.",
                legs: bestCombination(count: 4, mode: .upside), budgetShare: 0.015)
        ]
        return plans.filter { !$0.legs.isEmpty }
    }
    private func allocations(gameParlaysAvailable: Bool, playerParlaysAvailable: Bool) -> [RecommendedAllocation] {
        let ranked = predictions.flatMap { prediction in
            prediction.bettingRecommendations.map { (prediction, $0) }
        }.sorted { lhs, rhs in
            let lhsScore = (lhs.1.expectedValue ?? 0) + lhs.1.edge / 1_000
            let rhsScore = (rhs.1.expectedValue ?? 0) + rhs.1.edge / 1_000
            return lhsScore > rhsScore
        }
        let validated = ranked.filter { validatedKinds.contains($0.1.kind) && $0.1.strength == .strong }
        let bestAvailable = ranked.filter { $0.1.strength == .strong }
        let eligible = showUnvalidatedRecommendations
            ? Array((bestAvailable.isEmpty ? ranked : bestAvailable).prefix(5))
            : validated
        guard !eligible.isEmpty else { return [] }
        let weights = eligible.map { _, recommendation -> Double in
            let strength = recommendation.strength == .strong ? 2.0 : 1.0
            let concentration = pow(max(0.1, recommendation.edge), 0.35 + bankroll.riskLevel * 1.65)
            let upside = recommendation.kind == .moneyline ? 1 + bankroll.returnLevel : 1 + bankroll.returnLevel * 0.2
            return strength * concentration * upside
        }
        let totalWeight = weights.reduce(0, +)
        let singlesShare: Double = gameParlaysAvailable && playerParlaysAvailable ? 0.75
            : gameParlaysAvailable ? 0.80
            : playerParlaysAvailable ? 0.92 : 1.0
        let available = min(max(0, bankroll.weeklyBudget), max(0, bankroll.bankroll)) * singlesShare
        return zip(eligible, weights).map { pair, weight in
            let (prediction, recommendation) = pair
            let key = "\(prediction.matchup.gameKey)-\(recommendation.id)"
            return RecommendedAllocation(
                id: key,
                matchup: "\(prediction.matchup.away.abbreviation) at \(prediction.matchup.home.abbreviation)",
                recommendation: recommendation,
                amount: totalWeight > 0 ? available * weight / totalWeight : 0,
                odds: bankroll.odds(for: key, default: defaultOdds(for: recommendation, prediction: prediction)),
                modelWinProbability: estimatedWinProbability(for: recommendation, prediction: prediction)
            )
        }.sorted { $0.amount > $1.amount }
    }
    private var parlayPlans: [ParlayPlan] {
        let candidates = predictions.flatMap { prediction in
            prediction.bettingRecommendations
                .filter { $0.strength == .strong }
                .map { recommendation in
                    ParlayLeg(id: "\(prediction.matchup.gameKey)-\(recommendation.id)",
                              matchup: "\(prediction.matchup.away.abbreviation) at \(prediction.matchup.home.abbreviation)",
                              recommendation: recommendation,
                              validated: validatedKinds.contains(recommendation.kind),
                              odds: defaultOdds(for: recommendation, prediction: prediction),
                              modelWinProbability: estimatedWinProbability(for: recommendation, prediction: prediction))
                }
        }
        func uniqueGames(_ source: [ParlayLeg], count: Int) -> [ParlayLeg] {
            var games = Set<String>(), result: [ParlayLeg] = []
            for leg in source where !games.contains(leg.matchup) {
                games.insert(leg.matchup); result.append(leg)
                if result.count == count { break }
            }
            return result
        }
        let lowerVariance = uniqueGames(candidates
            .filter { $0.recommendation.kind != .moneyline }
            .sorted { $0.recommendation.edge > $1.recommendation.edge }, count: 2)
        let balanced = uniqueGames(candidates.sorted {
            let lhs = $0.recommendation.edge * ($0.recommendation.kind == .moneyline ? 0.85 : 1)
            let rhs = $1.recommendation.edge * ($1.recommendation.kind == .moneyline ? 0.85 : 1)
            return lhs > rhs
        }, count: 3)
        let highUpside = uniqueGames(candidates.sorted {
            let lhs = $0.recommendation.edge * ($0.recommendation.kind == .moneyline ? 1 + bankroll.returnLevel : 1)
            let rhs = $1.recommendation.edge * ($1.recommendation.kind == .moneyline ? 1 + bankroll.returnLevel : 1)
            return lhs > rhs
        }, count: 4)
        return [
            ParlayPlan(id: "lower", title: "Lower Variance", subtitle: "Two strongest side/total edges from separate games", risk: "2 legs", legs: lowerVariance, budgetShare: 0.07),
            ParlayPlan(id: "balanced", title: "Balanced", subtitle: "Three diversified model edges", risk: "3 legs", legs: balanced, budgetShare: 0.06),
            ParlayPlan(id: "upside", title: "High Upside", subtitle: "Four legs with added moneyline preference", risk: "4 legs", legs: highUpside, budgetShare: 0.04)
        ]
    }
    var body: some View {
        let currentParlayPlans = parlayPlans
        let currentPlayerParlays = recommendedPlayerParlays
        let gameParlaysAvailable = currentParlayPlans.contains {
            $0.isFundable(showingUnvalidated: showUnvalidatedRecommendations)
        }
        let playerParlaysAvailable = !currentPlayerParlays.isEmpty
        let currentAllocations = allocations(gameParlaysAvailable: gameParlaysAvailable,
                                             playerParlaysAvailable: playerParlaysAvailable)
        let bestBet = currentAllocations.max { lhs, rhs in
            let lhsEdge = lhs.modelWinProbability - (OddsMath.impliedProbability(american: lhs.odds) ?? 0)
            let rhsEdge = rhs.modelWinProbability - (OddsMath.impliedProbability(american: rhs.odds) ?? 0)
            return lhsEdge < rhsEdge
        }
        let fundedWeeklyAmount = min(bankroll.weeklyBudget, bankroll.bankroll)
        let playerSuggestedExposure = fundedWeeklyAmount * currentPlayerParlays.map(\.budgetShare).reduce(0, +)
        let playerMaximumReturn = currentPlayerParlays.reduce(0.0) { partial, parlay in
            let stake = min(bankroll.weeklyBudget, bankroll.bankroll) * parlay.budgetShare
            let odds = OddsMath.parlayAmerican(parlay.legs.map(\.quote.odds)) ?? 100
            return partial + (OddsMath.totalReturn(stake: stake, american: odds) ?? 0)
        }
        let playerParlayProbabilities = currentPlayerParlays.map { parlay in
            (id: parlay.id, probability: parlay.legs.map(\.fairProbability).reduce(1, *))
        }
        let playerIllustrativeWinCount = min(playerParlayProbabilities.count,
            max(0, Int(playerParlayProbabilities.map(\.probability).reduce(0, +).rounded())))
        let playerIllustrativeWinnerIDs = Set(playerParlayProbabilities
            .sorted { $0.probability > $1.probability }
            .prefix(playerIllustrativeWinCount).map(\.id))
        let playerIllustrativeReturn = currentPlayerParlays.reduce(0.0) { partial, parlay in
            guard playerIllustrativeWinnerIDs.contains(parlay.id) else { return partial }
            let stake = min(bankroll.weeklyBudget, bankroll.bankroll) * parlay.budgetShare
            let odds = OddsMath.parlayAmerican(parlay.legs.map(\.quote.odds)) ?? 100
            return partial + (OddsMath.totalReturn(stake: stake, american: odds) ?? 0)
        }
        let playerIllustrativeNet = playerIllustrativeReturn - playerSuggestedExposure
        let fundedGameParlays = currentParlayPlans.filter { $0.isFundable(showingUnvalidated: showUnvalidatedRecommendations) }
        let unifiedSingles = currentAllocations.map { allocation in
            (id: allocation.id, title: allocation.recommendation.selection, category: "Single",
             stake: allocation.amount, odds: allocation.odds, probability: allocation.modelWinProbability)
        }
        let unifiedGameParlays = fundedGameParlays.map { parlay in
            let riskMultiplier = parlay.id == "lower" ? 1.25 - bankroll.riskLevel * 0.5 : parlay.id == "upside" ? 0.5 + bankroll.riskLevel : 1.0
            let stake = fundedWeeklyAmount * parlay.budgetShare * riskMultiplier
            let calculatedOdds = OddsMath.parlayAmerican(parlay.legs.map(\.odds)) ?? 100
            return (id: "parlay-\(parlay.id)", title: "\(parlay.title) game parlay", category: "Game Parlay",
                    stake: stake, odds: bankroll.odds(for: "parlay-\(parlay.id)", default: calculatedOdds),
                    probability: parlay.legs.map(\.modelWinProbability).reduce(1, *))
        }
        let unifiedPlayerParlays = currentPlayerParlays.map { parlay in
            let odds = OddsMath.parlayAmerican(parlay.legs.map(\.quote.odds)) ?? 100
            return (id: parlay.id, title: "\(parlay.title) player parlay", category: "Player Parlay",
                    stake: fundedWeeklyAmount * parlay.budgetShare, odds: odds,
                    probability: parlay.legs.map(\.fairProbability).reduce(1, *))
        }
        let unifiedPlan = unifiedSingles + unifiedGameParlays + unifiedPlayerParlays
        let weeklyStake = unifiedPlan.map(\.stake).reduce(0, +)
        let weeklyWinCount = min(unifiedPlan.count, max(0, Int(unifiedPlan.map(\.probability).reduce(0, +).rounded())))
        let weeklyWinnerIDs = Set(unifiedPlan.sorted { $0.probability > $1.probability }.prefix(weeklyWinCount).map(\.id))
        let weeklyReturned = unifiedPlan.reduce(0.0) { partial, wager in
            weeklyWinnerIDs.contains(wager.id)
                ? partial + (OddsMath.totalReturn(stake: wager.stake, american: wager.odds) ?? 0) : partial
        }
        let weeklyNet = weeklyReturned - weeklyStake
        let latestPlayerPropUpdate = availablePlayerProps.compactMap(\.updatedAt).max()
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Bet Slip section", selection: $selectedTab) {
                    ForEach(BettingTab.allCases, id: \.self) { tab in
                        Text(tab == .plan ? "Weekly Plan · \(unifiedPlan.count)" :
                             tab == .playerParlays ? "Player Parlays · 3" :
                             tab == .gameParlays ? "Game Parlays · \(currentParlayPlans.count)" :
                             "All Markets · \(predictions.count)")
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
                List {
                if selectedTab == .plan {
                Section {
                    HStack(spacing: 28) {
                        VStack(alignment: .leading) {
                            Text(weeklyStake.formatted(.currency(code: "USD"))).font(.title2.bold()).monospacedDigit()
                            Text("Suggested stake").font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading) {
                            Text(unifiedPlan.isEmpty ? "—" : "\(weeklyWinCount)–\(unifiedPlan.count - weeklyWinCount)").font(.title2.bold()).monospacedDigit()
                            Text("Scenario record").font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading) {
                            Text(weeklyReturned.formatted(.currency(code: "USD"))).font(.title2.bold()).monospacedDigit()
                            Text("Scenario return").font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading) {
                            Text(weeklyNet.formatted(.currency(code: "USD").sign(strategy: .always()))).font(.title2.bold()).foregroundStyle(weeklyNet >= 0 ? Color.green : Color.red).monospacedDigit()
                            Text("Scenario net").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Text("Weekly scenario based on the highest-probability selections receiving the projected number of wins. Verify current odds and availability before placing any wager.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Label("This Week’s Decision Summary", systemImage: "chart.bar.fill")
                }

                if let bestBet {
                    Section("Pre-bet checklist") {
                        ChecklistRow(label: "Current price entered from Bet365", complete: bankroll.enteredOdds[bestBet.id] != nil)
                        ChecklistRow(label: "Weekly exposure is within budget", complete: bankroll.manualTotal <= min(bankroll.weeklyBudget, bankroll.bankroll))
                        ChecklistRow(label: "Forecast and market data are current", complete: predictions.compactMap(\.recalculatedAt).max().map { Date.now.timeIntervalSince($0) < 21_600 } ?? false)
                        ChecklistRow(label: "Historical market grade passed", complete: validatedKinds.contains(bestBet.recommendation.kind))
                    }
                }

                Section("Plan configuration") {
                    DisclosureGroup(isExpanded: $showConfiguration) {
                    HStack {
                        Label("Recommendation mode", systemImage: "scope")
                        Spacer()
                        Picker("Recommendation mode", selection: $showUnvalidatedRecommendations) {
                            Text("Historically validated").tag(false)
                            Text("Model-ranked picks").tag(true)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 175)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Bankroll").font(.caption).foregroundStyle(.secondary)
                            SubmittedCurrencyEditor("Available bankroll", value: bankroll.bankroll) { updatedAmount in
                                bankroll.bankroll = updatedAmount
                            }
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Weekly amount").font(.caption).foregroundStyle(.secondary)
                            SubmittedCurrencyEditor("Weekly wager amount", value: bankroll.weeklyBudget) { updatedAmount in
                                bankroll.weeklyBudget = updatedAmount
                            }
                        }
                    }
                    HStack {
                        Picker("Risk", selection: riskPreset) {
                            Text("Conservative").tag(0.15)
                            Text("Balanced").tag(BankrollStore.recommendedRisk)
                            Text("Aggressive").tag(0.85)
                        }.pickerStyle(.menu)
                        Picker("Return", selection: returnPreset) {
                            Text("Steady").tag(0.10)
                            Text("Balanced").tag(BankrollStore.recommendedReturn)
                            Text("Upside").tag(0.90)
                        }.pickerStyle(.menu)
                        Spacer()
                        Button {
                            withAnimation { bankroll.resetAllocationPreferences() }
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(abs(bankroll.riskLevel - BankrollStore.recommendedRisk) < 0.001 &&
                                  abs(bankroll.returnLevel - BankrollStore.recommendedReturn) < 0.001)
                    }
                    HStack {
                        Text("Entered: \(bankroll.manualTotal.formatted(.currency(code: "USD")))")
                        Text("·").foregroundStyle(.tertiary)
                        Text("Remaining: \(max(0, bankroll.weeklyBudget - bankroll.manualTotal).formatted(.currency(code: "USD")))")
                        Spacer()
                        Button("Clear", role: .destructive) { bankroll.clearWeeklyWagers() }
                            .disabled(bankroll.manualTotal == 0)
                    }.font(.caption)
                    if bankroll.manualTotal > bankroll.weeklyBudget {
                        Label("Entered wagers exceed the weekly amount by \((bankroll.manualTotal - bankroll.weeklyBudget).formatted(.currency(code: "USD"))).", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    if bankroll.weeklyBudget > bankroll.bankroll {
                        Label("Weekly amount cannot be fully funded by the current bankroll.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                    Text(showUnvalidatedRecommendations
                         ? "Model-ranked · \(riskLabel) risk · \(returnLabel) return. Select Update after changing the weekly amount."
                         : "Validated only · \(riskLabel) risk · \(returnLabel) return. Select Update after changing the weekly amount.")
                        .font(.caption).foregroundStyle(.secondary)
                    } label: {
                        HStack {
                            Text(showUnvalidatedRecommendations ? "Model-ranked" : "Validated only")
                            Text("· \(riskLabel) · \(returnLabel)").foregroundStyle(.secondary)
                            Spacer()
                            Text(bankroll.weeklyBudget.formatted(.currency(code: "USD"))).fontWeight(.semibold).monospacedDigit()
                        }
                    }
                }

                Section(showUnvalidatedRecommendations ? "Single-game allocations" : "Validated single-game allocations") {
                    if currentAllocations.isEmpty {
                        Label(showUnvalidatedRecommendations ? "$0 · matchup or market data unavailable" : "$0 · no market passes validation",
                              systemImage: showUnvalidatedRecommendations ? "eye.slash.fill" : "lock.shield.fill")
                            .font(.headline).foregroundStyle(.orange)
                        Text(showUnvalidatedRecommendations
                             ? "A weekly best pick cannot be calculated until matchup and market data are available."
                             : "The planner will distribute the funded weekly amount only across recommendations that satisfy the historical sample-size and win-rate gate.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        let predictedWinCount = min(currentAllocations.count, max(0, Int(currentAllocations.map(\.modelWinProbability).reduce(0, +).rounded())))
                        let predictedWinnerIDs = Set(currentAllocations.sorted { $0.modelWinProbability > $1.modelWinProbability }.prefix(predictedWinCount).map(\.id))
                        ForEach(currentAllocations, id: \.id) { allocation in
                            let allocationValidated = validatedKinds.contains(allocation.recommendation.kind)
                            let profit = OddsMath.profit(stake: allocation.amount, american: allocation.odds) ?? 0
                            let totalReturn = OddsMath.totalReturn(stake: allocation.amount, american: allocation.odds) ?? 0
                            let predictedToWin = predictedWinnerIDs.contains(allocation.id)
                            DisclosureGroup(isExpanded: allocationExpandedBinding(allocation.id)) {
                                VStack(alignment: .leading, spacing: 4) {
                                        Text("\(allocation.matchup) · \(allocation.recommendation.kind.rawValue) · \(allocationValidated ? "Historical grade passed" : "Historical grade pending · model-ranked")")
                                        .font(.caption).foregroundStyle(allocationValidated ? Color.secondary : Color.orange)
                                    Text("\(allocation.odds.formatted(.number.sign(strategy: .always()))) odds · Model chance: \(allocation.modelWinProbability.formatted(.percent.precision(.fractionLength(0)))) win · \((1 - allocation.modelWinProbability).formatted(.percent.precision(.fractionLength(0)))) loss")
                                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                    let marketProbability = OddsMath.impliedProbability(american: allocation.odds) ?? 0
                                    let currentEdge = allocation.modelWinProbability - marketProbability
                                    Label("Why this bet: model \(allocation.modelWinProbability.formatted(.percent.precision(.fractionLength(1)))) vs market \(marketProbability.formatted(.percent.precision(.fractionLength(1)))) · edge \(currentEdge.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())))",
                                          systemImage: "chart.line.uptrend.xyaxis")
                                        .font(.caption2).foregroundStyle(currentEdge > 0 ? Color.green : Color.red)
                                    if bankroll.enteredOdds[allocation.id] != nil {
                                        let baseline = defaultOdds(for: allocation.recommendation, prediction: predictions.first { "\($0.matchup.gameKey)-\(allocation.recommendation.id)" == allocation.id } ?? predictions[0])
                                        Text("Price movement: \(baseline.formatted(.number.sign(strategy: .always()))) → \(allocation.odds.formatted(.number.sign(strategy: .always())))")
                                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                    if currentEdge <= 0 {
                                        Label("Current price removes the model edge. Recheck Bet365 before placing.", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption2.bold()).foregroundStyle(.red)
                                    }
                                    Text("WIN → \(totalReturn.formatted(.currency(code: "USD"))) returned (+\(profit.formatted(.currency(code: "USD")))) · LOSS → $0 returned (-\(allocation.amount.formatted(.currency(code: "USD"))))")
                                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                    Label(predictedToWin ? "Illustrative scenario: WIN · \(totalReturn.formatted(.currency(code: "USD"))) returned" : "Illustrative scenario: LOSS · $0 returned",
                                          systemImage: predictedToWin ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.caption2.bold()).foregroundStyle(predictedToWin ? Color.green : Color.red).monospacedDigit()
                                    HStack {
                                        Spacer()
                                        Button(bankroll.manualStakes[allocation.id] == allocation.amount ? "Added to placed bets" : "Add to placed bets") {
                                            bankroll.manualStakes[allocation.id] = allocation.amount
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                }
                                .padding(.top, 4)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 8) {
                                            Text(allocation.recommendation.selection).fontWeight(.semibold)
                                            if allocation.id == bestBet?.id {
                                                Label("BEST BET", systemImage: "star.fill")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 3)
                                                    .background(AppTheme.accent, in: Capsule())
                                            }
                                        }
                                        Text("\(allocation.odds.formatted(.number.sign(strategy: .always()))) · \(allocation.modelWinProbability.formatted(.percent.precision(.fractionLength(0)))) model chance")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(allocation.amount.formatted(.currency(code: "USD"))).font(.headline).monospacedDigit()
                                        Text(allocationValidated ? "grade passed" : "grade pending").font(.caption2).foregroundStyle(allocationValidated ? Color.green : Color.orange)
                                    }
                                }
                            }
                        }
                        let totalStake = currentAllocations.map(\.amount).reduce(0, +)
                        let totalProfit = currentAllocations.reduce(0) { partial, allocation in
                            partial + (OddsMath.profit(stake: allocation.amount, american: allocation.odds) ?? 0)
                        }
                        let totalReturned = totalStake + totalProfit
                        let predictedReturned = currentAllocations.reduce(0) { partial, allocation in
                            guard predictedWinnerIDs.contains(allocation.id) else { return partial }
                            return partial + (OddsMath.totalReturn(stake: allocation.amount, american: allocation.odds) ?? 0)
                        }
                        let predictedNet = predictedReturned - totalStake
                        VStack(spacing: 5) {
                            LabeledContent(showUnvalidatedRecommendations ? "Total model-ranked stake" : "Total validated stake",
                                           value: totalStake.formatted(.currency(code: "USD")))
                            LabeledContent("Anticipated profit if every bet wins",
                                           value: totalProfit.formatted(.currency(code: "USD")))
                            LabeledContent("Total returned if every bet wins",
                                           value: totalReturned.formatted(.currency(code: "USD")))
                            LabeledContent("Illustrative scenario record",
                                           value: "\(predictedWinCount) wins · \(currentAllocations.count - predictedWinCount) losses")
                            LabeledContent("Illustrative scenario return",
                                           value: predictedReturned.formatted(.currency(code: "USD")))
                            LabeledContent("Illustrative scenario net",
                                           value: predictedNet.formatted(.currency(code: "USD").sign(strategy: .always())))
                        }
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    }
                }

                if !unifiedGameParlays.isEmpty || !unifiedPlayerParlays.isEmpty {
                    Section("Parlays included in weekly plan") {
                        ForEach(unifiedGameParlays, id: \.id) { wager in
                            let plan = currentParlayPlans.first { "parlay-\($0.id)" == wager.id }
                            let profit = OddsMath.profit(stake: wager.stake, american: wager.odds) ?? 0
                            let totalReturn = OddsMath.totalReturn(stake: wager.stake, american: wager.odds) ?? 0
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(plan?.subtitle ?? "Model-ranked legs from separate games")
                                        .font(.caption).foregroundStyle(.secondary)
                                    ForEach(plan?.legs ?? []) { leg in
                                        Text("• \(leg.recommendation.selection) · \(leg.matchup)")
                                            .font(.caption)
                                    }
                                    Text("\(wager.odds.formatted(.number.sign(strategy: .always()))) odds · Model chance: \(wager.probability.formatted(.percent.precision(.fractionLength(1)))) win · \((1 - wager.probability).formatted(.percent.precision(.fractionLength(1)))) loss")
                                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                    Text("WIN → \(totalReturn.formatted(.currency(code: "USD"))) returned (+\(profit.formatted(.currency(code: "USD")))) · LOSS → $0 returned (-\(wager.stake.formatted(.currency(code: "USD"))))")
                                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                    Label(weeklyWinnerIDs.contains(wager.id) ? "Illustrative scenario: WIN · \(totalReturn.formatted(.currency(code: "USD"))) returned" : "Illustrative scenario: LOSS · $0 returned",
                                          systemImage: weeklyWinnerIDs.contains(wager.id) ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.caption2.bold()).foregroundStyle(weeklyWinnerIDs.contains(wager.id) ? Color.green : Color.red)
                                    HStack {
                                        Spacer()
                                        Button(bankroll.manualStakes[wager.id] == wager.stake ? "Added to placed bets" : "Add to placed bets") {
                                            bankroll.manualStakes[wager.id] = wager.stake
                                        }.buttonStyle(.borderedProminent)
                                    }
                                }.padding(.top, 4)
                            } label: {
                                HStack {
                                    Label(wager.title, systemImage: "square.stack.3d.up.fill")
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(wager.stake.formatted(.currency(code: "USD"))).font(.headline).monospacedDigit()
                                        Text("\(wager.odds.formatted(.number.sign(strategy: .always()))) · \(wager.probability.formatted(.percent.precision(.fractionLength(1)))) chance")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        ForEach(unifiedPlayerParlays, id: \.id) { wager in
                            let plan = currentPlayerParlays.first { $0.id == wager.id }
                            let profit = OddsMath.profit(stake: wager.stake, american: wager.odds) ?? 0
                            let totalReturn = OddsMath.totalReturn(stake: wager.stake, american: wager.odds) ?? 0
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(plan?.rationale ?? "Market-ranked player prop combination")
                                        .font(.caption).foregroundStyle(.secondary)
                                    ForEach(plan?.legs ?? []) { leg in
                                        Text("• \(leg.quote.player) · \(leg.quote.selection) \(leg.quote.point.formatted(.number.precision(.fractionLength(1)))) \(leg.quote.marketName) · \(leg.matchup)")
                                            .font(.caption)
                                    }
                                    Text("\(wager.odds.formatted(.number.sign(strategy: .always()))) odds · No-vig chance: \(wager.probability.formatted(.percent.precision(.fractionLength(1)))) win · \((1 - wager.probability).formatted(.percent.precision(.fractionLength(1)))) loss")
                                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                    Text("WIN → \(totalReturn.formatted(.currency(code: "USD"))) returned (+\(profit.formatted(.currency(code: "USD")))) · LOSS → $0 returned (-\(wager.stake.formatted(.currency(code: "USD"))))")
                                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                    Label(weeklyWinnerIDs.contains(wager.id) ? "Illustrative scenario: WIN · \(totalReturn.formatted(.currency(code: "USD"))) returned" : "Illustrative scenario: LOSS · $0 returned",
                                          systemImage: weeklyWinnerIDs.contains(wager.id) ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.caption2.bold()).foregroundStyle(weeklyWinnerIDs.contains(wager.id) ? Color.green : Color.red)
                                    HStack {
                                        Spacer()
                                        Button(bankroll.manualStakes[wager.id] == wager.stake ? "Added to placed bets" : "Add to placed bets") {
                                            bankroll.manualStakes[wager.id] = wager.stake
                                        }.buttonStyle(.borderedProminent)
                                    }
                                }.padding(.top, 4)
                            } label: {
                                HStack {
                                    Label(wager.title, systemImage: "person.2.fill")
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(wager.stake.formatted(.currency(code: "USD"))).font(.headline).monospacedDigit()
                                        Text("\(wager.odds.formatted(.number.sign(strategy: .always()))) · \(wager.probability.formatted(.percent.precision(.fractionLength(1)))) no-vig")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Divider()
                        LabeledContent("Combined weekly stake", value: weeklyStake.formatted(.currency(code: "USD")))
                        LabeledContent("Combined illustrative record", value: "\(weeklyWinCount) wins · \(unifiedPlan.count - weeklyWinCount) losses")
                        LabeledContent("Combined illustrative return", value: weeklyReturned.formatted(.currency(code: "USD")))
                        LabeledContent("Combined illustrative net", value: weeklyNet.formatted(.currency(code: "USD").sign(strategy: .always())))
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $showFinalReview) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(unifiedPlan, id: \.id) { wager in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(wager.title).fontWeight(.semibold)
                                        Text("\(wager.category) · \(wager.odds.formatted(.number.sign(strategy: .always())))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(wager.stake.formatted(.currency(code: "USD"))).monospacedDigit()
                                }
                            }
                            Divider()
                            LabeledContent("Total planned stake", value: weeklyStake.formatted(.currency(code: "USD")))
                            LabeledContent("Potential return if all win", value: unifiedPlan.reduce(0) { $0 + (OddsMath.totalReturn(stake: $1.stake, american: $1.odds) ?? 0) }.formatted(.currency(code: "USD")))
                            LabeledContent("Currently recorded", value: bankroll.manualTotal.formatted(.currency(code: "USD")))
                            Button {
                                for wager in unifiedPlan { bankroll.manualStakes[wager.id] = wager.stake }
                            } label: {
                                Label("Add entire plan to placed bets", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }.padding(.top, 6)
                    } label: {
                        HStack {
                            Label("Final plan confirmation", systemImage: "checkmark.seal.fill")
                            Spacer()
                            Text("\(unifiedPlan.count) wagers · \(weeklyStake.formatted(.currency(code: "USD")))")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Confirm the exact Bet365 prices and player availability before recording the plan. Recording a wager does not place it with a sportsbook.")
                }
                }

                if selectedTab == .gameParlays {
                Section(showUnvalidatedRecommendations ? "Three speculative parlay plans" : "Three parlay plans") {
                    let fundableParlayProbabilities = currentParlayPlans.filter { $0.isFundable(showingUnvalidated: showUnvalidatedRecommendations) }
                    let predictedParlayWinCount = min(fundableParlayProbabilities.count, max(0, Int(fundableParlayProbabilities.map { $0.legs.map(\.modelWinProbability).reduce(1, *) }.reduce(0, +).rounded())))
                    let predictedParlayWinnerIDs = Set(fundableParlayProbabilities.sorted {
                        $0.legs.map(\.modelWinProbability).reduce(1, *) > $1.legs.map(\.modelWinProbability).reduce(1, *)
                    }.prefix(predictedParlayWinCount).map(\.id))
                    ForEach(currentParlayPlans) { parlay in
                        let fundedWeeklyAmount = min(max(0, bankroll.weeklyBudget), max(0, bankroll.bankroll))
                        let riskMultiplier = parlay.id == "lower" ? 1.25 - bankroll.riskLevel * 0.5 : parlay.id == "upside" ? 0.5 + bankroll.riskLevel : 1.0
                        let fundable = parlay.isFundable(showingUnvalidated: showUnvalidatedRecommendations)
                        let suggestedStake = fundable ? fundedWeeklyAmount * parlay.budgetShare * riskMultiplier : 0
                        let parlayKey = "parlay-\(parlay.id)"
                        let calculatedOdds = OddsMath.parlayAmerican(parlay.legs.map(\.odds)) ?? 100
                        let activeOdds = bankroll.odds(for: parlayKey, default: calculatedOdds)
                        let suggestedProfit = OddsMath.profit(stake: suggestedStake, american: activeOdds) ?? 0
                        let suggestedReturn = OddsMath.totalReturn(stake: suggestedStake, american: activeOdds) ?? 0
                        let parlayWinProbability = parlay.legs.isEmpty ? 0 : parlay.legs.map(\.modelWinProbability).reduce(1, *)
                        let predictedToWin = predictedParlayWinnerIDs.contains(parlay.id)
                        let enteredStake = bankroll.manualStakes[parlayKey] ?? 0
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(parlay.title).font(.headline)
                                    Text(parlay.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(parlay.risk).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4).background(.secondary.opacity(0.12), in: Capsule())
                            }
                            ForEach(Array(parlay.legs.enumerated()), id: \.element.id) { index, leg in
                                HStack(alignment: .top) {
                                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 22, height: 22).background(AppTheme.accent, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(leg.recommendation.selection).fontWeight(.semibold)
                                        Text("\(leg.matchup) · \(leg.recommendation.rationale)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: leg.validated ? "checkmark.seal.fill" : showUnvalidatedRecommendations ? "exclamationmark.triangle.fill" : "lock.fill")
                                        .foregroundStyle(leg.validated ? .green : showUnvalidatedRecommendations ? .orange : .secondary)
                                }
                            }
                            Divider()
                            HStack {
                                Label(parlay.isValidated ? "Validated" : showUnvalidatedRecommendations ? "Speculative · Unvalidated" : "Preview only · Pass",
                                      systemImage: parlay.isValidated ? "checkmark.shield.fill" : showUnvalidatedRecommendations ? "exclamationmark.triangle.fill" : "hand.raised.fill")
                                    .foregroundStyle(parlay.isValidated ? .green : .orange)
                                Spacer()
                                Text("Suggested \(suggestedStake.formatted(.currency(code: "USD")))").fontWeight(.semibold).monospacedDigit()
                            }
                            Text("Model chance: \(parlayWinProbability.formatted(.percent.precision(.fractionLength(0)))) win · \((1 - parlayWinProbability).formatted(.percent.precision(.fractionLength(0)))) loss · odds \(activeOdds.formatted(.number.sign(strategy: .always())))")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            Text(parlay.legs.isEmpty
                                 ? "Outcome amounts unavailable until legs qualify"
                                 : "WIN → \(suggestedReturn.formatted(.currency(code: "USD"))) returned (+\(suggestedProfit.formatted(.currency(code: "USD")))) · LOSS → $0 returned (-\(suggestedStake.formatted(.currency(code: "USD"))))")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            if !parlay.legs.isEmpty {
                                Label(predictedToWin ? "Illustrative scenario: WIN · \(suggestedReturn.formatted(.currency(code: "USD"))) returned" : "Illustrative scenario: LOSS · $0 returned",
                                      systemImage: predictedToWin ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption.bold()).foregroundStyle(predictedToWin ? Color.green : Color.red).monospacedDigit()
                            }
                            HStack {
                                Text("My parlay wager").font(.caption).foregroundStyle(.secondary)
                                Spacer(); Text("$")
                                TextField("0.00", value: bankroll.stakeBinding(for: parlayKey), format: .number.precision(.fractionLength(2)))
                                    .multilineTextAlignment(.trailing).frame(width: 90)
                            }
                            OddsReturnRow(odds: bankroll.oddsBinding(for: parlayKey, default: calculatedOdds),
                                          stake: enteredStake, source: "Calculated leg price · replace with Bet365 combined odds",
                                          verified: bankroll.enteredOdds[parlayKey] != nil)
                        }.padding(.vertical, 5)
                    }
                    let fundedWeeklyAmount = min(max(0, bankroll.weeklyBudget), max(0, bankroll.bankroll))
                    let fundedParlays = currentParlayPlans.filter { $0.isFundable(showingUnvalidated: showUnvalidatedRecommendations) }
                    let totalParlayStake = fundedParlays.reduce(0) { partial, parlay in
                        let riskMultiplier = parlay.id == "lower" ? 1.25 - bankroll.riskLevel * 0.5 : parlay.id == "upside" ? 0.5 + bankroll.riskLevel : 1.0
                        return partial + fundedWeeklyAmount * parlay.budgetShare * riskMultiplier
                    }
                    let totalParlayProfit = fundedParlays.reduce(0) { partial, parlay in
                        let riskMultiplier = parlay.id == "lower" ? 1.25 - bankroll.riskLevel * 0.5 : parlay.id == "upside" ? 0.5 + bankroll.riskLevel : 1.0
                        let stake = fundedWeeklyAmount * parlay.budgetShare * riskMultiplier
                        let calculatedOdds = OddsMath.parlayAmerican(parlay.legs.map(\.odds)) ?? 100
                        let activeOdds = bankroll.odds(for: "parlay-\(parlay.id)", default: calculatedOdds)
                        return partial + (OddsMath.profit(stake: stake, american: activeOdds) ?? 0)
                    }
                    let predictedParlayReturned = fundedParlays.reduce(0) { partial, parlay in
                        guard predictedParlayWinnerIDs.contains(parlay.id) else { return partial }
                        let riskMultiplier = parlay.id == "lower" ? 1.25 - bankroll.riskLevel * 0.5 : parlay.id == "upside" ? 0.5 + bankroll.riskLevel : 1.0
                        let stake = fundedWeeklyAmount * parlay.budgetShare * riskMultiplier
                        let calculatedOdds = OddsMath.parlayAmerican(parlay.legs.map(\.odds)) ?? 100
                        let activeOdds = bankroll.odds(for: "parlay-\(parlay.id)", default: calculatedOdds)
                        return partial + (OddsMath.totalReturn(stake: stake, american: activeOdds) ?? 0)
                    }
                    let predictedParlayNet = predictedParlayReturned - totalParlayStake
                    VStack(spacing: 5) {
                        LabeledContent("Total suggested parlay stake", value: totalParlayStake.formatted(.currency(code: "USD")))
                        LabeledContent("Anticipated profit if every parlay wins", value: totalParlayProfit.formatted(.currency(code: "USD")))
                        LabeledContent("Total returned if every parlay wins", value: (totalParlayStake + totalParlayProfit).formatted(.currency(code: "USD")))
                        LabeledContent("Illustrative parlay record", value: "\(predictedParlayWinCount) wins · \(fundedParlays.count - predictedParlayWinCount) losses")
                        LabeledContent("Illustrative parlay return", value: predictedParlayReturned.formatted(.currency(code: "USD")))
                        LabeledContent("Illustrative parlay net", value: predictedParlayNet.formatted(.currency(code: "USD").sign(strategy: .always())))
                    }
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    Text(showUnvalidatedRecommendations
                         ? "Speculative parlay amounts are visible by your choice even though the legs failed validation. Parlays compound estimation error and have substantially higher variance."
                         : "Parlay legs are selected from different games to reduce direct correlation. Every leg must pass its market validation gate before the app recommends a nonzero stake. Parlays have higher variance than single wagers.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                }

                if selectedTab == .playerParlays {
                Section("Player parlay builder") {
                    Label("Consensus player props come from The Odds API. Replace the displayed consensus price with the exact Bet365 line before placing a wager.", systemImage: "person.crop.circle.badge.plus")
                        .font(.caption).foregroundStyle(.secondary)
                    if availablePlayerProps.isEmpty {
                        Label("No synced player props yet. The scheduled worker fetches them on Sunday, or during a manual workflow run.", systemImage: "clock.arrow.circlepath")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        HStack(spacing: 24) {
                            LabeledContent("Top-ranked plans", value: currentPlayerParlays.count.formatted())
                            LabeledContent("Suggested exposure", value: playerSuggestedExposure.formatted(.currency(code: "USD")))
                            LabeledContent("Available markets", value: availablePlayerProps.count.formatted())
                        }
                        .font(.callout.weight(.semibold)).monospacedDigit()
                        if let latestPlayerPropUpdate {
                            Label("Player odds updated \(latestPlayerPropUpdate, style: .relative)", systemImage: "clock.arrow.circlepath")
                                .font(.caption)
                                .foregroundStyle(Date.now.timeIntervalSince(latestPlayerPropUpdate) < 21_600 ? Color.secondary : Color.orange)
                        }
                        ForEach(currentPlayerParlays) { parlay in
                            let combinedOdds = OddsMath.parlayAmerican(parlay.legs.map(\.quote.odds)) ?? 100
                            let suggestedStake = min(bankroll.weeklyBudget, bankroll.bankroll) * parlay.budgetShare
                            let totalReturn = OddsMath.totalReturn(stake: suggestedStake, american: combinedOdds) ?? 0
                            let marketEstimatedHitProbability = parlay.legs.map(\.fairProbability).reduce(1, *)
                            let illustrativeWin = playerIllustrativeWinnerIDs.contains(parlay.id)
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(parlay.legs.enumerated()), id: \.element.id) { index, candidate in
                                        HStack(alignment: .firstTextBaseline) {
                                            Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.secondary)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text("\(candidate.quote.player) · \(candidate.quote.selection) \(candidate.quote.point.formatted(.number.precision(.fractionLength(1)))) \(candidate.quote.marketName)")
                                                    .fontWeight(.semibold)
                                                Text("\(candidate.matchup) · \(candidate.quote.bookmakers) books · \(candidate.quote.odds.formatted(.number.sign(strategy: .always()))) · \(candidate.fairProbability.formatted(.percent.precision(.fractionLength(1)))) no-vig")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    HStack {
                                        Text("Illustrative stake \(suggestedStake.formatted(.currency(code: "USD"))) · win → \(totalReturn.formatted(.currency(code: "USD"))) returned")
                                            .font(.caption).monospacedDigit()
                                        Spacer()
                                        Button("Use This Parlay") {
                                            playerPropLegs = parlay.legs.map { candidate in
                                                ManualPlayerPropLeg(
                                                    player: candidate.quote.player,
                                                    selection: "\(candidate.quote.selection) \(candidate.quote.point.formatted(.number.precision(.fractionLength(1)))) \(candidate.quote.marketName)",
                                                    odds: candidate.quote.odds
                                                )
                                            }
                                            bankroll.manualStakes["player-prop-parlay"] = suggestedStake
                                        }.buttonStyle(.borderedProminent)
                                    }
                                    Label("Market-estimated hit probability: \(marketEstimatedHitProbability.formatted(.percent.precision(.fractionLength(1)))) · vig removed · not a player model", systemImage: "percent")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Label(illustrativeWin
                                          ? "Illustrative scenario: WIN · \(totalReturn.formatted(.currency(code: "USD"))) returned"
                                          : "Illustrative scenario: LOSS · $0 returned",
                                          systemImage: illustrativeWin ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(illustrativeWin ? Color.green : Color.red)
                                }.padding(.top, 6)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(parlay.title).font(.headline)
                                        Text(parlay.rationale).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(combinedOdds.formatted(.number.sign(strategy: .always())))
                                        .font(.headline.monospacedDigit())
                                    Text("\(suggestedStake.formatted(.currency(code: "USD"))) stake · \(totalReturn.formatted(.currency(code: "USD"))) return")
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        VStack(spacing: 5) {
                            LabeledContent("Illustrative player-parlay record",
                                           value: "\(playerIllustrativeWinCount) wins · \(currentPlayerParlays.count - playerIllustrativeWinCount) losses")
                            LabeledContent("Illustrative return",
                                           value: playerIllustrativeReturn.formatted(.currency(code: "USD")))
                            LabeledContent("Illustrative net",
                                           value: playerIllustrativeNet.formatted(.currency(code: "USD").sign(strategy: .always())))
                        }
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        Text("The app evaluated both Over and Under sides with paired prices, estimated no-vig probability, freshness, sportsbook coverage, payout and cross-game diversification. These are the top market-ranked combinations currently available—not validated player-performance projections. Confirm every line and combined price in Bet365 before wagering.")
                            .font(.caption).foregroundStyle(.orange)
                        DisclosureGroup("Browse consensus props · \(filteredPlayerProps.count) of \(availablePlayerProps.count)") {
                            HStack {
                                TextField("Search player", text: $playerPropSearch)
                                Picker("Market", selection: $playerPropMarket) {
                                    ForEach(["All", "Passing yards", "Rushing yards", "Receiving yards", "Receptions"], id: \.self) { Text($0).tag($0) }
                                }.frame(width: 190)
                            }
                            ForEach(Array(filteredPlayerProps.prefix(40))) { quote in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(quote.player).fontWeight(.semibold)
                                        Text("\(quote.selection) \(quote.point.formatted(.number.precision(.fractionLength(1)))) \(quote.marketName) · \(quote.bookmakers) books")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(quote.odds.formatted(.number.sign(strategy: .always()))).monospacedDigit()
                                    Button("Add") {
                                        let selection = "\(quote.selection) \(quote.point.formatted(.number.precision(.fractionLength(1)))) \(quote.marketName)"
                                        let leg = ManualPlayerPropLeg(player: quote.player, selection: selection, odds: quote.odds)
                                        if !playerPropLegs.contains(where: { $0.player == leg.player && $0.selection == leg.selection }) {
                                            playerPropLegs.append(leg)
                                        }
                                    }.buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    HStack {
                        TextField("Player", text: $playerName).frame(minWidth: 120)
                        TextField("Selection, e.g. Over 74.5 receiving yards", text: $playerPropSelection).frame(minWidth: 260)
                        TextField("Odds", value: $playerPropOdds, format: .number.sign(strategy: .always())).frame(width: 80)
                        Button("Add Leg") {
                            playerPropLegs.append(ManualPlayerPropLeg(
                                player: playerName.trimmingCharacters(in: .whitespacesAndNewlines),
                                selection: playerPropSelection.trimmingCharacters(in: .whitespacesAndNewlines),
                                odds: playerPropOdds
                            ))
                            playerName = ""
                            playerPropSelection = ""
                            playerPropOdds = -110
                        }
                        .disabled(playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  playerPropSelection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  playerPropOdds == 0)
                    }
                    ForEach(playerPropLegs) { leg in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(leg.player).fontWeight(.semibold)
                                Text(leg.selection).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(leg.odds.formatted(.number.sign(strategy: .always()))).monospacedDigit()
                            Button(role: .destructive) {
                                playerPropLegs.removeAll { $0.id == leg.id }
                            } label: {
                                Image(systemName: "trash")
                            }.buttonStyle(.borderless)
                        }
                    }
                    if playerPropLegs.count >= 2 {
                        let calculatedOdds = OddsMath.parlayAmerican(playerPropLegs.map(\.odds)) ?? 100
                        let wagerKey = "player-prop-parlay"
                        let enteredStake = bankroll.manualStakes[wagerKey] ?? 0
                        OddsReturnRow(
                            odds: bankroll.oddsBinding(for: wagerKey, default: calculatedOdds),
                            stake: enteredStake,
                            source: "Calculated from entered legs · replace with the exact combined Bet365 price",
                            verified: bankroll.enteredOdds[wagerKey] != nil
                        )
                        HStack {
                            Text("My player parlay wager").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("$")
                            TextField("0.00", value: bankroll.stakeBinding(for: wagerKey), format: .number.precision(.fractionLength(2)))
                                .multilineTextAlignment(.trailing).frame(width: 90)
                        }
                        Text("All legs must win for the parlay to return a profit. The app is calculating payout only; it is not validating or recommending these player props.")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("Add at least two player-prop legs to calculate combined odds and returns.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                }

                if selectedTab == .markets {
                Section {
                    if validatedKinds.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("No strategy has passed historical validation", systemImage: "shield.lefthalf.filled").font(.title3.bold()).foregroundStyle(.orange)
                            Text("This does not suppress the Model-Ranked plan. It means the recommendations are model-ranked opinions rather than historically proven betting systems.").foregroundStyle(.secondary)
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
                                let displayStrength: BetStrength = (validated || showUnvalidatedRecommendations) ? recommendation.strength : .pass
                                let evidence = evidenceByKind[recommendation.kind]!
                                let wagerKey = "\(prediction.matchup.gameKey)-\(recommendation.id)"
                                let fallbackOdds = defaultOdds(for: recommendation, prediction: prediction)
                                let enteredStake = bankroll.manualStakes[wagerKey] ?? 0
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(recommendation.kind.rawValue).fontWeight(.semibold)
                                        Spacer()
                                        Label(validated ? displayStrength.rawValue : showUnvalidatedRecommendations ? "Speculative · \(displayStrength.rawValue)" : "Not validated",
                                              systemImage: validated ? "checkmark.seal.fill" : showUnvalidatedRecommendations ? "exclamationmark.triangle.fill" : "lock.fill")
                                            .foregroundStyle(validated && displayStrength == .strong ? .green : displayStrength == .lean || showUnvalidatedRecommendations ? .orange : .secondary)
                                    }
                                    Text(displayStrength == .pass ? "Pass on \(recommendation.selection)" : recommendation.selection)
                                    Text(recommendation.rationale).font(.caption).foregroundStyle(.secondary)
                                    Text(recommendation.kind == .moneyline
                                         ? "Evidence: \(evidence.graded) strong-edge samples · \(evidence.returnOnStake.formatted(.percent.precision(.fractionLength(1)))) return"
                                         : "Evidence: \(evidence.graded) strong-edge samples · \(evidence.winRate.formatted(.percent.precision(.fractionLength(1)))) wins")
                                        .font(.caption2)
                                        .foregroundStyle(evidence.returnOnStake < 0 ? Color.red : Color.secondary)
                                    if evidence.returnOnStake < 0 && recommendation.strength != .pass {
                                        Label("The model likes this matchup, but this market strategy has not produced a positive historical return.", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption2.bold()).foregroundStyle(.red)
                                    }
                                    HStack {
                                        Text("My wager").font(.caption).foregroundStyle(.secondary)
                                        if let suggested = currentAllocations.first(where: { $0.id == wagerKey }) {
                                            Button("Use suggested \(suggested.amount.formatted(.currency(code: "USD")))") {
                                                bankroll.manualStakes[wagerKey] = suggested.amount
                                            }
                                            .buttonStyle(.borderless)
                                            .font(.caption)
                                        }
                                        Spacer()
                                        Text("$")
                                        TextField("0.00", value: bankroll.stakeBinding(for: wagerKey), format: .number.precision(.fractionLength(2)))
                                            .multilineTextAlignment(.trailing).frame(width: 90)
                                    }
                                    OddsReturnRow(odds: bankroll.oddsBinding(for: wagerKey, default: fallbackOdds),
                                        stake: enteredStake,
                                        source: recommendation.kind == .moneyline ? (prediction.matchup.bettingLine?.source ?? "Consensus moneyline") : "General -110 estimate · replace with current sportsbook price",
                                        verified: bankroll.enteredOdds[wagerKey] != nil)
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
                }
                }
                .listStyle(.plain)
                .contentMargins(.horizontal, 12, for: .scrollContent)
                .contentMargins(.vertical, 6, for: .scrollContent)
            }
            .navigationTitle("Bet Slip")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 18) {
                    switch selectedTab {
                    case .plan:
                        Label("Stake \(weeklyStake.formatted(.currency(code: "USD")))", systemImage: "dollarsign.circle.fill")
                        Label(unifiedPlan.isEmpty ? "Scenario —" : "Scenario \(weeklyWinCount)–\(unifiedPlan.count - weeklyWinCount)", systemImage: "chart.bar.fill")
                        Spacer()
                        Text("Scenario return \(weeklyReturned.formatted(.currency(code: "USD")))")
                        Text("Net \(weeklyNet.formatted(.currency(code: "USD").sign(strategy: .always())))")
                            .foregroundStyle(weeklyNet >= 0 ? Color.green : Color.red)
                    case .playerParlays:
                        Label("Suggested exposure \(playerSuggestedExposure.formatted(.currency(code: "USD")))", systemImage: "person.2.fill")
                        Label("Scenario \(playerIllustrativeWinCount)–\(currentPlayerParlays.count - playerIllustrativeWinCount)", systemImage: "chart.bar.fill")
                        Spacer()
                        Text("Scenario return \(playerIllustrativeReturn.formatted(.currency(code: "USD")))")
                        Text("All-win \(playerMaximumReturn.formatted(.currency(code: "USD")))")
                    case .gameParlays:
                        Label("\(currentParlayPlans.count) game parlays", systemImage: "square.stack.3d.up.fill")
                        Spacer()
                        Text("Entered exposure \(bankroll.manualTotal.formatted(.currency(code: "USD")))")
                    case .markets:
                        Label("\(predictions.count) games", systemImage: "sportscourt.fill")
                        Spacer()
                        Text("Entered exposure \(bankroll.manualTotal.formatted(.currency(code: "USD")))")
                    }
                    Divider().frame(height: 18)
                    Text("Recorded wagers \(bankroll.manualTotal.formatted(.currency(code: "USD"))) / \(min(bankroll.weeklyBudget, bankroll.bankroll).formatted(.currency(code: "USD")))")
                        .foregroundStyle(bankroll.manualTotal <= min(bankroll.weeklyBudget, bankroll.bankroll) ? Color.secondary : Color.orange)
                }
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
    }
    private func allocationExpandedBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedAllocationIDs.contains(id) },
            set: { isExpanded in
                if isExpanded { expandedAllocationIDs.insert(id) }
                else { expandedAllocationIDs.remove(id) }
            }
        )
    }
    private var riskLabel: String { bankroll.riskLevel < 0.34 ? "Conservative" : bankroll.riskLevel < 0.67 ? "Balanced" : "Aggressive" }
    private var returnLabel: String { bankroll.returnLevel < 0.34 ? "Steady" : bankroll.returnLevel < 0.67 ? "Balanced" : "High upside" }
    private var riskPreset: Binding<Double> {
        Binding(
            get: { bankroll.riskLevel < 0.34 ? 0.15 : bankroll.riskLevel < 0.67 ? BankrollStore.recommendedRisk : 0.85 },
            set: { bankroll.riskLevel = $0 }
        )
    }
    private var returnPreset: Binding<Double> {
        Binding(
            get: { bankroll.returnLevel < 0.34 ? 0.10 : bankroll.returnLevel < 0.67 ? BankrollStore.recommendedReturn : 0.90 },
            set: { bankroll.returnLevel = $0 }
        )
    }
}

private struct ChecklistRow: View {
    let label: String
    let complete: Bool
    var body: some View {
        Label(label, systemImage: complete ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(complete ? Color.green : Color.orange)
            .font(.callout)
    }
}

private struct OddsReturnRow: View {
    @Binding var odds: Int
    let stake: Double
    let source: String
    var verified = false
    var body: some View {
        let probability = OddsMath.impliedProbability(american: odds)
        let profit = OddsMath.profit(stake: stake, american: odds)
        let total = OddsMath.totalReturn(stake: stake, american: odds)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("American odds").font(.caption).foregroundStyle(.secondary)
                TextField("-110", value: $odds, format: .number.sign(strategy: .always()))
                    .multilineTextAlignment(.trailing).frame(width: 90)
                Label(verified ? "Bet365 price entered" : "Needs Bet365 verification",
                      systemImage: verified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(verified ? Color.green : Color.orange)
                Spacer()
                Text("Implied \((probability ?? 0).formatted(.percent.precision(.fractionLength(1))))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Profit \((profit ?? 0).formatted(.currency(code: "USD")))")
                Spacer()
                Text("Total return \((total ?? 0).formatted(.currency(code: "USD")))").fontWeight(.semibold)
            }.font(.caption).monospacedDigit()
            Text(source).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(8).background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PredictionsView: View {
    private enum PickFilter: String, CaseIterable { case all = "All games", recommended = "Recommended", review = "Needs review" }
    private enum PickSort: String, CaseIterable { case opportunity = "Best opportunity", confidence = "Confidence", kickoff = "Game time" }
    let predictions: [Prediction]
    let season: Int
    let week: Int
    let feedStatus: String
    let isRefreshing: Bool
    let refresh: () -> Void
    @State private var filter: PickFilter = .all
    @State private var sort: PickSort = .opportunity

    private func opportunityScore(_ prediction: Prediction) -> Double {
        prediction.bettingRecommendations.filter { $0.strength != .pass }.map(\.edge).max() ?? -1
    }

    private var displayedPredictions: [Prediction] {
        predictions.filter { prediction in
            switch filter {
            case .all: true
            case .recommended: prediction.bettingRecommendations.contains { $0.strength == .strong }
            case .review: prediction.reviewFlag != nil
            }
        }.sorted { lhs, rhs in
            switch sort {
            case .opportunity: opportunityScore(lhs) > opportunityScore(rhs)
            case .confidence: lhs.confidence > rhs.confidence
            case .kickoff: lhs.matchup.kickoff < rhs.matchup.kickoff
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Picker("Show", selection: $filter) {
                            ForEach(PickFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        Picker("Sort", selection: $sort) {
                            ForEach(PickSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.frame(width: 190)
                    }
                    .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 12))

                    if displayedPredictions.isEmpty {
                        ContentUnavailableView("No matching games", systemImage: "line.3.horizontal.decrease.circle", description: Text("Choose another filter to review this week’s matchups."))
                    }
                    ForEach(displayedPredictions) { prediction in
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
    let historicalValidationGrades: [GradedPrediction]
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
                        LabeledContent("MVP 1.2 winner accuracy", value: summary.winnerAccuracy.formatted(.percent.precision(.fractionLength(0))))
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
                        let allBets = Backtester.bettingPerformance(historicalValidationGrades)
                        let strongBets = Backtester.bettingPerformance(historicalValidationGrades, strongOnly: true)
                        if allBets.graded == 0 {
                            Text("No qualifying historical recommendations yet.").foregroundStyle(.secondary)
                        } else {
                            LabeledContent("Qualified recommendations", value: allBets.graded.formatted())
                            LabeledContent("Record", value: "\(allBets.wins)-\(allBets.losses)-\(allBets.pushes)")
                            LabeledContent("Win rate excluding pushes", value: allBets.winRate.formatted(.percent.precision(.fractionLength(1))))
                            LabeledContent("Strong-edge record", value: "\(strongBets.wins)-\(strongBets.losses)-\(strongBets.pushes) · \(strongBets.winRate.formatted(.percent.precision(.fractionLength(1))))")
                            ForEach([BetKind.spread, .total, .moneyline], id: \.self) { kind in
                                let validation = Backtester.bettingValidation(historicalValidationGrades, kind: kind)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Label(kind.rawValue, systemImage: validation.isValidated ? "checkmark.shield.fill" : "clock.badge.exclamationmark")
                                            .foregroundStyle(validation.isValidated ? .green : .orange)
                                        Spacer()
                                        Text(validation.isValidated ? "Validated" : "Building evidence").font(.caption.bold())
                                    }
                                    ProgressView(value: validation.progress)
                                    Text("Strong edges: \(validation.performance.wins)-\(validation.performance.losses)-\(validation.performance.pushes) · \(validation.performance.winRate.formatted(.percent.precision(.fractionLength(1)))) wins · \(validation.performance.returnOnStake.formatted(.percent.precision(.fractionLength(1)))) return")
                                        .font(.caption)
                                    Text("\(validation.seasonsTested) held-out seasons · \(validation.profitableSeasons) profitable")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if !validation.isValidated {
                                        Text("Still needed: \(validation.unmetRequirements.joined(separator: " · "))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 4)
                            }
                            Text("Only rolling out-of-sample seasons determine validation. Live and archived app picks remain visible elsewhere but cannot promote a market to Validated. Historical lines are nflverse closing lines; exact earlier sportsbook availability, limits and transaction costs are not reconstructed.").font(.caption).foregroundStyle(.secondary)
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
                    LabeledContent("Version", value: "MVP 1.2")
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
    private var bestBet: BetRecommendation? {
        let actionable = prediction.bettingRecommendations.filter { $0.strength != .pass }
        return actionable.max { $0.edge < $1.edge }
    }
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
            HStack {
                Label("Game prediction", systemImage: "sportscourt.fill")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Text("\(prediction.predictedWinner.abbreviation) · \(prediction.confidence.formatted(.percent.precision(.fractionLength(0)))) win confidence")
                    .font(.caption)
                Spacer()
                if let bestBet {
                    Text("Best bet: \(bestBet.selection)")
                        .font(.caption.bold()).foregroundStyle(bestBet.strength == .strong ? Color.green : Color.orange)
                } else {
                    Text("Best bet: Pass").font(.caption.bold()).foregroundStyle(.secondary)
                }
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
                    if let spread = line.homeSpread { Label("\(prediction.matchup.home.abbreviation) \(spread.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))))", systemImage: "arrow.left.and.right") }
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
