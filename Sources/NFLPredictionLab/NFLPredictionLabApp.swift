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
            AccuracyView(grades: model.gradedPredictions, archiveCount: model.archiveCount).tabItem { Label("Accuracy", systemImage: "chart.line.uptrend.xyaxis") }.tag(2)
            HistoryView(bundles: model.archiveBundles).tabItem { Label("History", systemImage: "clock.arrow.circlepath") }.tag(3)
            SettingsView(model: model).tabItem { Label("Model", systemImage: "slider.horizontal.3") }.tag(4)
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
    let archiveCount: Int
    var body: some View {
        NavigationStack {
            if grades.isEmpty {
                ContentUnavailableView("Awaiting completed games", systemImage: "chart.bar", description: Text("\(archiveCount) archived forecast snapshots are ready to grade when final scores arrive."))
            } else {
                let summary = Backtester.summarize(grades)!
                List {
                    Section("Performance") {
                        LabeledContent("Forecasts graded", value: summary.games.formatted())
                        LabeledContent("Winner accuracy", value: summary.winnerAccuracy.formatted(.percent.precision(.fractionLength(0))))
                        LabeledContent("Mean score error", value: summary.meanAbsoluteScoreError.formatted(.number.precision(.fractionLength(1))))
                        LabeledContent("Brier score", value: summary.meanBrierScore.formatted(.number.precision(.fractionLength(3))))
                        LabeledContent("Balanced score", value: summary.balancedAccuracy.formatted(.percent.precision(.fractionLength(0))))
                    }
                    Section("Calibration") {
                        ForEach(Backtester.calibration(grades)) { bucket in
                            LabeledContent("\(bucket.lowerBound.formatted(.percent.precision(.fractionLength(0))))–\(bucket.upperBound.formatted(.percent.precision(.fractionLength(0)))) · \(bucket.games) games",
                                           value: "Observed \(bucket.observedRate.formatted(.percent.precision(.fractionLength(0))))")
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
    private var teams: [String] {
        Set(model.predictions.flatMap { [$0.matchup.away.abbreviation, $0.matchup.home.abbreviation] }).sorted()
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    LabeledContent("Version", value: "MVP 0.3")
                    LabeledContent("Objective", value: "50% winner · 50% score")
                    LabeledContent("Runs per matchup", value: "10,000")
                    Text("Ratings use recency-weighted scoring, defense, and opponent strength. Quarterback and injury adjustments can be added without changing the forecasting engine.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Persistence") {
                    LabeledContent("Storage", value: model.storageLabel)
                    if let lastUpdated = model.lastUpdated {
                        LabeledContent("Forecast generated", value: lastUpdated.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Freshness", value: Date.now.timeIntervalSince(lastUpdated) < 21_600 ? "Current" : "Refresh recommended")
                    }
                    Text("GitHub Actions runs the scheduled forecast; CloudKit synchronizes the published results.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("QB / injury adjustments") {
                    Text("Adjust a team's offense from −10 to +10 points, then refresh forecasts. Use negative values for an unavailable quarterback or major offensive injuries.").font(.footnote).foregroundStyle(.secondary)
                    ForEach(teams, id: \.self) { team in
                        Stepper(value: Binding(get: { model.adjustment(for: team) }, set: { model.setAdjustment($0, for: team) }), in: -10...10, step: 0.5) {
                            LabeledContent(team, value: model.adjustment(for: team).formatted(.number.sign(strategy: .always()).precision(.fractionLength(1))))
                        }
                    }
                    Button("Recalculate with adjustments") { Task { await model.refresh() } }
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
