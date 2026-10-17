// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NFLPredictionLab",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "PredictionCore", targets: ["PredictionCore"]),
        .executable(name: "NFLPredictionLab", targets: ["NFLPredictionLab"]),
        .executable(name: "CloudForecastWorker", targets: ["CloudForecastWorker"])
    ],
    targets: [
        .target(name: "PredictionCore"),
        .executableTarget(
            name: "NFLPredictionLab",
            dependencies: ["PredictionCore"],
            resources: [.copy("Assets.xcassets")]
        ),
        .executableTarget(name: "CloudForecastWorker", dependencies: ["PredictionCore"]),
        .testTarget(name: "PredictionCoreTests", dependencies: ["PredictionCore"])
    ]
)
