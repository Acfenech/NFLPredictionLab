# NFL Prediction Lab MVP

A private SwiftUI prototype with a shared Swift forecasting engine. Open `Package.swift` in Xcode and run the `NFLPredictionLab` scheme on **My Mac**.

The app and cloud worker use nflverse's automatically updated schedule/results release and convert pregame win percentage into a centered baseline rating. ESPN remains a fallback for the cloud worker. If both sources fail, the app visibly falls back to cached or neutral forecasts. The engine runs 10,000 Monte Carlo trials per matchup and the grading metric weights winner correctness and score accuracy equally.

## iPhone target

The shared `PredictionCore` library and SwiftUI views are iOS-compatible. The package provides the immediately runnable Mac MVP; create an iOS App target in Xcode and include the same app/view sources when an Apple development team and bundle identifier are selected.

## Persistence and automation

`PredictionRepository` isolates storage. The MVP includes local JSON persistence and a `CloudKitPredictionRepository` that stores the latest encoded forecast bundle in the public CloudKit database. CloudKit must not be enabled until an iCloud container, a signed app target, and entitlements are configured.

CloudKit stores and synchronizes records; it does not run unattended scheduled forecasts. GitHub Actions now performs the scheduled computation. Publishing its JSON output to CloudKit remains disabled until the container identifier and server-to-server credentials are configured.

## Scheduled cloud worker

`.github/workflows/forecast.yml` runs tests and the `CloudForecastWorker` at 8 AM America/Detroit on Tuesday, Thursday, Saturday, and Sunday, with manual runs supported. Forecast JSON is retained as a private GitHub Actions artifact for 90 days. CloudKit publishing remains disabled until its container and server-to-server secrets are configured.
