import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TeamSnapshot: Sendable, Hashable {
    public let abbreviation: String
    public let record: String
    public let rating: Double

    public init(abbreviation: String, record: String, rating: Double) {
        self.abbreviation = abbreviation
        self.record = record
        self.rating = rating
    }
}

public protocol TeamStatsFeed: Sendable {
    func upcomingMatchups(season: Int, week: Int) async throws -> [Matchup]
    func snapshots(season: Int, week: Int) async throws -> [String: TeamSnapshot]
    func completedResults(season: Int, week: Int) async throws -> [GameResult]
}

public enum StatsFeedError: Error {
    case invalidResponse
}

/// Lightweight, no-key baseline feed using ESPN's public scoreboard endpoint.
/// It supplies current records; a licensed provider can replace it behind TeamStatsFeed.
public struct ESPNScoreboardFeed: TeamStatsFeed {
    public init() {}

    public func upcomingMatchups(season: Int, week: Int) async throws -> [Matchup] {
        let events = try await events(season: season, week: week)
        let games = events.compactMap { event -> Matchup? in
            guard let status = event["status"] as? [String: Any],
                  let type = status["type"] as? [String: Any], type["completed"] as? Bool != true,
                  let dateText = event["date"] as? String,
                  let kickoff = ISO8601DateFormatter().date(from: dateText),
                  let competition = (event["competitions"] as? [[String: Any]])?.first,
                  let competitors = competition["competitors"] as? [[String: Any]] else { return nil }
            func team(_ side: String) -> Team? {
                guard let item = competitors.first(where: { $0["homeAway"] as? String == side }),
                      let data = item["team"] as? [String: Any],
                      let abbreviation = data["abbreviation"] as? String else { return nil }
                let name = data["displayName"] as? String ?? abbreviation
                return Team(abbreviation: abbreviation, name: name, offensiveRating: 0, defensiveRating: 0)
            }
            guard let away = team("away"), let home = team("home") else { return nil }
            return Matchup(week: week, kickoff: kickoff, away: away, home: home)
        }
        guard !games.isEmpty else { throw StatsFeedError.invalidResponse }
        return games.sorted { $0.kickoff < $1.kickoff }
    }

    public func snapshots(season: Int, week: Int) async throws -> [String: TeamSnapshot] {
        let events = try await events(season: season, week: week)
        var result: [String: TeamSnapshot] = [:]
        for event in events {
            guard let competitions = event["competitions"] as? [[String: Any]] else { continue }
            for competition in competitions {
                guard let competitors = competition["competitors"] as? [[String: Any]] else { continue }
                for competitor in competitors {
                    guard let team = competitor["team"] as? [String: Any],
                          let abbreviation = team["abbreviation"] as? String else { continue }
                    let records = competitor["records"] as? [[String: Any]]
                    let record = records?.first?["summary"] as? String ?? "—"
                    result[abbreviation] = TeamSnapshot(abbreviation: abbreviation, record: record, rating: Self.rating(from: record))
                }
            }
        }
        guard !result.isEmpty else { throw StatsFeedError.invalidResponse }
        return result
    }

    public func completedResults(season: Int, week: Int) async throws -> [GameResult] {
        let events = try await events(season: season, week: week)
        return events.compactMap { event in
            guard let status = event["status"] as? [String: Any],
                  let type = status["type"] as? [String: Any], type["completed"] as? Bool == true,
                  let competition = (event["competitions"] as? [[String: Any]])?.first,
                  let competitors = competition["competitors"] as? [[String: Any]] else { return nil }
            func side(_ name: String) -> (String, Int)? {
                guard let item = competitors.first(where: { $0["homeAway"] as? String == name }),
                      let team = item["team"] as? [String: Any],
                      let abbreviation = team["abbreviation"] as? String,
                      let scoreText = item["score"] as? String,
                      let score = Int(scoreText) else { return nil }
                return (abbreviation, score)
            }
            guard let away = side("away"), let home = side("home") else { return nil }
            return GameResult(awayAbbreviation: away.0, homeAbbreviation: home.0, awayScore: away.1, homeScore: home.1)
        }
    }

    private func events(season: Int, week: Int) async throws -> [[String: Any]] {
        var components = URLComponents(string: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard")!
        components.queryItems = [
            URLQueryItem(name: "dates", value: String(season)),
            URLQueryItem(name: "seasontype", value: "2"),
            URLQueryItem(name: "week", value: String(week))
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else {
            throw StatsFeedError.invalidResponse
        }

        return events
    }

    public static func rating(from record: String) -> Double {
        let parts = record.split(separator: "-").compactMap { Double($0) }
        guard parts.count >= 2 else { return 0 }
        let wins = parts[0]
        let losses = parts[1]
        let ties = parts.count > 2 ? parts[2] : 0
        let games = wins + losses + ties
        guard games > 0 else { return 0 }
        return ((wins + ties * 0.5) / games - 0.5) * 10
    }
}

