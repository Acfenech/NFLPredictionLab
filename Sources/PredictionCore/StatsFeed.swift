import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TeamSnapshot: Sendable, Hashable {
    public let abbreviation: String
    public let record: String
    public let rating: Double
    public let offensiveRating: Double
    public let defensiveRating: Double

    public init(abbreviation: String, record: String, rating: Double,
                offensiveRating: Double? = nil, defensiveRating: Double? = nil) {
        self.abbreviation = abbreviation
        self.record = record
        self.rating = rating
        self.offensiveRating = offensiveRating ?? rating
        self.defensiveRating = defensiveRating ?? rating
    }
}

public protocol TeamStatsFeed: Sendable {
    func currentSeasonWeek(referenceDate: Date) async throws -> (season: Int, week: Int)
    func upcomingMatchups(season: Int, week: Int) async throws -> [Matchup]
    func snapshots(season: Int, week: Int) async throws -> [String: TeamSnapshot]
    func completedResults(season: Int, week: Int) async throws -> [GameResult]
}

public extension TeamStatsFeed {
    func currentSeasonWeek(referenceDate: Date = .now) async throws -> (season: Int, week: Int) {
        throw StatsFeedError.missingFields("current NFL season and week")
    }
}

public enum StatsFeedError: Error, CustomStringConvertible {
    case invalidResponse
    case httpStatus(Int, String)
    case missingFields(String)

    public var description: String {
        switch self {
        case .invalidResponse:
            return "The stats feed returned an invalid response."
        case let .httpStatus(code, preview):
            return "The stats feed returned HTTP \(code): \(preview)"
        case let .missingFields(fields):
            return "The stats feed response is missing: \(fields)"
        }
    }
}

