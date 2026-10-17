import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CryptoKit
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
    let projectedHomeMargin: Double
    let projectedTotal: Double
    let marketHomeMargin: Double?
    let marketTotal: Double?
    let modelOnlyHomeMargin: Double?
    let modelOnlyTotal: Double?
    let reviewFlag: String?
}

struct ForecastOutput: Codable {
    let generatedAt: Date
    let season: Int
    let week: Int
    let source: String
    let modelVersion: String
    let predictions: [OutputPrediction]
}

struct CloudKitPublisher {
    let container: String
    let environment: String
    let keyID: String
    let privateKeyPEM: String

    func publish(_ predictions: [Prediction], season: Int, week: Int, generatedAt: Date) async throws {
        let encoder = JSONEncoder()
        let payload = try encoder.encode(predictions).base64EncodedString()
        func fields(payload: String, count: Int) -> [String: Any] { [
            "payload": ["value": payload, "type": "BYTES"],
            "generatedAt": ["value": Int64(generatedAt.timeIntervalSince1970 * 1_000), "type": "TIMESTAMP"],
            "predictionCount": ["value": count, "type": "INT64"]
        ] }
        let archiveName = "\(season)-W\(week)-\(Int64(generatedAt.timeIntervalSince1970))"
        let previousNames = (try? await historyRecordNames()) ?? []
        let historyNames = Array((previousNames + [archiveName]).suffix(100))
        let historyPayload = try encoder.encode(historyNames).base64EncodedString()
        let bodyObject: [String: Any] = [
            "operations": [
                ("latest", fields(payload: payload, count: predictions.count)),
                (archiveName, fields(payload: payload, count: predictions.count)),
                ("history-index", fields(payload: historyPayload, count: historyNames.count))
            ].map { recordName, recordFields -> [String: Any] in
                [
                    "operationType": "forceReplace",
                    "record": [
                        "recordType": "ForecastBundle",
                        "recordName": recordName,
                        "fields": recordFields
                    ]
                ]
            }
        ]
        let subpath = "/database/1/\(container)/\(environment)/public/records/modify"
        let responseData = try await perform(bodyObject, subpath: subpath)
        if let responseObject = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let records = responseObject["records"] as? [[String: Any]],
           let failure = records.first(where: { $0["serverErrorCode"] != nil }) {
            throw StatsFeedError.missingFields("CloudKit publish failed: \(failure)")
        }
    }

    private func historyRecordNames() async throws -> [String] {
        let subpath = "/database/1/\(container)/\(environment)/public/records/lookup"
        let data = try await perform(["records": [["recordName": "history-index"]]], subpath: subpath)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let record = (root["records"] as? [[String: Any]])?.first,
              record["serverErrorCode"] == nil,
              let fields = record["fields"] as? [String: Any],
              let payload = fields["payload"] as? [String: Any],
              let value = payload["value"] as? String,
              let decoded = Data(base64Encoded: value) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: decoded)) ?? []
    }

    private func perform(_ bodyObject: [String: Any], subpath: String) async throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: bodyObject, options: [.sortedKeys])
        let date = ISO8601DateFormatter().string(from: Date())
        let bodyHash = Data(SHA256.hash(data: body)).base64EncodedString()
        let message = "\(date):\(bodyHash):\(subpath)"
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
        let signature = try privateKey.signature(for: Data(message.utf8)).derRepresentation.base64EncodedString()

        var request = URLRequest(url: URL(string: "https://api.apple-cloudkit.com\(subpath)")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(keyID, forHTTPHeaderField: "X-Apple-CloudKit-Request-KeyID")
        request.setValue(date, forHTTPHeaderField: "X-Apple-CloudKit-Request-ISO8601Date")
        request.setValue(signature, forHTTPHeaderField: "X-Apple-CloudKit-Request-SignatureV1")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw StatsFeedError.httpStatus(status, String(decoding: responseData.prefix(1_000), as: UTF8.self))
        }
        return responseData
    }
}

