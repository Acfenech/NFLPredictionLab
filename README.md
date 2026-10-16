# NFL Prediction Lab MVP

A private SwiftUI prototype with a shared Swift forecasting engine. Open `Package.swift` in Xcode and run the `NFLPredictionLab` scheme on **My Mac**.

The Week 6 matchup schedule is sourced from NFL.com. At launch, the app requests current team records from ESPN's public scoreboard endpoint and converts win percentage into a centered baseline rating. If the request fails, it visibly falls back to neutral ratings. This is useful for an MVP, but it is not a documented or licensed production API; replace `TeamStatsFeed` with a licensed provider before distribution. The engine runs 10,000 Monte Carlo trials per matchup and the grading metric weights winner correctness and score accuracy equally.

## iPhone target

The shared `PredictionCore` library and SwiftUI views are iOS-compatible. The package provides the immediately runnable Mac MVP; create an iOS App target in Xcode and include the same app/view sources when an Apple development team and bundle identifier are selected.

## Persistence and automation

`PredictionRepository` isolates storage. The MVP includes JSON persistence and a CloudKit-ready mode. CloudKit must not be enabled until an iCloud container and signed entitlements are configured.

CloudKit stores and synchronizes records; it does not run unattended scheduled forecasts. A later scheduled compute worker—such as GitHub Actions or a small serverless job—should fetch data, run the model, and write signed results to CloudKit through an authenticated service boundary. No cloud deployment is currently configured.
