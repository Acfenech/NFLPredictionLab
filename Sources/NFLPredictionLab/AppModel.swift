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
    @Published private(set) var storageLabel = "CloudKit"

    private let fallbackMatchups = SampleData.matchups
    private let feed: any TeamStatsFeed
    private let repository: any PredictionRepository

    init(feed: any TeamStatsFeed = NFLVerseScheduleFeed(), repository: (any PredictionRepository)? = nil) {
        self.feed = feed
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
        do {
            let discovered = try await feed.currentSeasonWeek(referenceDate: .now)
            season = discovered.season
            week = discovered.week
            async let scheduleRequest = feed.upcomingMatchups(season: season, week: week)
            async let snapshotsRequest = feed.snapshots(season: season, week: week)
            async let resultsRequest = feed.completedResults(season: season, week: week)
            let (liveMatchups, snapshots, results) = try await (scheduleRequest, snapshotsRequest, resultsRequest)
            let matchups = liveMatchups
            let required = Set(matchups.flatMap { [$0.away.abbreviation, $0.home.abbreviation] })
            let missing = required.subtracting(snapshots.keys)
            let ratedMatchups = matchups.map { matchup in
                Matchup(id: matchup.id, week: matchup.week, kickoff: matchup.kickoff,
                        away: Self.rated(matchup.away, with: snapshots),
                        home: Self.rated(matchup.home, with: snapshots))
            }
            predictions = await calculate(ratedMatchups, preserving: saved)
            do { try await repository.save(predictions) }
            catch { notices.append("Cloud save failed") }
            gradedPredictions = grade(predictions: predictions, results: results)
            lastUpdated = predictions.map(\.generatedAt).max()
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
            lastUpdated = predictions.map(\.generatedAt).max()
            status = (["Stats feed unavailable · cached or neutral forecasts shown"] + notices).joined(separator: " · ")
        }
    }

    private nonisolated static func rated(_ team: Team, with snapshots: [String: TeamSnapshot]) -> Team {
        let rating = snapshots[team.abbreviation]?.rating ?? 0
        return Team(abbreviation: team.abbreviation, name: team.name, offensiveRating: rating, defensiveRating: rating)
    }

    private func calculate(_ matchups: [Matchup], preserving saved: [Prediction]) async -> [Prediction] {
        await Task.detached {
            let engine = ForecastingEngine()
            return matchups.enumerated().map { offset, matchup in
                let prior = saved.first { $0.matchup.gameKey == matchup.gameKey }
                let fresh = engine.predict(matchup, seed: UInt64(offset + 1))
                return Prediction(id: prior?.id ?? fresh.id, matchup: matchup, homeScore: fresh.homeScore,
                                  awayScore: fresh.awayScore, homeWinProbability: fresh.homeWinProbability,
                                  simulations: fresh.simulations, generatedAt: prior?.generatedAt ?? fresh.generatedAt,
                                  simulationSummary: fresh.simulationSummary)
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
