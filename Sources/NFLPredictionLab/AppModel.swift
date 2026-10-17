import Foundation
#if canImport(Security)
import Security
#endif
#if canImport(PredictionCore)
import PredictionCore
#endif

@MainActor
final class AppModel: ObservableObject {
    private struct CachedValidation: Codable {
        let version: Int
        let forecastSeason: Int
        let configuration: ModelConfiguration
        let trainingGames: Int
        let validationSeason: Int
        let grades: [GradedPrediction]
        let rollingGrades: [GradedPrediction]
        let rollingSeasons: [Int]
    }

    private static let validationCacheVersion = 2
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
    @Published private(set) var historicalValidationGrades: [GradedPrediction] = []
    @Published private(set) var storageLabel = "CloudKit"
    @Published private(set) var archiveCount = 0
    @Published private(set) var archiveBundles: [[Prediction]] = []
    @Published private(set) var teamAdjustments: [String: Double] = [:]
    @Published private(set) var injuryTeamsLoaded = 0
    @Published private(set) var advancedTeamsLoaded = 0
    @Published private(set) var weatherGamesLoaded = 0

    private let fallbackMatchups = SampleData.matchups
    private let feed: any TeamStatsFeed
    private let repository: any PredictionRepository
    private var availabilityImpacts: [String: AvailabilityImpact] = [:]
    private var advancedMetrics: [String: AdvancedTeamMetrics] = [:]
    private var gameContexts: [String: GameContext] = [:]
    private let freeDataFeed = NFLVerseFreeDataFeed()

