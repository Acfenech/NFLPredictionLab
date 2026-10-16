import Foundation

public protocol PredictionRepository: Sendable {
    func load() async throws -> [Prediction]
    func save(_ predictions: [Prediction]) async throws
}

public actor LocalPredictionRepository: PredictionRepository {
    private let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> [Prediction] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Prediction].self, from: Data(contentsOf: url))
    }

    public func save(_ predictions: [Prediction]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(predictions).write(to: url, options: .atomic)
    }
}

/// CloudKit-ready seam. Add the iCloud entitlement and container, then implement this
/// repository with CKRecord operations without changing the forecasting engine or UI.
public enum PersistenceMode: String, CaseIterable, Sendable {
    case local = "On this device"
    case cloudKit = "CloudKit (setup required)"
}
