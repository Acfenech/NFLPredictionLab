import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PredictionCore

struct OutputPrediction: Codable {
    let gameKey: String
    let kickoff: Date
    let away: String
    let home: String
    let awayScore: Double
    let homeScore: Double
    let homeWinProbability: Double
    let simulations: Int
}

struct ForecastOutput: Codable {
    let generatedAt: Date
    let season: Int
    let week: Int
    let source: String
    let predictions: [OutputPrediction]
}

func currentSeasonWeek() async throws -> (Int, Int) {
    let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard")!
    let request = URLRequest.nflStatsRequest(url: url)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw StatsFeedError.invalidResponse }
    guard http.statusCode == 200 else {
        throw StatsFeedError.httpStatus(http.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
    }
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let season = root["season"] as? [String: Any],
          let year = season["year"] as? Int,
          let weekData = root["week"] as? [String: Any],
          let week = weekData["number"] as? Int else {
        throw StatsFeedError.missingFields("season.year or week.number")
    }
    return (year, week)
}

let environment = ProcessInfo.processInfo.environment
let discovered = try await currentSeasonWeek()
let season = Int(environment["NFL_SEASON"] ?? "") ?? discovered.0
let week = Int(environment["NFL_WEEK"] ?? "") ?? discovered.1
let feed = ESPNScoreboardFeed()
async let matchupsRequest = feed.upcomingMatchups(season: season, week: week)
async let snapshotsRequest = feed.snapshots(season: season, week: week)
let (matchups, snapshots) = try await (matchupsRequest, snapshotsRequest)
let engine = ForecastingEngine()

let predictions = matchups.enumerated().map { offset, matchup in
    func rated(_ team: Team) -> Team {
        let rating = snapshots[team.abbreviation]?.rating ?? 0
        return Team(abbreviation: team.abbreviation, name: team.name,
                    offensiveRating: rating, defensiveRating: rating)
    }
    let ratedMatchup = Matchup(id: matchup.id, week: matchup.week, kickoff: matchup.kickoff,
                               away: rated(matchup.away), home: rated(matchup.home))
    let prediction = engine.predict(ratedMatchup, seed: UInt64(offset + 1))
    return OutputPrediction(gameKey: ratedMatchup.gameKey, kickoff: ratedMatchup.kickoff,
                            away: ratedMatchup.away.abbreviation, home: ratedMatchup.home.abbreviation,
                            awayScore: prediction.awayScore, homeScore: prediction.homeScore,
                            homeWinProbability: prediction.homeWinProbability,
                            simulations: prediction.simulations)
}

let output = ForecastOutput(generatedAt: .now, season: season, week: week,
                            source: "ESPN scoreboard baseline", predictions: predictions)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
let outputDirectory = URL(fileURLWithPath: environment["FORECAST_OUTPUT_DIR"] ?? "forecast-output")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let destination = outputDirectory.appendingPathComponent("week-\(week)-forecast.json")
try encoder.encode(output).write(to: destination, options: .atomic)
print("Generated \(predictions.count) forecasts for \(season) Week \(week): \(destination.path)")
