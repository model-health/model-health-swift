import Foundation
import ModelHealthFFI

// MARK: - Artifact Results

extension ArtifactType {
    var cValue: Int32 {
        switch self {
        case .metrics:
            return 0

        case .report:
            return 1

        case .data:
            return 2

        case .kinematicsCsv:
            return 3
        }
    }

    init?(cValue: Int32) {
        switch cValue {
        case 0:
            self = .metrics

        case 1:
            self = .report

        case 2:
            self = .data

        case 3:
            self = .kinematicsCsv

        default:
            return nil
        }
    }
}

extension Activity {
    /// Whether processing has finished, so results can be downloaded.
    ///
    /// Also true for an activity that finished without analysis output: its motion data is
    /// there, but a report or metrics may not be.
    public var hasResults: Bool {
        status.withCString { model_health_activity_has_results($0) }
    }
}

extension FetchedArtifacts {
    /// Reads what `model_health_fetch_artifacts` produced. Does not free it.
    internal init(cOutcomes array: CArtifactOutcomeArray) {
        var data: [ArtifactType: Data] = [:]
        var errors: [ArtifactType: ModelHealthError] = [:]
        for (artifact, outcome) in artifactOutcomes(in: array) {
            if outcome.success {
                data[artifact] = outcome.data.data.map { Data(bytes: $0, count: Int(outcome.data.length)) } ?? Data()
            } else {
                errors[artifact] = artifactError(from: outcome)
            }
        }
        self.init(data: data, errors: errors)
    }
}

extension DownloadedArtifacts {
    /// Reads what `model_health_download_activity` produced. Does not free it.
    internal init(cOutcomes array: CArtifactOutcomeArray) {
        var paths: [ArtifactType: URL] = [:]
        var errors: [ArtifactType: ModelHealthError] = [:]
        for (artifact, outcome) in artifactOutcomes(in: array) {
            if outcome.success, let path = outcome.path {
                paths[artifact] = URL(fileURLWithPath: String(cString: path))
            } else {
                errors[artifact] = artifactError(from: outcome)
            }
        }
        self.init(paths: paths, errors: errors)
    }
}

/// The outcomes in `array` that name an artifact this SDK knows.
private func artifactOutcomes(in array: CArtifactOutcomeArray) -> [(ArtifactType, CArtifactOutcome)] {
    guard let items = array.items else {
        return []
    }
    return (0..<Int(array.count)).compactMap { index in
        ArtifactType(cValue: items[index].artifact).map { ($0, items[index]) }
    }
}

private func artifactError(from outcome: CArtifactOutcome) -> ModelHealthError {
    ModelHealthError.from(
        code: outcome.error_code,
        subCode: outcome.error_sub_code,
        statusCode: outcome.error_status_code,
        message: outcome.error_message.map { String(cString: $0) } ?? "Unknown error"
    )
}
