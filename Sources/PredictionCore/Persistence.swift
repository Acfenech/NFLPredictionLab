import Foundation
#if canImport(CloudKit)
import CloudKit
#endif

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

#if canImport(CloudKit)
/// Stores the latest forecast bundle in the container's public database so the
/// signed app and the scheduled publisher can read the same records.
public actor CloudKitPredictionRepository: PredictionRepository {
    public static let recordType = "ForecastBundle"
    public static let latestRecordName = "latest"

    private let database: CKDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(containerIdentifier: String? = nil) {
        let container = containerIdentifier.map(CKContainer.init(identifier:)) ?? CKContainer.default()
        database = container.publicCloudDatabase
    }

    public func load() async throws -> [Prediction] {
        let id = CKRecord.ID(recordName: Self.latestRecordName)
        do {
            let record = try await database.record(for: id)
            guard let payload = record["payload"] as? Data else {
                throw StatsFeedError.missingFields("CloudKit ForecastBundle.payload")
            }
            return try decoder.decode([Prediction].self, from: payload)
        } catch let error as CKError where error.code == .unknownItem {
            return []
        }
    }

    public func save(_ predictions: [Prediction]) async throws {
        let id = CKRecord.ID(recordName: Self.latestRecordName)
        let record: CKRecord
        do {
            record = try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.recordType, recordID: id)
        }
        record["payload"] = try encoder.encode(predictions) as CKRecordValue
        record["generatedAt"] = Date() as CKRecordValue
        record["predictionCount"] = predictions.count as CKRecordValue
        _ = try await database.save(record)
    }
}
#endif

/// CloudKit-ready seam. Add the iCloud entitlement and container, then implement this
/// repository with CKRecord operations without changing the forecasting engine or UI.
public enum PersistenceMode: String, CaseIterable, Sendable {
    case local = "On this device"
    case cloudKit = "CloudKit (setup required)"
}