    private var validationCacheURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appending(path: "NFLPredictionLab/historical-validation-v\(Self.validationCacheVersion).json")
    }

    init(feed: any TeamStatsFeed = NFLVerseScheduleFeed(), repository: (any PredictionRepository)? = nil) {
        self.feed = feed
        self.teamAdjustments = UserDefaults.standard.dictionary(forKey: "teamAdjustments") as? [String: Double] ?? [:]
        if let repository {
            self.repository = repository
        } else {
#if canImport(CloudKit) && canImport(Security)
            let task = SecTaskCreateFromSelf(nil)
            let services = task.flatMap {
                SecTaskCopyValueForEntitlement($0, "com.apple.developer.icloud-services" as CFString, nil)
            } as? [String]
            if services?.contains("CloudKit") == true || services?.contains("CloudKit-Anonymous") == true {
            self.repository = CloudKitPredictionRepository(containerIdentifier: "iCloud.com.acfenech.NFLPredictionLab")
            } else {
                let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                self.repository = LocalPredictionRepository(url: base.appending(path: "NFLPredictionLab/predictions.json"))
                self.storageLabel = "On this device"
            }
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
            var historicalValidationReport = loadValidationCache(for: season)
            if let report = historicalValidationReport { applyValidation(report) }
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
            let (liveMatchups, snapshots, results) = try await (scheduleRequest, snapshotsRequest, resultsRequest)
            if availabilityImpacts.isEmpty {
                do { availabilityImpacts = try await freeDataFeed.availabilityImpacts(season: season, week: week) }
                catch { notices.append("Free injury report delayed") }
            }
            if advancedMetrics.isEmpty {
                do { advancedMetrics = try await freeDataFeed.advancedMetrics(season: season, throughWeek: week) }
                catch { notices.append("Free advanced stats delayed") }
            }
            let freeContexts = await freeDataFeed.gameContexts(for: liveMatchups)
            for (key, context) in freeContexts where gameContexts[key] == nil { gameContexts[key] = context }
            injuryTeamsLoaded = availabilityImpacts.count
            advancedTeamsLoaded = advancedMetrics.count
            weatherGamesLoaded = gameContexts.values.filter { $0.weatherSummary != nil }.count
            if historicalValidationReport == nil {
                status = "Weekly data loaded · building historical validation once…"
                let historical = try await feed.historicalGames(seasons: HistoricalValidationWindow.seasons(before: season))
                historicalValidationReport = await Task.detached(operation: { ModelTrainer.trainAndValidate(historical) }).value
                if let report = historicalValidationReport {
                    applyValidation(report)
                    saveValidationCache(report, for: season)
                }
            }
            let matchups = liveMatchups
            let required = Set(matchups.flatMap { [$0.away.abbreviation, $0.home.abbreviation] })
            let missing = required.subtracting(snapshots.keys)
            let ratedMatchups = matchups.map { matchup in
                let savedLine = saved.first(where: { $0.matchup.gameKey == matchup.gameKey })?.matchup.bettingLine
                let baseLine = matchup.bettingLine
                let preferredLine: BettingLine?
                if let savedLine, savedLine.source.contains("The Odds API") {
                    preferredLine = BettingLine(homeSpread: baseLine?.homeSpread ?? savedLine.homeSpread,
                        total: baseLine?.total ?? savedLine.total,
                        homeMoneyline: savedLine.homeMoneyline, awayMoneyline: savedLine.awayMoneyline,
                        source: savedLine.source,
                        openingHomeSpread: baseLine?.openingHomeSpread ?? savedLine.openingHomeSpread,
                        openingTotal: baseLine?.openingTotal ?? savedLine.openingTotal,
                        closingHomeSpread: baseLine?.closingHomeSpread ?? savedLine.closingHomeSpread,
                        closingTotal: baseLine?.closingTotal ?? savedLine.closingTotal)
                } else { preferredLine = baseLine }
                let baseContext = gameContexts[matchup.gameKey]
                let quarterbackNotes = [availabilityImpacts[matchup.away.abbreviation]?.note,
                                        availabilityImpacts[matchup.home.abbreviation]?.note]
                    .compactMap { $0 }.joined(separator: " · ")
                let context = GameContext(weatherSummary: baseContext?.weatherSummary,
                    weatherPoints: baseContext?.weatherPoints ?? 0,
                    travelMiles: baseContext?.travelMiles,
                    travelPoints: baseContext?.travelPoints ?? 0,
                    quarterbackSummary: quarterbackNotes.isEmpty ? nil : quarterbackNotes)
                return Matchup(id: matchup.id, week: matchup.week, kickoff: matchup.kickoff,
                        away: rated(matchup.away, with: snapshots),
                        home: rated(matchup.home, with: snapshots), bettingLine: preferredLine,
                        context: context)
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
            // Rolling grades contain every season evaluated strictly from prior-season
            // information, including the newest outer holdout. Using them avoids both
            // the small-sample newest-season gate and double-counting that season.
            if let report = historicalValidationReport {
                grades.append(contentsOf: report.rollingGrades.isEmpty ? report.grades : report.rollingGrades)
            }
            gradedPredictions = grades
            lastUpdated = predictions.compactMap(\.recalculatedAt).max() ?? predictions.map(\.generatedAt).max()
            sourceUpdatedAt = predictions.compactMap(\.dataSourceUpdatedAt).max()
            let feedMessage = missing.isEmpty
                ? "Current records loaded · nflverse"
                : "Partial stats · \(missing.count) teams use neutral ratings"
            let coverage = "context: \(advancedTeamsLoaded) metric teams, \(injuryTeamsLoaded) injury teams, \(weatherGamesLoaded) weather games"
            status = ([feedMessage, coverage] + notices).joined(separator: " · ")
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

    private func applyValidation(_ report: ModelValidationReport) {
        selectedConfiguration = report.configuration
        validationSummary = Backtester.summarize(report.grades)
        validationSeason = report.validationSeason
        trainingGames = report.trainingGames
        rollingValidationSummary = Backtester.summarize(report.rollingGrades)
        rollingValidationSeasons = report.rollingSeasons
        historicalValidationGrades = report.rollingGrades.isEmpty ? report.grades : report.rollingGrades
    }

    private func loadValidationCache(for forecastSeason: Int) -> ModelValidationReport? {
        guard let data = try? Data(contentsOf: validationCacheURL),
              let cached = try? JSONDecoder().decode(CachedValidation.self, from: data),
              cached.version == Self.validationCacheVersion,
              cached.forecastSeason == forecastSeason else { return nil }
        return ModelValidationReport(configuration: cached.configuration,
            trainingGames: cached.trainingGames, validationSeason: cached.validationSeason,
            grades: cached.grades, rollingGrades: cached.rollingGrades,
            rollingSeasons: cached.rollingSeasons)
    }

    private func saveValidationCache(_ report: ModelValidationReport, for forecastSeason: Int) {
        let cached = CachedValidation(version: Self.validationCacheVersion,
            forecastSeason: forecastSeason, configuration: report.configuration,
            trainingGames: report.trainingGames, validationSeason: report.validationSeason,
            grades: report.grades, rollingGrades: report.rollingGrades,
            rollingSeasons: report.rollingSeasons)
        do {
            try FileManager.default.createDirectory(at: validationCacheURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(cached).write(to: validationCacheURL, options: .atomic)
        } catch {
            // A cache failure affects performance only; validation still remains in memory.
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

    func resetAllAdjustments() {
        teamAdjustments = [:]
        UserDefaults.standard.removeObject(forKey: "teamAdjustments")
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
                                  simulationSummary: fresh.simulationSummary, modelVersion: "MVP 1.3",
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
