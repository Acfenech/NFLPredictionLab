# NFL Prediction Lab MVP

A private SwiftUI prototype with a shared Swift forecasting engine. Open `NFLPredictionLab.xcodeproj` in Xcode and run the `NFLPredictionLab` scheme on **My Mac** or a connected iPhone.

The app and cloud worker use nflverse's automatically updated schedule/results release and convert pregame win percentage into a centered baseline rating. ESPN remains a fallback for the cloud worker. If both sources fail, the app visibly falls back to cached or neutral forecasts. The engine runs 10,000 Monte Carlo trials per matchup and the grading metric weights winner correctness and score accuracy equally.

## Apple app target

The repository-owned Xcode project contains one multiplatform target for macOS, iPhone, and iPad. Its bundle identifier is `com.acfenech.NFLPredictionLab`, its development team is configured, and its CloudKit-ready entitlements name `iCloud.com.acfenech.NFLPredictionLab`. The container still needs to be created or selected in Signing & Capabilities before CloudKit persistence is enabled.

## Persistence and automation

`PredictionRepository` isolates storage. The signed Apple app uses `CloudKitPredictionRepository` to read and write the latest encoded forecast bundle in the public CloudKit database, while non-CloudKit builds retain local JSON persistence.

CloudKit stores and synchronizes records; it does not run unattended scheduled forecasts. GitHub Actions performs the scheduled computation and publishes the app-compatible forecast bundle when the `CLOUDKIT_KEY_ID` and `CLOUDKIT_PRIVATE_KEY` repository secrets are configured.

## Scheduled cloud worker

`.github/workflows/forecast.yml` runs tests and the `CloudForecastWorker` at 8 AM America/Detroit on Tuesday, Thursday, Saturday, and Sunday, with manual runs supported. Forecast JSON is retained as a private GitHub Actions artifact for 90 days. CloudKit publishing remains disabled until its container and server-to-server secrets are configured.
