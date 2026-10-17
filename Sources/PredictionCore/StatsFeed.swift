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
    public let recentForm: Double
    public let restDays: Int

    public init(abbreviation: String, record: String, rating: Double,
                offensiveRating: Double? = nil, defensiveRating: Double? = nil,
                recentForm: Double = 0, restDays: Int = 7) {
        self.abbreviation = abbreviation
        self.record = record
        self.rating = rating
        self.offensiveRating = offensiveRating ?? rating
        self.defensiveRating = defensiveRating ?? rating
        self.recentForm = recentForm
        self.restDays = restDays
    }
}

public protocol TeamStatsFeed: Sendable {
    func currentSeasonWeek(referenceDate: Date) async throws -> (season: Int, week: Int)
    func upcomingMatchups(season: Int, week: Int) async throws -> [Matchup]
    func snapshots(season: Int, week: Int) async throws -> [String: TeamSnapshot]
    func completedResults(season: Int, week: Int) async throws -> [GameResult]
    func historicalGames(seasons: ClosedRange<Int>) async throws -> [HistoricalGame]
}

public extension TeamStatsFeed {
    func currentSeasonWeek(referenceDate: Date = .now) async throws -> (season: Int, week: Int) {
        throw StatsFeedError.missingFields("current NFL season and week")
    }
    func historicalGames(seasons: ClosedRange<Int>) async throws -> [HistoricalGame] { [] }
}

public struct AvailabilityImpact: Codable, Hashable, Sendable {
    public let adjustment: Double
    public let note: String
    public init(adjustment: Double, note: String) {
        self.adjustment = adjustment
        self.note = note
    }
}

public protocol PlayerAvailabilityFeed: Sendable {
    func currentImpacts() async throws -> [String: AvailabilityImpact]
}

/// Provider-neutral game context keyed by Matchup.gameKey. This lets a licensed
/// weather/injury feed plug into both the app and scheduled worker without coupling
/// the model to one vendor.
public protocol GameContextFeed: Sendable {
    func currentContexts() async throws -> [String: GameContext]
}

public struct RemoteGameContextFeed: GameContextFeed {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func currentContexts() async throws -> [String: GameContext] {
        let (data, response) = try await URLSession.shared.data(for: .nflStatsRequest(url: url))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw StatsFeedError.httpStatus(http.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return try JSONDecoder().decode([String: GameContext].self, from: data)
    }
}

public struct AdvancedTeamMetrics: Codable, Hashable, Sendable {
    public let offensiveEPA: Double
    public let defensiveEPA: Double
    public let successRate: Double
    public let explosivePlayRate: Double
    public let pressureRate: Double
    public let turnoverRegression: Double

    public init(offensiveEPA: Double, defensiveEPA: Double, successRate: Double,
                explosivePlayRate: Double, pressureRate: Double, turnoverRegression: Double) {
        self.offensiveEPA = offensiveEPA
        self.defensiveEPA = defensiveEPA
        self.successRate = successRate
        self.explosivePlayRate = explosivePlayRate
        self.pressureRate = pressureRate
        self.turnoverRegression = turnoverRegression
    }