public extension URLRequest {
    static func nflStatsRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("NFLPredictionLab/1.0 (+https://github.com/Acfenech/NFLPredictionLab)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

/// Lightweight, no-key baseline feed using ESPN's public scoreboard endpoint.
/// It supplies current records; a licensed provider can replace it behind TeamStatsFeed.
public struct ESPNScoreboardFeed: TeamStatsFeed {
    public init() {}

    public func currentSeasonWeek(referenceDate: Date = .now) async throws -> (season: Int, week: Int) {
        let guessedSeason = Calendar(identifier: .gregorian).component(.year, from: referenceDate)
        for week in 1...18 where !(try await upcomingMatchups(season: guessedSeason, week: week)).isEmpty {
            return (guessedSeason, week)
        }
        throw StatsFeedError.missingFields("a current ESPN NFL week")
    }

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
        let request = URLRequest.nflStatsRequest(url: components.url!)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let preview = String(decoding: data.prefix(300), as: UTF8.self)
            throw StatsFeedError.httpStatus(http.statusCode, preview)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else {
            throw StatsFeedError.missingFields("events")
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

/// No-key schedule and results feed backed by nflverse's automatically updated
/// `schedules` release. Ratings are based on each team's record before kickoff.
public actor NFLVerseScheduleFeed: TeamStatsFeed {
    private let sourceURL: URL
    private var cachedGames: [ScheduleGame]?

    public init(sourceURL: URL = URL(string: "https://github.com/nflverse/nflverse-data/releases/download/schedules/games.csv")!) {
        self.sourceURL = sourceURL
    }

    public func currentSeasonWeek(referenceDate: Date = .now) async throws -> (season: Int, week: Int) {
        let games = try await loadGames()
        let upcoming = games
            .filter { $0.gameType == "REG" && $0.kickoff >= referenceDate }
            .sorted { $0.kickoff < $1.kickoff }
        guard let next = upcoming.first else {
            throw StatsFeedError.missingFields("a future regular-season game in the nflverse schedule")
        }
        return (next.season, next.week)
    }

    public func upcomingMatchups(season: Int, week: Int) async throws -> [Matchup] {
        let games = try await loadGames()
        return games
            .filter { $0.season == season && $0.gameType == "REG" && $0.week == week && $0.homeScore == nil }
            .sorted { $0.kickoff < $1.kickoff }
            .map {
                Matchup(week: week, kickoff: $0.kickoff,
                        away: Team(abbreviation: $0.away, name: $0.away, offensiveRating: 0, defensiveRating: 0),
                        home: Team(abbreviation: $0.home, name: $0.home, offensiveRating: 0, defensiveRating: 0))
            }
    }

    public func snapshots(season: Int, week: Int) async throws -> [String: TeamSnapshot] {
        let games = try await loadGames()
        let teams = Set(games.filter { $0.season == season && $0.gameType == "REG" && $0.week == week }
            .flatMap { [$0.away, $0.home] })
        var records = Dictionary(uniqueKeysWithValues: teams.map { ($0, (wins: 0, losses: 0, ties: 0)) })

        let completed = games.filter {
            $0.season == season && $0.gameType == "REG" && $0.week < week && $0.awayScore != nil && $0.homeScore != nil
        }
        for game in completed {
            guard let awayScore = game.awayScore, let homeScore = game.homeScore else { continue }
            if awayScore == homeScore {
                records[game.away]?.ties += 1
                records[game.home]?.ties += 1
            } else if awayScore > homeScore {
                records[game.away]?.wins += 1
                records[game.home]?.losses += 1
            } else {
                records[game.home]?.wins += 1
                records[game.away]?.losses += 1
            }
        }

        let leaguePoints = completed.flatMap { [$0.awayScore!, $0.homeScore!] }
        let leagueAverage = leaguePoints.isEmpty ? 22.5 : Double(leaguePoints.reduce(0, +)) / Double(leaguePoints.count)

        func weightedScoring(for team: String) -> (for: Double, against: Double) {
            var pointsFor = 0.0, pointsAgainst = 0.0, totalWeight = 0.0
            for game in completed where game.away == team || game.home == team {
                let weight = pow(0.82, Double(max(0, week - game.week - 1)))
                let isHome = game.home == team
                pointsFor += Double(isHome ? game.homeScore! : game.awayScore!) * weight
                pointsAgainst += Double(isHome ? game.awayScore! : game.homeScore!) * weight
                totalWeight += weight
            }
            guard totalWeight > 0 else { return (leagueAverage, leagueAverage) }
            return (pointsFor / totalWeight, pointsAgainst / totalWeight)
        }

        func opponentAdjustment(for team: String) -> Double {
            let opponents = completed.compactMap { game -> String? in
                if game.home == team { return game.away }
                if game.away == team { return game.home }
                return nil
            }
            guard !opponents.isEmpty else { return 0 }
            return opponents.map { opponent in
                guard let value = records[opponent] else { return 0 }
                let games = value.wins + value.losses + value.ties
                guard games > 0 else { return 0 }
                return ((Double(value.wins) + Double(value.ties) * 0.5) / Double(games) - 0.5) * 4
            }.reduce(0, +) / Double(opponents.count)
        }

        return Dictionary(uniqueKeysWithValues: records.map { abbreviation, value in
            let record = value.ties == 0
                ? "\(value.wins)-\(value.losses)"
                : "\(value.wins)-\(value.losses)-\(value.ties)"
            let scoring = weightedScoring(for: abbreviation)
            let opponent = opponentAdjustment(for: abbreviation)
            let offense = (scoring.for - leagueAverage) * 0.65 + opponent * 0.35
            let defense = (leagueAverage - scoring.against) * 0.65 + opponent * 0.35
            return (abbreviation, TeamSnapshot(abbreviation: abbreviation, record: record,
                                                rating: (offense + defense) / 2,
                                                offensiveRating: offense, defensiveRating: defense))
        })
    }

    public func completedResults(season: Int, week: Int) async throws -> [GameResult] {
        let games = try await loadGames()
        return games.compactMap { game in
            guard game.season == season, game.gameType == "REG", game.week == week,
                  let awayScore = game.awayScore, let homeScore = game.homeScore else { return nil }
            return GameResult(awayAbbreviation: game.away, homeAbbreviation: game.home,
                              awayScore: awayScore, homeScore: homeScore)
        }
    }

    private func loadGames() async throws -> [ScheduleGame] {
        if let cachedGames { return cachedGames }
        let request = URLRequest.nflStatsRequest(url: sourceURL)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw StatsFeedError.httpStatus(http.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
        let games = try Self.parseSchedule(String(decoding: data, as: UTF8.self))
        guard !games.isEmpty else { throw StatsFeedError.missingFields("nflverse schedule rows") }
        cachedGames = games
        return games
    }

    private static func parseSchedule(_ csv: String) throws -> [ScheduleGame] {
        let rows = CSV.rows(csv)
        guard let header = rows.first else { throw StatsFeedError.missingFields("nflverse CSV header") }
        let indexes = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        let required = ["season", "game_type", "week", "gameday", "gametime", "away_team", "away_score", "home_team", "home_score"]
        guard required.allSatisfy({ indexes[$0] != nil }) else {
            throw StatsFeedError.missingFields("required nflverse schedule columns")
        }

        func value(_ row: [String], _ name: String) -> String {
            guard let index = indexes[name], row.indices.contains(index) else { return "" }
            return row[index]
        }

        return rows.dropFirst().compactMap { row in
            guard let season = Int(value(row, "season")), let week = Int(value(row, "week")) else { return nil }
            let dateText = value(row, "gameday")
            let timeText = value(row, "gametime").isEmpty ? "13:00" : value(row, "gametime")
            guard let kickoff = easternDateFormatter.date(from: "\(dateText) \(timeText)") else { return nil }
            return ScheduleGame(season: season, gameType: value(row, "game_type"), week: week,
                                kickoff: kickoff, away: value(row, "away_team"), home: value(row, "home_team"),
                                awayScore: Int(value(row, "away_score")), homeScore: Int(value(row, "home_score")))
        }
    }

    private static let easternDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private struct ScheduleGame: Sendable {
    let season: Int
    let gameType: String
    let week: Int
    let kickoff: Date
    let away: String
    let home: String
    let awayScore: Int?
    let homeScore: Int?
}

private enum CSV {
    static func rows(_ text: String) -> [[String]] {
        var result: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\"" {
                if quoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if character == "," && !quoted {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r") && !quoted {
                if character == "\r", next < text.endIndex, text[next] == "\n" { index = next }
                row.append(field)
                if !row.allSatisfy({ $0.isEmpty }) { result.append(row) }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            result.append(row)
        }
        return result
    }
}

