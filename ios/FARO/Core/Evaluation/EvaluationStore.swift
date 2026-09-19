import Foundation

enum EvaluationStoreError:
    Error,
    Equatable,
    LocalizedError,
    AppMessageProviding
{
    case directoryUnavailable
    case readFailed
    case unsupportedSchema
    case writeFailed
    case exportFailed

    var appMessage: AppMessage {
        switch self {
        case .directoryUnavailable:
            AppMessage(.errorEvaluationDirectory)
        case .readFailed, .unsupportedSchema:
            AppMessage(.errorEvaluationRead)
        case .writeFailed:
            AppMessage(.errorEvaluationWrite)
        case .exportFailed:
            AppMessage(.errorEvaluationExport)
        }
    }

    var errorDescription: String? {
        appMessage.localized(in: .englishUS)
    }
}

actor EvaluationStore {
    private let directoryURL: URL?
    private let exportDirectoryURL: URL
    private let fileManager: FileManager
    private var cachedDataset: EvaluationDataset?

    init(
        directoryURL: URL? = nil,
        exportDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            self.directoryURL = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first?.appendingPathComponent(
                "FARO/Evaluation",
                isDirectory: true
            )
        }
        self.exportDirectoryURL = exportDirectoryURL
            ?? fileManager.temporaryDirectory.appendingPathComponent(
                "FARO-Evaluation-Exports",
                isDirectory: true
            )
        self.fileManager = fileManager
    }

    func load() throws -> EvaluationDataset {
        if let cachedDataset {
            return cachedDataset
        }
        guard let recordsURL else {
            throw EvaluationStoreError.directoryUnavailable
        }
        guard fileManager.fileExists(atPath: recordsURL.path) else {
            cachedDataset = .empty
            return .empty
        }

        do {
            let data = try Data(contentsOf: recordsURL)
            let dataset = try Self.decoder.decode(
                EvaluationDataset.self,
                from: data
            )
            guard dataset.schemaVersion
                    == EvaluationDataset.currentSchemaVersion else {
                throw EvaluationStoreError.unsupportedSchema
            }
            cachedDataset = dataset
            return dataset
        } catch let error as EvaluationStoreError {
            throw error
        } catch {
            throw EvaluationStoreError.readFailed
        }
    }

    func append(
        _ trial: RecognitionEvaluationTrial
    ) throws -> EvaluationDataset {
        var dataset = try load()
        dataset.recognitionTrials.append(trial)
        try write(dataset)
        return dataset
    }

    func append(
        _ observation: FieldEvaluationObservation
    ) throws -> EvaluationDataset {
        var dataset = try load()
        dataset.fieldObservations.append(observation)
        try write(dataset)
        return dataset
    }

    func clear() throws -> EvaluationDataset {
        guard let recordsURL else {
            throw EvaluationStoreError.directoryUnavailable
        }
        do {
            for url in [recordsURL, reportURL]
                where fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            cachedDataset = .empty
            return .empty
        } catch {
            throw EvaluationStoreError.writeFailed
        }
    }

    func export(
        generatedAt: Date = .now
    ) throws -> URL {
        let dataset = try load()
        let report = EvaluationExport(
            dataset: dataset,
            generatedAt: generatedAt
        )
        do {
            try fileManager.createDirectory(
                at: exportDirectoryURL,
                withIntermediateDirectories: true
            )
            try Self.encoder.encode(report).write(
                to: reportURL,
                options: .atomic
            )
            return reportURL
        } catch {
            throw EvaluationStoreError.exportFailed
        }
    }

    private var recordsURL: URL? {
        directoryURL?.appendingPathComponent("evaluation.json")
    }

    private var reportURL: URL {
        exportDirectoryURL.appendingPathComponent(
            "FARO-evaluation-report.json"
        )
    }

    private func write(_ dataset: EvaluationDataset) throws {
        guard let directoryURL,
              let recordsURL else {
            throw EvaluationStoreError.directoryUnavailable
        }
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try Self.encoder.encode(dataset).write(
                to: recordsURL,
                options: .atomic
            )
            cachedDataset = dataset
        } catch {
            throw EvaluationStoreError.writeFailed
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