    /// Converts normalized play-by-play inputs into a conservative point-scale contribution.
    public var rating: Double {
        offensiveEPA * 8 - defensiveEPA * 6 + (successRate - 0.42) * 12 +
        (explosivePlayRate - 0.10) * 8 + (pressureRate - 0.30) * 4 + turnoverRegression * 0.5
    }
}

public struct RemoteAdvancedMetricsFeed: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func currentMetrics() async throws -> [String: AdvancedTeamMetrics] {
        let (data, response) = try await URLSession.shared.data(for: .nflStatsRequest(url: url))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw StatsFeedError.httpStatus(http.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return try JSONDecoder().decode([String: AdvancedTeamMetrics].self, from: data)
    }
}

/// Provider-neutral JSON adapter. A licensed feed can publish a compact object such as
/// `{ "BUF": { "adjustment": -4.5, "note": "Starting QB out" } }`.
public struct RemoteAvailabilityFeed: PlayerAvailabilityFeed {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func currentImpacts() async throws -> [String: AvailabilityImpact] {
        let (data, response) = try await URLSession.shared.data(for: .nflStatsRequest(url: url))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw StatsFeedError.httpStatus(http.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return try JSONDecoder().decode([String: AvailabilityImpact].self, from: data)
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

public struct MoneylineQuote: Hashable, Sendable {
    public let homeMoneyline: Int
    public let awayMoneyline: Int
    public let bookmakers: Int
    public init(homeMoneyline: Int, awayMoneyline: Int, bookmakers: Int) {
        self.homeMoneyline = homeMoneyline
        self.awayMoneyline = awayMoneyline
        self.bookmakers = bookmakers
    }
}

/// Optional licensed price overlay. The API key is supplied at runtime and is never
/// committed to the project. Prices are the median available US-book decimal price,
/// converted back to American odds to avoid one outlying book driving the display.
public struct TheOddsAPIMoneylineFeed: Sendable {
    public let apiKey: String
    public init(apiKey: String) { self.apiKey = apiKey }

    public func quotes(for matchups: [Matchup]) async throws -> [String: MoneylineQuote] {
        var components = URLComponents(string: "https://api.the-odds-api.com/v4/sports/americanfootball_nfl/odds")!
        components.queryItems = [
            URLQueryItem(name: "apiKey", value: apiKey), URLQueryItem(name: "regions", value: "us"),
            URLQueryItem(name: "markets", value: "h2h"), URLQueryItem(name: "oddsFormat", value: "american")
        ]
        let (data, response) = try await URLSession.shared.data(for: .nflStatsRequest(url: components.url!))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw StatsFeedError.httpStatus(http.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
        let events = try JSONDecoder().decode([OddsEvent].self, from: data)
        var result: [String: MoneylineQuote] = [:]
        for matchup in matchups {
            let homeName = Self.teamNames[matchup.home.abbreviation] ?? matchup.home.name
            let awayName = Self.teamNames[matchup.away.abbreviation] ?? matchup.away.name
            guard let event = events.first(where: { $0.homeTeam == homeName && $0.awayTeam == awayName }) else { continue }
            var home: [Double] = [], away: [Double] = []
            for book in event.bookmakers {
                guard let market = book.markets.first(where: { $0.key == "h2h" }),
                      let homePrice = market.outcomes.first(where: { $0.name == homeName })?.price,
                      let awayPrice = market.outcomes.first(where: { $0.name == awayName })?.price,
                      let homeDecimal = OddsMath.decimal(fromAmerican: homePrice),
                      let awayDecimal = OddsMath.decimal(fromAmerican: awayPrice) else { continue }
                home.append(homeDecimal); away.append(awayDecimal)
            }
            guard let homeMedian = Self.median(home), let awayMedian = Self.median(away),
                  let homeAmerican = OddsMath.american(fromDecimal: homeMedian),
                  let awayAmerican = OddsMath.american(fromDecimal: awayMedian) else { continue }
            result[matchup.gameKey] = MoneylineQuote(homeMoneyline: homeAmerican,
                awayMoneyline: awayAmerican, bookmakers: min(home.count, away.count))
        }
        return result
    }

    private struct OddsEvent: Decodable {
        let homeTeam: String; let awayTeam: String; let bookmakers: [Bookmaker]
        enum CodingKeys: String, CodingKey { case homeTeam = "home_team", awayTeam = "away_team", bookmakers }
    }
    private struct Bookmaker: Decodable { let markets: [Market] }
    private struct Market: Decodable { let key: String; let outcomes: [Outcome] }
    private struct Outcome: Decodable { let name: String; let price: Int }
    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }; let sorted = values.sorted(); let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
    static let teamNames = [
        "ARI":"Arizona Cardinals", "ATL":"Atlanta Falcons", "BAL":"Baltimore Ravens", "BUF":"Buffalo Bills",
        "CAR":"Carolina Panthers", "CHI":"Chicago Bears", "CIN":"Cincinnati Bengals", "CLE":"Cleveland Browns",
        "DAL":"Dallas Cowboys", "DEN":"Denver Broncos", "DET":"Detroit Lions", "GB":"Green Bay Packers",
        "HOU":"Houston Texans", "IND":"Indianapolis Colts", "JAX":"Jacksonville Jaguars", "KC":"Kansas City Chiefs",
        "LA":"Los Angeles Rams", "LAC":"Los Angeles Chargers", "LV":"Las Vegas Raiders", "MIA":"Miami Dolphins",
        "MIN":"Minnesota Vikings", "NE":"New England Patriots", "NO":"New Orleans Saints", "NYG":"New York Giants",
        "NYJ":"New York Jets", "PHI":"Philadelphia Eagles", "PIT":"Pittsburgh Steelers", "SEA":"Seattle Seahawks",
        "SF":"San Francisco 49ers", "TB":"Tampa Bay Buccaneers", "TEN":"Tennessee Titans", "WAS":"Washington Commanders"
    ]
}

/// Current consensus player-prop prices. This intentionally requests four core
/// volume markets once per event so a weekly refresh remains practical on the
/// free 500-credit plan.
public struct TheOddsAPIPlayerPropsFeed: Sendable {
    public static let marketKeys = ["player_pass_yds", "player_rush_yds", "player_reception_yds", "player_receptions"]
    public let apiKey: String
    public init(apiKey: String) { self.apiKey = apiKey }

    public func quotes(for matchups: [Matchup]) async throws -> [String: [PlayerPropQuote]] {
        try await fetchReport(for: matchups).quotesByGame
    }

    /// Fetches every event independently. A missing or unsupported prop market for one
    /// game no longer discards good quotes from the rest of the week.
    public func fetchReport(for matchups: [Matchup]) async throws -> PlayerPropsFetchReport {
        var eventComponents = URLComponents(string: "https://api.the-odds-api.com/v4/sports/americanfootball_nfl/events")!
        eventComponents.queryItems = [URLQueryItem(name: "apiKey", value: apiKey)]
        let (eventData, eventResponse) = try await URLSession.shared.data(for: .nflStatsRequest(url: eventComponents.url!))
        if let http = eventResponse as? HTTPURLResponse, http.statusCode != 200 {
            throw StatsFeedError.httpStatus(http.statusCode, String(decoding: eventData.prefix(300), as: UTF8.self))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = try decoder.decode([Event].self, from: eventData)
        var requests: [(Matchup, Event)] = []
        var diagnostics: [String] = []
        for matchup in matchups {
            let homeName = TheOddsAPIMoneylineFeed.teamNames[matchup.home.abbreviation] ?? matchup.home.name
            let awayName = TheOddsAPIMoneylineFeed.teamNames[matchup.away.abbreviation] ?? matchup.away.name
            guard let event = events.first(where: { $0.homeTeam == homeName && $0.awayTeam == awayName }) else {
                diagnostics.append("\(matchup.gameKey): no matching event returned by The Odds API")
                continue
            }
            requests.append((matchup, event))
        }

        let apiKey = self.apiKey
        let results = await withTaskGroup(of: EventRequestResult.self, returning: [EventRequestResult].self) { group in
            for (matchup, event) in requests {
                group.addTask {
                    await Self.fetchEvent(matchup: matchup, event: event, apiKey: apiKey)
                }
            }
            var values: [EventRequestResult] = []
            for await value in group { values.append(value) }
            return values
        }

        var quotesByGame: [String: [PlayerPropQuote]] = [:]
        for result in results.sorted(by: { $0.gameKey < $1.gameKey }) {
            if let quotes = result.quotes, !quotes.isEmpty { quotesByGame[result.gameKey] = quotes }
            diagnostics.append(result.diagnostic)
        }
        return PlayerPropsFetchReport(quotesByGame: quotesByGame, diagnostics: diagnostics)
    }

    private static func fetchEvent(matchup: Matchup, event: Event, apiKey: String) async -> EventRequestResult {
        do {
            var components = URLComponents(string: "https://api.the-odds-api.com/v4/sports/americanfootball_nfl/events/\(event.id)/odds")!
            components.queryItems = [
                URLQueryItem(name: "apiKey", value: apiKey), URLQueryItem(name: "regions", value: "us"),
                URLQueryItem(name: "markets", value: Self.marketKeys.joined(separator: ",")),
                URLQueryItem(name: "oddsFormat", value: "american")
            ]
            let (data, response) = try await URLSession.shared.data(for: .nflStatsRequest(url: components.url!))
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let body = String(decoding: data.prefix(500), as: UTF8.self)
                let remaining = http.value(forHTTPHeaderField: "x-requests-remaining") ?? "unknown"
                return EventRequestResult(gameKey: matchup.gameKey, quotes: nil,
                    diagnostic: "\(matchup.gameKey): HTTP \(http.statusCode), quota remaining \(remaining), response \(body)")
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let detail = try decoder.decode(EventDetail.self, from: data)
            let quotes = Self.consensusQuotes(from: detail)
            let remaining = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "x-requests-remaining") ?? "unknown"
            return EventRequestResult(gameKey: matchup.gameKey, quotes: quotes,
                diagnostic: "\(matchup.gameKey): \(quotes.count) quotes, \(detail.bookmakers.count) books, quota remaining \(remaining)")
        } catch {
            return EventRequestResult(gameKey: matchup.gameKey, quotes: nil,
                diagnostic: "\(matchup.gameKey): request failed: \(error)")
        }
    }

    private static func consensusQuotes(from event: EventDetail) -> [PlayerPropQuote] {
        struct Key: Hashable { let player, market, selection: String; let point: Double }
        var prices: [Key: [Double]] = [:]
        var updates: [Key: Date] = [:]
        for book in event.bookmakers {
            for market in book.markets where marketKeys.contains(market.key) {
                for outcome in market.outcomes {
                    guard let player = outcome.description, let point = outcome.point,
                          let decimal = OddsMath.decimal(fromAmerican: outcome.price) else { continue }
                    let key = Key(player: player, market: market.key, selection: outcome.name, point: point)
                    prices[key, default: []].append(decimal)
                    if let update = market.lastUpdate, update > (updates[key] ?? .distantPast) { updates[key] = update }
                }
            }
        }
        return prices.compactMap { key, values in
            guard let median = median(values), let odds = OddsMath.american(fromDecimal: median) else { return nil }
            return PlayerPropQuote(player: key.player, marketKey: key.market,
                marketName: marketNames[key.market] ?? key.market, selection: key.selection,
                point: key.point, odds: odds, bookmakers: values.count, updatedAt: updates[key])
        }.sorted { lhs, rhs in
            lhs.player == rhs.player ? lhs.marketName < rhs.marketName : lhs.player < rhs.player
        }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted(), middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private struct EventRequestResult: Sendable {
        let gameKey: String
        let quotes: [PlayerPropQuote]?
        let diagnostic: String
    }
    private struct Event: Decodable, Sendable {
        let id: String; let homeTeam: String; let awayTeam: String
        enum CodingKeys: String, CodingKey { case id, homeTeam = "home_team", awayTeam = "away_team" }
    }
    private struct EventDetail: Decodable { let bookmakers: [Bookmaker] }
    private struct Bookmaker: Decodable { let markets: [Market] }
    private struct Market: Decodable {
        let key: String; let lastUpdate: Date?; let outcomes: [Outcome]
        enum CodingKeys: String, CodingKey { case key, lastUpdate = "last_update", outcomes }
    }
    private struct Outcome: Decodable { let name: String; let description: String?; let price: Int; let point: Double? }
    private static let marketNames = [
        "player_pass_yds": "Passing yards", "player_rush_yds": "Rushing yards",
        "player_reception_yds": "Receiving yards", "player_receptions": "Receptions"
    ]
}

public struct PlayerPropsFetchReport: Sendable {
    public let quotesByGame: [String: [PlayerPropQuote]]
    public let diagnostics: [String]
    public init(quotesByGame: [String: [PlayerPropQuote]], diagnostics: [String]) {
        self.quotesByGame = quotesByGame
        self.diagnostics = diagnostics
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

    public func historicalGames(seasons: ClosedRange<Int>) async throws -> [HistoricalGame] { [] }

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
                        home: Team(abbreviation: $0.home, name: $0.home, offensiveRating: 0, defensiveRating: 0),
                        bettingLine: $0.bettingLine)
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

        func recentForm(for team: String) -> Double {
            let margins = completed.filter { $0.away == team || $0.home == team }
                .sorted { $0.kickoff > $1.kickoff }.prefix(4).map { game -> Double in
                    let isHome = game.home == team
                    return Double((isHome ? game.homeScore! : game.awayScore!) - (isHome ? game.awayScore! : game.homeScore!))
                }
            return margins.isEmpty ? 0 : margins.reduce(0, +) / Double(margins.count)
        }

        func restDays(for team: String) -> Int {
            guard let kickoff = games.first(where: { $0.season == season && $0.week == week && ($0.away == team || $0.home == team) })?.kickoff,
                  let previous = completed.filter({ $0.away == team || $0.home == team }).map(\.kickoff).max() else { return 7 }
            return max(3, min(14, Calendar(identifier: .gregorian).dateComponents([.day], from: previous, to: kickoff).day ?? 7))
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
                                                offensiveRating: offense, defensiveRating: defense,
                                                recentForm: recentForm(for: abbreviation), restDays: restDays(for: abbreviation)))
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

    public func historicalGames(seasons: ClosedRange<Int>) async throws -> [HistoricalGame] {
        let games = try await loadGames()
        var output: [HistoricalGame] = []
        for season in seasons {
            for week in 2...18 {
                let snapshots = try await snapshots(season: season, week: week)
                for game in games where game.season == season && game.gameType == "REG" && game.week == week {
                    guard let awayScore = game.awayScore, let homeScore = game.homeScore,
                          let away = snapshots[game.away], let home = snapshots[game.home] else { continue }
                    let matchup = Matchup(week: week, kickoff: game.kickoff,
                        away: Team(abbreviation: game.away, name: game.away,
                                   offensiveRating: away.offensiveRating, defensiveRating: away.defensiveRating,
                                   recentForm: away.recentForm, restDays: away.restDays),
                        home: Team(abbreviation: game.home, name: game.home,
                                   offensiveRating: home.offensiveRating, defensiveRating: home.defensiveRating,
                                   recentForm: home.recentForm, restDays: home.restDays),
                        bettingLine: game.bettingLine)
                    let result = GameResult(awayAbbreviation: game.away, homeAbbreviation: game.home,
                                            awayScore: awayScore, homeScore: homeScore)
                    output.append(HistoricalGame(season: season, matchup: matchup, result: result))
                }
            }
        }
        return output
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
            let completed = Int(value(row, "home_score")) != nil
            let spread = Double(value(row, "spread_line"))
            let total = Double(value(row, "total_line"))
            return ScheduleGame(season: season, gameType: value(row, "game_type"), week: week,
                                kickoff: kickoff, away: value(row, "away_team"), home: value(row, "home_team"),
                                awayScore: Int(value(row, "away_score")), homeScore: Int(value(row, "home_score")),
                                bettingLine: BettingLine(homeSpread: spread,
                                                         total: total,
                                                         homeMoneyline: Int(value(row, "home_moneyline")),
                                                         awayMoneyline: Int(value(row, "away_moneyline")),
                                                         closingHomeSpread: completed ? spread : nil,
                                                         closingTotal: completed ? total : nil))
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
    let bettingLine: BettingLine
}

enum CSV {
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

/// Free, keyless inputs used by the private app and GitHub Actions worker.
/// nflverse supplies injuries, depth charts and team summaries; Open-Meteo
/// supplies kickoff weather. All calls fail independently so forecasts remain usable.
public struct NFLVerseFreeDataFeed: Sendable {
    public init() {}

    public func availabilityImpacts(season: Int, week: Int) async throws -> [String: AvailabilityImpact] {
        async let injuryText = text(URL(string: "https://github.com/nflverse/nflverse-data/releases/download/injuries/injuries_\(season).csv")!)
        async let depthText = text(URL(string: "https://github.com/nflverse/nflverse-data/releases/download/depth_charts/depth_charts_\(season).csv")!)
        let injuries = try await injuryText
        let depth = try? await depthText
        let rows = CSV.rows(injuries)
        guard let header = rows.first else { throw StatsFeedError.missingFields("injury CSV header") }
        let indexes = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        func value(_ row: [String], _ name: String) -> String {
            guard let index = indexes[name], row.indices.contains(index) else { return "" }
            return row[index]
        }

        let starters = depth.map { startingQuarterbacks(csv: $0) } ?? [:]
        var entries: [String: [(name: String, position: String, status: String, points: Double)]] = [:]
        for row in rows.dropFirst() where Int(value(row, "week")) == week && value(row, "season_type") == "REG" {
            let team = value(row, "team"), position = value(row, "position").uppercased()
            let status = value(row, "report_status").lowercased()
            guard !team.isEmpty, !status.isEmpty else { continue }
            let isStartingQB = position == "QB" && (starters[team] == nil || starters[team] == value(row, "full_name"))
            let severity: Double
            if status.contains("out") { severity = isStartingQB ? -6.0 : positionImpact(position) }
            else if status.contains("doubt") { severity = isStartingQB ? -4.0 : positionImpact(position) * 0.7 }
            else if status.contains("question") { severity = isStartingQB ? -2.0 : positionImpact(position) * 0.35 }
            else { continue }
            entries[team, default: []].append((value(row, "full_name"), position, value(row, "report_status"), severity))
        }
        return entries.mapValues { values in
            let sorted = values.sorted { abs($0.points) > abs($1.points) }
            let adjustment = max(-10, sorted.map(\.points).reduce(0, +))
            let note = sorted.prefix(3).map { "\($0.name) (\($0.position), \($0.status))" }.joined(separator: "; ")
            return AvailabilityImpact(adjustment: adjustment, note: note)
        }
    }

    public func advancedMetrics(season: Int, throughWeek: Int) async throws -> [String: AdvancedTeamMetrics] {
        let csv = try await text(URL(string: "https://github.com/nflverse/nflverse-data/releases/download/stats_team/stats_team_week_\(season).csv")!)
        let rows = CSV.rows(csv)
        guard let header = rows.first else { throw StatsFeedError.missingFields("team stats CSV header") }
        let indexes = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        func value(_ row: [String], _ name: String) -> String {
            guard let index = indexes[name], row.indices.contains(index) else { return "" }
            return row[index]
        }
        struct Totals { var epa = 0.0; var plays = 0.0; var firstDowns = 0.0; var yards = 0.0; var sacks = 0.0; var turnovers = 0.0 }
        var offense: [String: Totals] = [:], allowed: [String: Totals] = [:]
        func merged(_ lhs: Totals, _ rhs: Totals) -> Totals {
            Totals(epa: lhs.epa + rhs.epa, plays: lhs.plays + rhs.plays,
                   firstDowns: lhs.firstDowns + rhs.firstDowns, yards: lhs.yards + rhs.yards,
                   sacks: lhs.sacks + rhs.sacks, turnovers: lhs.turnovers + rhs.turnovers)
        }
        for row in rows.dropFirst() where value(row, "season_type") == "REG" && (Int(value(row, "week")) ?? 99) < throughWeek {
            let team = value(row, "team"), opponent = value(row, "opponent_team")
            guard !team.isEmpty, !opponent.isEmpty else { continue }
            let attempts = Double(value(row, "attempts")) ?? 0
            let carries = Double(value(row, "carries")) ?? 0
            let plays = max(1, attempts + carries)
            var total = Totals()
            total.epa = (Double(value(row, "passing_epa")) ?? 0) + (Double(value(row, "rushing_epa")) ?? 0)
            total.plays = plays
            total.firstDowns = (Double(value(row, "passing_first_downs")) ?? 0) + (Double(value(row, "rushing_first_downs")) ?? 0)
            total.yards = (Double(value(row, "passing_yards")) ?? 0) + (Double(value(row, "rushing_yards")) ?? 0)
            total.sacks = Double(value(row, "sacks_suffered")) ?? 0
            total.turnovers = (Double(value(row, "passing_interceptions")) ?? 0) + (Double(value(row, "sack_fumbles_lost")) ?? 0) + (Double(value(row, "rushing_fumbles_lost")) ?? 0)
            offense[team] = merged(offense[team] ?? Totals(), total)
            allowed[opponent] = merged(allowed[opponent] ?? Totals(), total)
        }
        return Dictionary(uniqueKeysWithValues: offense.map { team, own in
            let defense = allowed[team] ?? Totals()
            let offensiveEPA = own.epa / max(1, own.plays)
            let defensiveEPA = defense.epa / max(1, defense.plays)
            let success = own.firstDowns / max(1, own.plays)
            let explosive = min(0.25, max(0.04, own.yards / max(1, own.plays) / 55))
            let pressure = min(0.55, max(0.15, defense.sacks / max(1, defense.plays) * 4.5 + 0.22))
            let turnoverRegression = (1.5 - own.turnovers / max(1, own.plays) * 60) * 0.25
            return (team, AdvancedTeamMetrics(offensiveEPA: offensiveEPA, defensiveEPA: defensiveEPA,
                successRate: success, explosivePlayRate: explosive, pressureRate: pressure,
                turnoverRegression: turnoverRegression))
        })
    }

    public func gameContexts(for matchups: [Matchup]) async -> [String: GameContext] {
        await withTaskGroup(of: (String, GameContext).self) { group in
            for matchup in matchups {
                group.addTask {
                    let venue = venueCoordinate(for: matchup)
                    let away = Self.teamCoordinates[matchup.away.abbreviation] ?? venue
                    let miles = Int(haversineMiles(from: away, to: venue).rounded())
                    let travelPoints = miles >= 2_000 ? 1.2 : miles >= 1_000 ? 0.6 : 0
                    let weather = try? await kickoffWeather(coordinate: venue, kickoff: matchup.kickoff)
                    return (matchup.gameKey, GameContext(weatherSummary: weather?.summary,
                        weatherPoints: weather?.points ?? 0, travelMiles: miles,
                        travelPoints: travelPoints, quarterbackSummary: nil))
                }
            }
            var output: [String: GameContext] = [:]
            for await (key, context) in group { output[key] = context }
            return output
        }
    }

    private func text(_ url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: .nflStatsRequest(url: url))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw StatsFeedError.httpStatus(http.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func startingQuarterbacks(csv: String) -> [String: String] {
        let rows = CSV.rows(csv)
        guard let header = rows.first else { return [:] }
        let indexes = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        func value(_ row: [String], _ name: String) -> String {
            guard let index = indexes[name], row.indices.contains(index) else { return "" }
            return row[index]
        }
        var result: [String: (date: String, name: String)] = [:]
        for row in rows.dropFirst() {
            let position = value(row, "pos_abb").isEmpty ? value(row, "position") : value(row, "pos_abb")
            let rank = Int(value(row, "pos_rank")) ?? Int(value(row, "depth_team")) ?? 99
            guard position == "QB", rank == 1 else { continue }
            let team = value(row, "team").isEmpty ? value(row, "club_code") : value(row, "team")
            let name = value(row, "player_name").isEmpty ? value(row, "full_name") : value(row, "player_name")
            let date = value(row, "dt")
            if result[team] == nil || result[team]!.date <= date { result[team] = (date, name) }
        }
        return result.mapValues(\.name)
    }

    private func positionImpact(_ position: String) -> Double {
        switch position { case "WR", "RB", "TE", "T", "OT", "DE", "DT", "LB", "CB", "S": return -0.7; default: return -0.35 }
    }
}

private struct GeoCoordinate: Sendable { let latitude: Double; let longitude: Double }

private extension NFLVerseFreeDataFeed {
    static let teamCoordinates: [String: GeoCoordinate] = [
        "ARI": .init(latitude: 33.5276, longitude: -112.2626), "ATL": .init(latitude: 33.7554, longitude: -84.4008),
        "BAL": .init(latitude: 39.2780, longitude: -76.6227), "BUF": .init(latitude: 42.7738, longitude: -78.7870),
        "CAR": .init(latitude: 35.2258, longitude: -80.8528), "CHI": .init(latitude: 41.8623, longitude: -87.6167),
        "CIN": .init(latitude: 39.0954, longitude: -84.5160), "CLE": .init(latitude: 41.5061, longitude: -81.6995),
        "DAL": .init(latitude: 32.7473, longitude: -97.0945), "DEN": .init(latitude: 39.7439, longitude: -105.0201),
        "DET": .init(latitude: 42.3400, longitude: -83.0456), "GB": .init(latitude: 44.5013, longitude: -88.0622),
        "HOU": .init(latitude: 29.6847, longitude: -95.4107), "IND": .init(latitude: 39.7601, longitude: -86.1639),
        "JAX": .init(latitude: 30.3239, longitude: -81.6373), "KC": .init(latitude: 39.0489, longitude: -94.4839),
        "LA": .init(latitude: 33.9535, longitude: -118.3392), "LAC": .init(latitude: 33.9535, longitude: -118.3392),
        "LV": .init(latitude: 36.0908, longitude: -115.1830), "MIA": .init(latitude: 25.9580, longitude: -80.2389),
        "MIN": .init(latitude: 44.9738, longitude: -93.2577), "NE": .init(latitude: 42.0909, longitude: -71.2643),
        "NO": .init(latitude: 29.9511, longitude: -90.0812), "NYG": .init(latitude: 40.8135, longitude: -74.0745),
        "NYJ": .init(latitude: 40.8135, longitude: -74.0745), "PHI": .init(latitude: 39.9008, longitude: -75.1675),
        "PIT": .init(latitude: 40.4468, longitude: -80.0158), "SEA": .init(latitude: 47.5952, longitude: -122.3316),
        "SF": .init(latitude: 37.4030, longitude: -121.9700), "TB": .init(latitude: 27.9759, longitude: -82.5033),
        "TEN": .init(latitude: 36.1665, longitude: -86.7713), "WAS": .init(latitude: 38.9078, longitude: -76.8645)
    ]
}

private func venueCoordinate(for matchup: Matchup) -> GeoCoordinate {
    // The early Sunday international window is played outside the designated home stadium.
    if Calendar(identifier: .gregorian).component(.hour, from: matchup.kickoff) < 16 {
        return GeoCoordinate(latitude: 51.5560, longitude: -0.2796)
    }
    return NFLVerseFreeDataFeed.teamCoordinates[matchup.home.abbreviation] ?? GeoCoordinate(latitude: 39.5, longitude: -98.35)
}

private func haversineMiles(from lhs: GeoCoordinate, to rhs: GeoCoordinate) -> Double {
    let radius = 3_958.8
    let lat1 = lhs.latitude * .pi / 180, lat2 = rhs.latitude * .pi / 180
    let dLat = (rhs.latitude - lhs.latitude) * .pi / 180
    let dLon = (rhs.longitude - lhs.longitude) * .pi / 180
    let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
    return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
}

private func kickoffWeather(coordinate: GeoCoordinate, kickoff: Date) async throws -> (summary: String, points: Double) {
    var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
    components.queryItems = [
        URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
        URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
        URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,rain,snowfall,wind_speed_10m"),
        URLQueryItem(name: "temperature_unit", value: "fahrenheit"), URLQueryItem(name: "wind_speed_unit", value: "mph"),
        URLQueryItem(name: "timezone", value: "UTC"), URLQueryItem(name: "forecast_days", value: "16")
    ]
    let (data, response) = try await URLSession.shared.data(for: .nflStatsRequest(url: components.url!))
    if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw StatsFeedError.httpStatus(http.statusCode, "Open-Meteo") }
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let hourly = root["hourly"] as? [String: Any], let times = hourly["time"] as? [String] else { throw StatsFeedError.invalidResponse }
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    let parsed = times.compactMap(formatter.date(from:))
    guard let index = parsed.indices.min(by: { abs(parsed[$0].timeIntervalSince(kickoff)) < abs(parsed[$1].timeIntervalSince(kickoff)) }) else { throw StatsFeedError.invalidResponse }
    func number(_ name: String) -> Double {
        guard let values = hourly[name] as? [Any], values.indices.contains(index) else { return 0 }
        return (values[index] as? NSNumber)?.doubleValue ?? 0
    }
    let temperature = number("temperature_2m"), wind = number("wind_speed_10m"), precipitation = number("precipitation_probability"), rain = number("rain"), snow = number("snowfall")
    var points = 0.0
    if wind >= 20 { points -= 4 } else if wind >= 14 { points -= 2 }
    if precipitation >= 60 || rain >= 0.08 { points -= 1.5 }
    if snow > 0 { points -= 2.5 }
    if temperature <= 25 { points -= 1 }
    let summary = "\(temperature.formatted(.number.precision(.fractionLength(0))))°F · wind \(wind.formatted(.number.precision(.fractionLength(0)))) mph · precipitation \(precipitation.formatted(.number.precision(.fractionLength(0))))%"
    return (summary, points)
}