func espnCurrentSeasonWeek() async throws -> (Int, Int) {
    let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard")!
    let request = URLRequest.nflStatsRequest(url: url)
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
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
let requestedSeason = Int(environment["NFL_SEASON"] ?? "")
let requestedWeek = Int(environment["NFL_WEEK"] ?? "")

var season = 0
var week = 0
var matchups: [Matchup] = []
var snapshots: [String: TeamSnapshot] = [:]
var source = ""

do {
    let feed = NFLVerseScheduleFeed()
    let discovered = try await feed.currentSeasonWeek()
    season = requestedSeason ?? discovered.season
    week = requestedWeek ?? discovered.week
    matchups = try await feed.upcomingMatchups(season: season, week: week)
    snapshots = try await feed.snapshots(season: season, week: week)
    source = "nflverse schedules and results"
} catch {
    print("nflverse unavailable (\(error)); falling back to ESPN scoreboard")
    let feed = ESPNScoreboardFeed()
    let discovered = try await espnCurrentSeasonWeek()
    season = requestedSeason ?? discovered.0
    if let requestedWeek {
        week = requestedWeek
        matchups = try await feed.upcomingMatchups(season: season, week: week)
    } else {
        var selectedWeek: Int?
        var selectedMatchups: [Matchup] = []
        for candidate in discovered.1...18 {
            let games = try await feed.upcomingMatchups(season: season, week: candidate)
            if !games.isEmpty {
                selectedWeek = candidate
                selectedMatchups = games
                break
            }
        }
        guard let selectedWeek else {
            throw StatsFeedError.missingFields("upcoming games from week \(discovered.1) through week 18 of \(season)")
        }
        week = selectedWeek
        matchups = selectedMatchups
    }
    snapshots = try await feed.snapshots(season: season, week: week)
    source = "ESPN scoreboard fallback"
}
guard !matchups.isEmpty else {
    throw StatsFeedError.missingFields("upcoming games for week \(week) of \(season)")
}
let historical = (try? await NFLVerseScheduleFeed().historicalGames(seasons: (season - 3)...(season - 1))) ?? []
let validationReport = ModelTrainer.trainAndValidate(historical)
let engine = ForecastingEngine(configuration: validationReport?.configuration ?? .baseline)
let forecastSnapshots = snapshots
let cloudAdjustments: [String: Double] = {
    guard let json = environment["TEAM_ADJUSTMENTS_JSON"], let data = json.data(using: .utf8),
          let values = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
    return values
}()
var loadedAvailabilityImpacts: [String: AvailabilityImpact] = [:]
if let text = environment["AVAILABILITY_FEED_URL"], let url = URL(string: text) {
    do { loadedAvailabilityImpacts = try await RemoteAvailabilityFeed(url: url).currentImpacts() }
    catch { print("Availability feed unavailable (\(error)); continuing with configured adjustments") }
}
if loadedAvailabilityImpacts.isEmpty {
    do { loadedAvailabilityImpacts = try await NFLVerseFreeDataFeed().availabilityImpacts(season: season, week: week) }
    catch { print("Free nflverse injury report delayed (\(error)); continuing without injury adjustments") }
}
let availabilityImpacts = loadedAvailabilityImpacts
var loadedAdvancedMetrics: [String: AdvancedTeamMetrics] = [:]
if let text = environment["ADVANCED_METRICS_FEED_URL"], let url = URL(string: text) {
    do { loadedAdvancedMetrics = try await RemoteAdvancedMetricsFeed(url: url).currentMetrics() }
    catch { print("Advanced metrics feed unavailable (\(error)); continuing with schedule-derived ratings") }
}
if loadedAdvancedMetrics.isEmpty {
    do { loadedAdvancedMetrics = try await NFLVerseFreeDataFeed().advancedMetrics(season: season, throughWeek: week) }
    catch { print("Free nflverse advanced stats delayed (\(error)); continuing with schedule-derived ratings") }
}
let advancedMetrics = loadedAdvancedMetrics
var loadedGameContexts: [String: GameContext] = [:]
if let text = environment["GAME_CONTEXT_FEED_URL"], let url = URL(string: text) {
    do { loadedGameContexts = try await RemoteGameContextFeed(url: url).currentContexts() }
    catch { print("Game context feed unavailable (\(error)); continuing without weather/travel context") }
}
let freeContexts = await NFLVerseFreeDataFeed().gameContexts(for: matchups)
for (key, context) in freeContexts where loadedGameContexts[key] == nil { loadedGameContexts[key] = context }
let gameContexts = loadedGameContexts

let forecastPredictions = matchups.enumerated().map { offset, matchup in
    func rated(_ team: Team) -> Team {
        let snapshot = forecastSnapshots[team.abbreviation]
        let manualAdjustment = cloudAdjustments[team.abbreviation] ?? 0
        let impact = availabilityImpacts[team.abbreviation]
        let adjustment = manualAdjustment + (impact?.adjustment ?? 0)
        return Team(abbreviation: team.abbreviation, name: team.name,
                    offensiveRating: (snapshot?.offensiveRating ?? 0) + adjustment,
                    defensiveRating: snapshot?.defensiveRating ?? 0,
                    recentForm: snapshot?.recentForm, restDays: snapshot?.restDays,
                    availabilityAdjustment: adjustment,
                    availabilityNote: impact?.note ?? (manualAdjustment == 0 ? nil : "Configured adjustment"),
                    advancedEfficiency: advancedMetrics[team.abbreviation]?.rating)
    }
    let baseContext = gameContexts[matchup.gameKey]
    let quarterbackNotes = [availabilityImpacts[matchup.away.abbreviation]?.note,
                            availabilityImpacts[matchup.home.abbreviation]?.note]
        .compactMap { $0 }.joined(separator: " · ")
    let context = GameContext(weatherSummary: baseContext?.weatherSummary,
        weatherPoints: baseContext?.weatherPoints ?? 0, travelMiles: baseContext?.travelMiles,
        travelPoints: baseContext?.travelPoints ?? 0,
        quarterbackSummary: quarterbackNotes.isEmpty ? nil : quarterbackNotes)
    let ratedMatchup = Matchup(id: matchup.id, week: matchup.week, kickoff: matchup.kickoff,
                               away: rated(matchup.away), home: rated(matchup.home), bettingLine: matchup.bettingLine,
                               context: context)
    return engine.predict(ratedMatchup, seed: UInt64(offset + 1))
}

let generatedAt = Date()
let outputPredictions = forecastPredictions.map { prediction in
    OutputPrediction(gameKey: prediction.matchup.gameKey, kickoff: prediction.matchup.kickoff,
                     away: prediction.matchup.away.abbreviation, home: prediction.matchup.home.abbreviation,
                     awayScore: prediction.awayScore, homeScore: prediction.homeScore,
                     homeWinProbability: prediction.homeWinProbability,
                     simulations: prediction.simulations,
                     projectedHomeMargin: prediction.projectedHomeSpread,
                     projectedTotal: prediction.projectedTotal,
                     marketHomeMargin: prediction.matchup.bettingLine?.homeSpread,
                     marketTotal: prediction.matchup.bettingLine?.total,
                     modelOnlyHomeMargin: prediction.modelOnlyHomeSpread,
                     modelOnlyTotal: prediction.modelOnlyTotal,
                     reviewFlag: prediction.reviewFlag)
}
let output = ForecastOutput(generatedAt: generatedAt, season: season, week: week,
                            source: source, modelVersion: "MVP 1.2", predictions: outputPredictions)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
let outputDirectory = URL(fileURLWithPath: environment["FORECAST_OUTPUT_DIR"] ?? "forecast-output")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let destination = outputDirectory.appendingPathComponent("week-\(week)-forecast.json")
try encoder.encode(output).write(to: destination, options: .atomic)
print("Generated \(forecastPredictions.count) forecasts for \(season) Week \(week): \(destination.path)")

if environment["CLOUDKIT_PUBLISH_ENABLED"] == "true" {
    guard let container = environment["CLOUDKIT_CONTAINER"],
          let keyID = environment["CLOUDKIT_KEY_ID"],
          let privateKey = environment["CLOUDKIT_PRIVATE_KEY"],
          !container.isEmpty, !keyID.isEmpty, !privateKey.isEmpty else {
        throw StatsFeedError.missingFields("CLOUDKIT_CONTAINER, CLOUDKIT_KEY_ID, or CLOUDKIT_PRIVATE_KEY")
    }
    let publisher = CloudKitPublisher(container: container,
                                      environment: environment["CLOUDKIT_ENVIRONMENT"] ?? "development",
                                      keyID: keyID,
                                      privateKeyPEM: privateKey)
    try await publisher.publish(forecastPredictions, season: season, week: week, generatedAt: generatedAt)
    print("Published latest forecast bundle and history snapshot to CloudKit \(publisher.environment)")
}
