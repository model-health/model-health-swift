import Foundation

extension Activity {
    /// This activity as the JSON core reads it, for the calls that act on the record as it
    /// is held rather than reading it again.
    ///
    /// Carries what results are read from: the processing state and the result links. The
    /// videos are left out, as no call that takes this needs them.
    func coreJSON() -> String {
        let timestamps = ISO8601DateFormatter()
        timestamps.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var record: [String: Any] = [
            "id": id,
            "session_id": sessionId,
            "status": status,
            "videos": [Any](),
            "results": results.map { result -> [String: Any] in
                [
                    "id": result.id,
                    "activity": result.activity,
                    "tag": result.tag ?? NSNull(),
                    "media": result.media ?? NSNull()
                ]
            },
            "tags": tags,
            "trashed": trashed,
            "created_at": timestamps.string(from: createdAt),
            "updated_at": timestamps.string(from: updatedAt)
        ]
        record["name"] = name
        record["notes"] = notes
        record["created_by"] = createdBy
        record["analysis_status"] = analysisStatus
        if let type = activityType {
            record["activity_type"] = [
                "id": type.id,
                "name": type.name,
                "display_name": type.displayName,
                "slug": type.slug
            ]
        }

        let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
