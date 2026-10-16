import Foundation
#if canImport(PredictionCore)
import PredictionCore
#endif

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var predictions: [Prediction] = []
    @Published private(set) var gradedPredictions: [GradedPrediction] = []
    @Published private(set) var status = "Loading current records…"
    @Published private(set) var isRefreshing = false
    @Published private(set) var season = 0
    @Published private(set) var week = 0
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var sourceUpdatedAt: Date?
    @Published private(set) var syncStatus = "Connecting to CloudKit…"
    @Published private(set) var validationSummary: BacktestSummary?
    @Published private(set) var validationSeason: Int?
    @Published private(set) var trainingGames = 0
    @Published private(set) var selectedConfiguration = ModelConfiguration.baseline
    @Published private(set) var rollingValidationSummary: BacktestSummary?
    @Published private(set) var rollingValidationSeasons: [Int] = []
    @Published private(set) var storageLabel = "CloudKit"
    @Published private(set) var archiveCount = 0
    @Published private(set) var archiveBundles: [[Prediction]] = []
    @Published private(set) var teamAdjustments: [String: Double] = [:]

    private let fallbackMatchups = SampleData.matchups
    private let feed: any TeamStatsFeed
    private let repository: any PredictionRepository
    private var availabilityImpacts: [String: AvailabilityImpact] = [:]
    private var advancedMetrics: [String: AdvancedTeamMetrics] = [:]
    private var gameContexts: [String: GameContext] = [:]

    init(feed: any TeamStatsFeed = NFLVerseScheduleFeed(), repository: (any PredictionRepository)? = nil) {
        self.feed = feed
        self.teamAdjustments = UserDefaults.standard.dictionary(forKey: "teamAdjustments") as? [String: Double] ?? [:]
        if let repository {
            self.repository = repository
        } else {
#if canImport(CloudKit)
            self.repository = CloudKitPredictionRepository(containerIdentifier: "iCloud.com.acfenech.NFLPredictionLab")
#else
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.repository = LocalPredictionRepository(url: base.appending(path: "NFLPredictionLab/predictions.json"))
            self.storageLabel = "On this device"
#endif
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var notices: [String] = []
        let saved: [Prediction]
        do { saved = try await repository.load() }
        catch { saved = []; notices.append("Cloud load failed") }
        let history: [[Prediction]]
        do {
            history = try await repository.loadHistory()
            syncStatus = "CloudKit connected · \(history.count) archives"
        } catch {
            history = []
            syncStatus = "Cloud history unavailable · retry with Refresh"
            notices.append("History sync failed")
        }
        archiveCount = history.count
        archiveBundles = history
        do {
            let discovered = try await feed.currentSeasonWeek(referenceDate: .now)
            season = discovered.season
            week = discovered.week
            if let text = ProcessInfo.processInfo.environment["AVAILABILITY_FEED_URL"], let url = URL(string: text) {
                do { availabilityImpacts = try await RemoteAvailabilityFeed(url: url).currentImpacts() }
                catch { notices.append("Availability feed unavailable") }
            }
            if let text = ProcessInfo.processInfo.environment["ADVANCED_METRICS_FEED_URL"], let url = URL(string: text) {
                do { advancedMetrics = try await RemoteAdvancedMetricsFeed(url: url).currentMetrics() }
                catch { notices.append("Advanced metrics feed unavailable") }
            }
            if let text = ProcessInfo.processInfo.environment["GAME_CONTEXT_FEED_URL"], let url = URL(string: text) {
                do { gameContexts = try await RemoteGameContextFeed(url: url).currentContexts() }
                catch { notices.append("Weather/travel feed unavailable") }
            }
            async let scheduleRequest = feed.upcomingMatchups(season: season, week: week)
            async let snapshotsRequest = feed.snapshots(season: season, week: week)
            async let resultsRequest = feed.completedResults(season: season, week: week)
            async let historicalRequest = feed.historicalGames(seasons: (season - 3)...(season - 1))
            let (liveMatchups, snapshots, results, historical) = try await (scheduleRequest, snapshotsRequest, resultsRequest, historicalRequest)
            if let report = await Task.detached(operation: { ModelTrainer.trainAndValidate(historical) }).value {
                selectedConfiguration = report.configuration
                validationSummary = Backtester.summarize(report.grades)
                validationSeason = report.validationSeason
                trainingGames = report.trainingGames
                rollingValidationSummary = Backtester.summarize(report.rollingGrades)
                rollingValidationSeasons = report.rollingSeasons
            }
            let matchups = liveMatchups
            let required = Set(matchups.flatMap { [$0.away.abbreviation, $0.home.abbreviation] })
            let missing = required.subtracting(snapshots.keys)
            let ratedMatchups = matchups.map { matchup in
                Matchup(id: matchup.id, week: matchup.week, kickoff: matchup.kickoff,
                        away: rated(matchup.away, with: snapshots),
                        home: rated(matchup.home, with: snapshots), bettingLine: matchup.bettingLine,
                        context: gameContexts[matchup.gameKey])
            }
            predictions = await calculate(ratedMatchups, preserving: saved)
            do { try await repository.save(predictions) }
            catch { notices.append("Cloud save failed") }
            var grades = grade(predictions: predictions, results: results)
            for bundle in history {
                guard let sample = bundle.first else { continue }
                let archivedSeason = Calendar(identifier: .gregorian).component(.year, from: sample.matchup.kickoff)
                if let archivedResults = try? await feed.completedResults(season: archivedSeason, week: sample.matchup.week) {
                    grades.append(contentsOf: grade(predictions: bundle, results: archivedResults))
                }
            }
            grades.append(contentsOf: ModelTrainer.trainAndValidate(historical)?.grades ?? [])
            gradedPredictions = grades
            lastUpdated = predictions.compactMap(\.recalculatedAt).max() ?? predictions.map(\.generatedAt).max()
            sourceUpdatedAt = predictions.compactMap(\.dataSourceUpdatedAt).max()
            let feedMessage = missing.isEmpty
                ? "Current records loaded · nflverse"
                : "Partial stats · \(missing.count) teams use neutral ratings"
            status = ([feedMessage] + notices).joined(separator: " · ")
        } catch {
            predictions = saved.isEmpty ? await calculate(fallbackMatchups, preserving: []) : saved
            if saved.isEmpty {
                do { try await repository.save(predictions) }
                catch { notices.append("Cloud save failed") }
            }
            lastUpdated = predictions.compactMap(\.recalculatedAt).max() ?? predictions.map(\.generatedAt).max()
            sourceUpdatedAt = predictions.compactMap(\.dataSourceUpdatedAt).max()
            status = (["Stats feed unavailable · cached or neutral forecasts shown"] + notices).joined(separator: " · ")
        }
    }

    private func rated(_ team: Team, with snapshots: [String: TeamSnapshot]) -> Team {
        let snapshot = snapshots[team.abbreviation]
        let manualAdjustment = teamAdjustments[team.abbreviation] ?? 0
        let availability = availabilityImpacts[team.abbreviation]
        let adjustment = manualAdjustment + (availability?.adjustment ?? 0)
        return Team(abbreviation: team.abbreviation, name: team.name,
                    offensiveRating: (snapshot?.offensiveRating ?? 0) + adjustment,
                    defensiveRating: snapshot?.defensiveRating ?? 0,
                    recentForm: snapshot?.recentForm, restDays: snapshot?.restDays,
                    availabilityAdjustment: adjustment,
                    availabilityNote: availability?.note ?? (manualAdjustment == 0 ? nil : "Manual adjustment \(manualAdjustment.formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))))"),
                    advancedEfficiency: advancedMetrics[team.abbreviation]?.rating)
    }

    func adjustment(for abbreviation: String) -> Double { teamAdjustments[abbreviation] ?? 0 }

    func setAdjustment(_ value: Double, for abbreviation: String) {
        teamAdjustments[abbreviation] = value
        UserDefaults.standard.set(teamAdjustments, forKey: "teamAdjustments")
    }

    private func calculate(_ matchups: [Matchup], preserving saved: [Prediction]) async -> [Prediction] {
        let configuration = selectedConfiguration
        return await Task.detached {
            let engine = ForecastingEngine(configuration: configuration)
            return matchups.enumerated().map { offset, matchup in
                let prior = saved.first { $0.matchup.gameKey == matchup.gameKey }
                let fresh = engine.predict(matchup, seed: UInt64(offset + 1))
                return Prediction(id: prior?.id ?? fresh.id, matchup: matchup, homeScore: fresh.homeScore,
                                  awayScore: fresh.awayScore, homeWinProbability: fresh.homeWinProbability,
                                  simulations: fresh.simulations, generatedAt: prior?.generatedAt ?? fresh.generatedAt,
                                  simulationSummary: fresh.simulationSummary, modelVersion: "MVP 0.6",
                                  dataSourceUpdatedAt: .now, recalculatedAt: .now, factors: fresh.factors,
                                  previousHomeWinProbability: prior?.homeWinProbability,
                                  previousHomeScore: prior?.homeScore, previousAwayScore: prior?.awayScore,
                                  modelOnlyHomeSpread: fresh.modelOnlyHomeSpread,
                                  modelOnlyTotal: fresh.modelOnlyTotal,
                                  previousMarketHomeSpread: prior?.matchup.bettingLine?.homeSpread,
                                  previousMarketTotal: prior?.matchup.bettingLine?.total)
            }
        }.value
    }

    private func grade(predictions: [Prediction], results: [GameResult]) -> [GradedPrediction] {
        predictions.compactMap { prediction in
            guard let result = results.first(where: {
                $0.awayAbbreviation == prediction.matchup.away.abbreviation &&
                $0.homeAbbreviation == prediction.matchup.home.abbreviation
            }) else { return nil }
            return GradedPrediction(prediction: prediction, actualHomeScore: result.homeScore, actualAwayScore: result.awayScore)
        }
    }
}
