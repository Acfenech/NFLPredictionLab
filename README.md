# NFL Prediction Lab MVP

A private SwiftUI prototype with a shared Swift forecasting engine. Open `NFLPredictionLab.xcodeproj` in Xcode and run the `NFLPredictionLab` scheme on **My Mac** or a connected iPhone.

The app and cloud worker use nflverse's automatically updated schedule/results release. Team strength combines recency-weighted scoring, defense, and opponent quality, with optional quarterback/injury adjustments. ESPN remains a fallback for the cloud worker. If both sources fail, the app visibly falls back to cached or neutral forecasts. The engine runs 10,000 Monte Carlo trials per matchup and the grading metric weights winner correctness and score accuracy equally.

## MVP 0.4 validation and explanations

The model now also includes recent scoring-margin form, rest differential, home field, and provider-neutral player availability. Every forecast carries a factor-by-factor explanation and a plain-language confidence justification.

Weights are selected using earlier completed seasons and evaluated on the latest held-out season. The Accuracy screen reports winner accuracy, score error, Brier score, balanced score, and calibration without leaking validation results back into training.

For automated QB and injury updates, set the optional GitHub Actions variable `AVAILABILITY_FEED_URL` to a licensed or private JSON endpoint:

```json
{
  "BUF": { "adjustment": -4.5, "note": "Starting quarterback unavailable" }
}
```

If the endpoint is absent or unavailable, forecasting safely continues with `TEAM_ADJUSTMENTS_JSON` and the app's manual controls.

For play-by-play inputs, `ADVANCED_METRICS_FEED_URL` accepts one object per team with
`offensiveEPA`, `defensiveEPA`, `successRate`, `explosivePlayRate`, `pressureRate`, and
`turnoverRegression`. This provider-neutral adapter lets the private app use nflverse-derived or
licensed metrics without embedding credentials in the application. Schedule-derived ratings remain
the safe fallback.

## MVP 0.5 calibration and market comparison

MVP 0.5 fits a monotonic probability calibration curve on training seasons and evaluates the
calibrated model on the held-out season. Matchup-specific scoring volatility replaces the prior
single fixed variance.

When nflverse publishes consensus fields, the app compares its projected margin and total with
`spread_line`, `total_line`, `home_moneyline`, and `away_moneyline`. Historical validation compares
model winner accuracy with both the home-team baseline and the market favorite. Missing future lines
are labeled clearly and never block a forecast. Market information is contextual analysis, not betting
advice.

Each recalculation also retains the prior probability and score projection so the matchup view can
explain forecast movement between data refreshes.

## Apple app target

The repository-owned Xcode project contains one multiplatform target for macOS, iPhone, and iPad. Its bundle identifier is `com.acfenech.NFLPredictionLab`, its development team is configured, and CloudKit persistence uses `iCloud.com.acfenech.NFLPredictionLab` in the development environment.

## Persistence and automation

`PredictionRepository` isolates storage. The signed Apple app uses `CloudKitPredictionRepository` to read and write the latest encoded forecast bundle in the public CloudKit database, while non-CloudKit builds retain local JSON persistence.

The History screen reads immutable CloudKit forecast snapshots. Once games are final, the Accuracy screen grades archived forecasts, reports winner and score performance, and compares predicted confidence with observed results.

CloudKit stores and synchronizes records; it does not run unattended scheduled forecasts. GitHub Actions performs the scheduled computation and publishes the app-compatible forecast bundle when the `CLOUDKIT_KEY_ID` and `CLOUDKIT_PRIVATE_KEY` repository secrets are configured.

## Scheduled cloud worker

`.github/workflows/forecast.yml` runs tests and the `CloudForecastWorker` at 8 AM America/Detroit on Tuesday, Thursday, Saturday, and Sunday, with manual runs supported. Forecast JSON is retained as a private GitHub Actions artifact for 90 days. Each successful run replaces the `latest` CloudKit bundle and creates a timestamped history snapshot for future backtesting.

Optional unattended quarterback/injury adjustments can be supplied as a GitHub Actions variable named `TEAM_ADJUSTMENTS_JSON`, for example `{"DET":-3.5,"KC":1.0}`. Device-only adjustments can be edited in Model Control and do not change the cloud schedule.
