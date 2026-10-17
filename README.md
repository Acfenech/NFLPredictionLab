# NFL Prediction Lab MVP

The betting screen calculates implied probability, potential profit, and total return from editable American odds for every single and parlay. nflverse remains the no-key spread/total and baseline moneyline source. When the optional `THE_ODDS_API_KEY` environment variable is present, the scheduled worker overlays the median available US-book NFL moneyline and preserves it through CloudKit sync. The key belongs in the GitHub Actions secret named `THE_ODDS_API_KEY`; it must not be committed to the repository. Exact sportsbook odds should still be entered before placing a wager.

A private SwiftUI prototype with a shared Swift forecasting engine. Open `NFLPredictionLab.xcodeproj` in Xcode and run the `NFLPredictionLab` scheme on **My Mac** or a connected iPhone.

## MVP 1.3 historical learning

MVP 1.3 expands training to five completed seasons and replaces in-sample configuration selection with nested walk-forward validation. Candidate home-field, team-rating, recent-form, market-blend, and variance settings are scored only on later seasons, with recent folds weighted more heavily. The newest completed season remains an honest outer holdout for the reported accuracy; after that evaluation is captured, the production configuration and probability calibration are refit on all completed historical games. The selection objective retains the required equal weighting of winner correctness and score accuracy.

Betting validation uses the complete walk-forward grade set rather than only the newest held-out season. Each included season was predicted using earlier seasons only, and the newest season appears exactly once. Spreads and totals require at least 30 strong-edge samples and a 54% win rate. Because moneyline prices have different break-even rates, they require at least 100 samples and a 3% price-adjusted historical return on one-unit stakes.

## MVP 1.2 parlay planning

MVP 1.2 adds three automatically composed parlay plans: a two-leg lower-variance plan, a three-leg balanced plan, and a four-leg high-upside plan. Legs come from different games, respond to the return preference, support manually entered stakes, and require every included market to pass validation before receiving a nonzero recommended stake.

## MVP 1.1 bankroll planning

MVP 1.1 adds a locally saved bankroll and weekly wager plan, per-market user-entered stake amounts, remaining-budget warnings, and a separate validation-gated recommended allocation. Risk and return-preference sliders change allocation concentration and market weighting; they never bypass the historical validation gate.

The allocation controls include **Reset to Recommended**, which restores the balanced 35% risk and 40% return-preference defaults without changing bankroll, weekly budget, wagers, or sportsbook odds.

An explicit **Show Unvalidated Recommendations** toggle reveals a separately labeled speculative plan and speculative parlay amounts. It is off by default. Every affected selection remains marked Unvalidated, and the historical gate itself is never weakened or bypassed silently.

Every suggested single bet and parlay also shows the potential profit and total amount returned if it wins, calculated from the suggested stake and the current entered or consensus American odds. The weekly-plan and parlay summary totals aggregate stake, anticipated profit, and total returned across their respective recommendations.

The Betting screen also shows a probability-weighted likely result for each recommendation and for both summary totals. Expected net accounts for winning and losing outcomes; expected returned is the average amount expected back, including stake, over many comparable wagers. These are model estimates rather than guarantees.

## MVP 1.0 professional interface

MVP 1.0 introduces an adaptive sidebar, weekly intelligence dashboard, visual matchup cards, a scoreboard-style detail view, probability bars, calibration charts, streamlined betting filters with visible evidence counts, searchable model controls, polished loading states, and a reusable visual design system across macOS and iPhone.

## MVP 0.9 in-app guidance

MVP 0.9 adds a complete in-app User Guide explaining source provenance, forecast and confidence interpretation, simulations, accuracy metrics, betting labels and validation, refresh/history behavior, manual adjustments, and important limitations.

## MVP 0.8 betting analysis

MVP 0.8 adds spread, moneyline, and total recommendations with Strong edge, Lean, and Pass classifications. Recommendations require minimum model-versus-market edges, explain their rationale, and are graded historically in the Accuracy screen. Price-aware validation is applied before the UI can label a wager actionable; otherwise candidate edges are visibly marked Not validated and Pass. They are analytical estimates, not guarantees or financial advice.

The app and cloud worker use nflverse's automatically updated schedule/results release. Team strength combines recency-weighted scoring, defense, and opponent quality, with optional quarterback/injury adjustments. ESPN remains a fallback for the cloud worker. If both sources fail, the app visibly falls back to cached or neutral forecasts. The engine runs 10,000 Monte Carlo trials per matchup and the grading metric weights winner correctness and score accuracy equally.

## MVP 0.7 free live context

MVP 0.7 adds the no-subscription nflverse injury, depth-chart and team-metric pipeline, Open-Meteo kickoff weather, local stadium travel calculations, and visible source-coverage counts.

## MVP 0.6 market-aware forecasts

MVP 0.6 retains a visible model-only baseline, then blends separate margin and total estimates with consensus market inputs. It also adds probability recalibration, opening/current/closing line fields, line-movement summaries, rolling-season validation, uncertainty ranges, and automatic review flags when a projection differs materially from the market.

Optional `GAME_CONTEXT_FEED_URL` data is keyed by `Matchup.gameKey` and can supply weather, travel distance, travel adjustment, and confirmed quarterback context. If it is not configured, forecasting continues safely and reports that no material context adjustment was available. The same variable can be configured in Xcode and GitHub Actions alongside `AVAILABILITY_FEED_URL` and `ADVANCED_METRICS_FEED_URL`.

## Free data pipeline

The default pipeline requires no subscription or API key. It downloads current nflverse injury reports, depth charts, and weekly team summaries; derives conservative EPA, success, explosiveness, pressure, and turnover-regression features; requests kickoff weather from Open-Meteo; and calculates travel from bundled stadium coordinates. Licensed provider URLs remain optional overrides. Every external source fails independently, so a delayed file never blocks the weekly schedule or baseline forecast.

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
