# NFL Prediction Lab MVP

A private SwiftUI prototype with a shared Swift forecasting engine. Open `NFLPredictionLab.xcodeproj` in Xcode and run the `NFLPredictionLab` scheme on **My Mac** or a connected iPhone.

The app and cloud worker use nflverse's automatically updated schedule/results release. Team strength combines recency-weighted scoring, defense, and opponent quality, with optional quarterback/injury adjustments. ESPN remains a fallback for the cloud worker. If both sources fail, the app visibly falls back to cached or neutral forecasts. The engine runs 10,000 Monte Carlo trials per matchup and the grading metric weights winner correctness and score accuracy equally.

## Apple app target

The repository-owned Xcode project contains one multiplatform target for macOS, iPhone, and iPad. Its bundle identifier is `com.acfenech.NFLPredictionLab`, its development team is configured, and CloudKit persistence uses `iCloud.com.acfenech.NFLPredictionLab` in the development environment.

## Persistence and automation

`PredictionRepository` isolates storage. The signed Apple app uses `CloudKitPredictionRepository` to read and write the latest encoded forecast bundle in the public CloudKit database, while non-CloudKit builds retain local JSON persistence.

The History screen reads immutable CloudKit forecast snapshots. Once games are final, the Accuracy screen grades archived forecasts, reports winner and score performance, and compares predicted confidence with observed results.

CloudKit stores and synchronizes records; it does not run unattended scheduled forecasts. GitHub Actions performs the scheduled computation and publishes the app-compatible forecast bundle when the `CLOUDKIT_KEY_ID` and `CLOUDKIT_PRIVATE_KEY` repository secrets are configured.

## Scheduled cloud worker

`.github/workflows/forecast.yml` runs tests and the `CloudForecastWorker` at 8 AM America/Detroit on Tuesday, Thursday, Saturday, and Sunday, with manual runs supported. Forecast JSON is retained as a private GitHub Actions artifact for 90 days. Each successful run replaces the `latest` CloudKit bundle and creates a timestamped history snapshot for future backtesting.

Optional unattended quarterback/injury adjustments can be supplied as a GitHub Actions variable named `TEAM_ADJUSTMENTS_JSON`, for example `{"DET":-3.5,"KC":1.0}`. Device-only adjustments can be edited in Model Control and do not change the cloud schedule.
