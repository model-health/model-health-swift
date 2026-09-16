import Foundation
import ModelHealthFFI

// MARK: - Internal Codable Types for FFI Deserialization

/// Decodes the externally-tagged serde JSON for `ImportStatus`.
/// Unit variants serialize as plain strings; struct variants as `{"variant": {...}}`.
internal enum CodableImportStatus: Decodable {
    case creatingSession
    case createdSession(sessionId: String)
    case uploadingVideo(trial: String, uploaded: Int, total: Int)
    case processing

    private enum VariantKeys: String, CodingKey {
        case createdSession = "created_session"
        case uploadingVideo = "uploading_video"
    }

    private struct CreatedSessionPayload: Decodable {
        let sessionId: String

        private enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
        }
    }

    private struct UploadingPayload: Decodable {
        let trial: String
        let uploaded: Int
        let total: Int
    }

    init(from decoder: Decoder) throws {
        // Try single-value (unit variants serialized as plain strings)
        if let single = try? decoder.singleValueContainer(),
           let string = try? single.decode(String.self)
        {
            switch string {
            case "creating_session":
                self = .creatingSession
                return

            case "processing":
                self = .processing
                return

            default:
                break
            }
        }

        // Try keyed container (struct variant: {"created_session": {...}} or {"uploading_video": {...}})
        let container = try decoder.container(keyedBy: VariantKeys.self)
        if container.contains(.createdSession) {
            let payload = try container.decode(CreatedSessionPayload.self, forKey: .createdSession)
            self = .createdSession(sessionId: payload.sessionId)
            return
        }
        if container.contains(.uploadingVideo) {
            let payload = try container.decode(UploadingPayload.self, forKey: .uploadingVideo)
            self = .uploadingVideo(trial: payload.trial, uploaded: payload.uploaded, total: payload.total)
            return
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown ImportStatus variant"))
    }

    func toPublic() -> ImportStatus {
        switch self {
        case .creatingSession:
            return .creatingSession

        case .createdSession(let sessionId):
            return .createdSession(sessionId: sessionId)

        case .uploadingVideo(let trial, let uploaded, let total):
            return .uploadingVideo(trial: trial, uploaded: uploaded, total: total)

        case .processing:
            return .processing
        }
    }
}

internal enum CodableCalibrationStatus: Codable {
    case recording
    case uploading(uploaded: Int, total: Int)
    case processing(percent: Int?)
    case done

    enum CodingKeys: String, CodingKey {
        case type
        case uploaded
        case total
        case percent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "recording":
            self = .recording

        case "uploading":
            let uploaded = try container.decode(Int.self, forKey: .uploaded)
            let total = try container.decode(Int.self, forKey: .total)
            self = .uploading(uploaded: uploaded, total: total)

        case "processing":
            let percent = try? container.decode(Int.self, forKey: .percent)
            self = .processing(percent: percent)

        case "done":
            self = .done

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown calibration status"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .recording:
            try container.encode("recording", forKey: .type)

        case .uploading(let uploaded, let total):
            try container.encode("uploading", forKey: .type)
            try container.encode(uploaded, forKey: .uploaded)
            try container.encode(total, forKey: .total)

        case .processing(let percent):
            try container.encode("processing", forKey: .type)
            if let percent = percent {
                try container.encode(percent, forKey: .percent)
            }

        case .done:
            try container.encode("done", forKey: .type)
        }
    }

    func toPublic() -> CalibrationStatus {
        switch self {
        case .recording:
            return .recording

        case .uploading(let uploaded, let total):
            return .uploading(uploaded: uploaded, total: total)

        case .processing(let percent):
            return .processing(percent: percent)

        case .done:
            return .done
        }
    }
}

// MARK: - Metrics Conversions

extension Metric {
    internal static func from(cValue: CMetric) throws -> Metric {
        let name = cValue.name.map { String(cString: $0) } ?? ""

        let reading: MetricValue
        switch cValue.reading_type {
        case 0:
            reading = .scalar(cValue.has_value ? cValue.value : nil)

        case 1:
            reading = .bilateral(
                left: cValue.has_value_left ? cValue.value_left : nil,
                right: cValue.has_value_right ? cValue.value_right : nil
            )

        default:
            throw FFIConversionError.invalidData("Unknown MetricValue type \(cValue.reading_type)")
        }

        return Metric(
            name: name,
            description: cValue.description.map { String(cString: $0) },
            value: reading
        )
    }
}

extension MetricsGroup {
    internal static func from(cGroup: CMetricsGroup) throws -> MetricsGroup {
        let name = cGroup.name.map { String(cString: $0) } ?? ""

        var metrics: [Metric] = []
        if cGroup.metrics.count > 0, let itemsPtr = cGroup.metrics.items {
            metrics = try (0..<Int(cGroup.metrics.count)).map { index in
                try Metric.from(cValue: itemsPtr[index])
            }
        }

        return MetricsGroup(
            name: name,
            description: cGroup.description.map { String(cString: $0) },
            metrics: metrics
        )
    }
}

extension ActivityMetrics {
    internal static func from(cMetrics: CActivityMetrics) throws -> ActivityMetrics {
        guard let activityIdPtr = cMetrics.activity_id else {
            throw FFIConversionError.nullPointer("ActivityMetrics activity_id is null")
        }

        var groups: [MetricsGroup] = []
        if cMetrics.groups.count > 0, let itemsPtr = cMetrics.groups.items {
            groups = try (0..<Int(cMetrics.groups.count)).map { index in
                try MetricsGroup.from(cGroup: itemsPtr[index])
            }
        }

        return ActivityMetrics(
            activityId: String(cString: activityIdPtr),
            activityTypeId: Int(cMetrics.activity_type_id),
            groups: groups
        )
    }
}
