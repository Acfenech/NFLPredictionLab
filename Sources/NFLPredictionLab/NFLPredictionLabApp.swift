import SwiftUI
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
    @State private var selection = 0
    @StateObject private var model = AppModel()

    var body: some View {
        TabView(selection: $selection) {
            PredictionsView(predictions: model.predictions, season: model.season, week: model.week, feedStatus: model.status, isRefreshing: model.isRefreshing) { Task { await model.refresh() } }.tabItem { Label("Forecasts", systemImage: "sportscourt") }.tag(0)
            SimulationView(predictions: model.predictions).tabItem { Label("Simulations", systemImage: "waveform.path.ecg") }.tag(1)
            AccuracyView(grades: model.gradedPredictions).tabItem { Label("Accuracy", systemImage: "chart.line.uptrend.xyaxis") }.tag(2)
            SettingsView(storageLabel: model.storageLabel, lastUpdated: model.lastUpdated).tabItem { Label("Model", systemImage: "slider.horizontal.3") }.tag(3)
        }
        .frame(minWidth: 760, minHeight: 540)
        .task { await model.refresh() }
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
            List(predictions) { prediction in
                NavigationLink {
                    MatchupDetail(prediction: prediction)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("\(prediction.matchup.away.abbreviation) at \(prediction.matchup.home.abbreviation)").font(.headline)
                            Spacer()
                            Text(prediction.confidence < 0.55 ? "Near toss-up" : "\(prediction.predictedWinner.abbreviation) wins")
                                .foregroundStyle(prediction.confidence < 0.55 ? .orange : .blue).fontWeight(.semibold)
                        }
                        Text("Projected: \(prediction.matchup.away.abbreviation) \(prediction.awayScore, specifier: "%.0f") – \(prediction.matchup.home.abbreviation) \(prediction.homeScore, specifier: "%.0f")")
                        Text(prediction.matchup.kickoff.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: prediction.confidence) { Text("Confidence \(prediction.confidence, format: .percent.precision(.fractionLength(0)))") }
                    }.padding(.vertical, 6)
                }
            }
            .navigationTitle(week > 0 ? String(format: "%d Week %d Forecasts", season, week) : "NFL Forecasts")
            .toolbar { Button(action: refresh) { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(isRefreshing) }
            .safeAreaInset(edge: .bottom) {
                Text(feedStatus).font(.caption).foregroundStyle(.secondary).padding(8)
            }
        }
    }
}

struct MatchupDetail: View {
    let prediction: Prediction
    var body: some View {
        Form {
            Section("Prediction") {
                LabeledContent("Winner", value: prediction.predictedWinner.name)
                LabeledContent("Score", value: "\(prediction.matchup.away.abbreviation) \(prediction.awayScore.formatted(.number.precision(.fractionLength(0)))) – \(prediction.matchup.home.abbreviation) \(prediction.homeScore.formatted(.number.precision(.fractionLength(0))))")
                LabeledContent("Home win probability", value: prediction.homeWinProbability.formatted(.percent.precision(.fractionLength(1))))
            }
            Section("Matchup intelligence") {
                LabeledContent("Home offense / defense", value: "\(prediction.matchup.home.offensiveRating.formatted(.number.precision(.fractionLength(1)))) / \(prediction.matchup.home.defensiveRating.formatted(.number.precision(.fractionLength(1))))")
                LabeledContent("Away offense / defense", value: "\(prediction.matchup.away.offensiveRating.formatted(.number.precision(.fractionLength(1)))) / \(prediction.matchup.away.defensiveRating.formatted(.number.precision(.fractionLength(1))))")
            }
        }.navigationTitle("Matchup")
    }
}

struct SimulationView: View {
    let predictions: [Prediction]
    var body: some View {
        NavigationStack {
            List(predictions) { p in
                VStack(alignment: .leading, spacing: 5) {
                    LabeledContent("\(p.matchup.away.abbreviation) at \(p.matchup.home.abbreviation)", value: "\(p.simulations.formatted()) runs")
                    Text("\(p.matchup.home.abbreviation) win \(p.homeWinProbability.formatted(.percent.precision(.fractionLength(1)))) · Upset \((1 - p.confidence).formatted(.percent.precision(.fractionLength(1))))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let s = p.simulationSummary {
                        Text("80% range: \(p.matchup.away.abbreviation) \(s.awayLow.formatted(.number.precision(.fractionLength(0))))–\(s.awayHigh.formatted(.number.precision(.fractionLength(0)))) · \(p.matchup.home.abbreviation) \(s.homeLow.formatted(.number.precision(.fractionLength(0))))–\(s.homeHigh.formatted(.number.precision(.fractionLength(0))))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Most common score: \(p.matchup.away.abbreviation) \(s.mostLikelyAwayScore) – \(p.matchup.home.abbreviation) \(s.mostLikelyHomeScore)")
                            .font(.caption)
                    }
                }.padding(.vertical, 4)
            }.navigationTitle("Simulation Center")
        }
    }
}

struct AccuracyView: View {
    let grades: [GradedPrediction]
    var body: some View {
        NavigationStack {
            if grades.isEmpty {
                ContentUnavailableView("Awaiting completed games", systemImage: "chart.bar", description: Text("Saved forecasts will be graded when final scores arrive."))
            } else {
                let summary = Backtester.summarize(grades)!
                List {
                    LabeledContent("Games graded", value: summary.games.formatted())
                    LabeledContent("Winner accuracy", value: summary.winnerAccuracy.formatted(.percent.precision(.fractionLength(0))))
                    LabeledContent("Mean score error", value: summary.meanAbsoluteScoreError.formatted(.number.precision(.fractionLength(1))))
                    LabeledContent("Brier score", value: summary.meanBrierScore.formatted(.number.precision(.fractionLength(3))))
                    LabeledContent("Balanced score", value: summary.balancedAccuracy.formatted(.percent.precision(.fractionLength(0))))
                }.navigationTitle("Accuracy")
            }
        }
    }
}

struct SettingsView: View {
    let storageLabel: String
    let lastUpdated: Date?
    var body: some View {
        NavigationStack {
            Form {
                Section("Model") { LabeledContent("Version", value: "MVP 0.2"); LabeledContent("Objective", value: "50% winner · 50% score"); LabeledContent("Runs per matchup", value: "10,000") }
                Section("Persistence") {
                    LabeledContent("Storage", value: storageLabel)
                    if let lastUpdated { LabeledContent("Forecast generated", value: lastUpdated.formatted(date: .abbreviated, time: .shortened)) }
                    Text("GitHub Actions runs the scheduled forecast; CloudKit synchronizes the published results.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Model Control")
        }
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
        game("AZ", "Arizona Cardinals", at: "LAR", "Los Angeles Rams", kickoff: "2026-10-18T16:05:00-04:00"),
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
