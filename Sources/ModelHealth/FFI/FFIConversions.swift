import Foundation
import ModelHealthFFI

// MARK: - Internal FFI to Model Conversions

enum FFIConversionError: Error {
    case nullPointer(String)
    case invalidData(String)
}

private let ffiDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

/// Drops any `.NNNNNN` fractional-seconds component so the date parser never has to deal
/// with fractional seconds — e.g. `"2024-01-15T10:30:00.123456Z"` -> `"2024-01-15T10:30:00Z"`.
private func stripFractionalSeconds(_ dateString: String) -> String {
    guard let dotIndex = dateString.firstIndex(of: ".") else {
        return dateString
    }

    var suffixStart = dateString.index(after: dotIndex)
    while suffixStart < dateString.endIndex, dateString[suffixStart].isNumber {
        suffixStart = dateString.index(after: suffixStart)
    }

    return String(dateString[..<dotIndex]) + String(dateString[suffixStart...])
}

/// Parses a non-null, always-present FFI timestamp string (ISO-8601, second precision).
private func parseFFIDate(_ cString: UnsafePointer<CChar>?, fieldName: String) throws -> Date {
    guard let cString else {
        throw FFIConversionError.nullPointer("\(fieldName) is null")
    }

    let raw = stripFractionalSeconds(String(cString: cString))
    guard let date = ffiDateFormatter.date(from: raw) else {
        throw FFIConversionError.invalidData("\(fieldName) is not a valid ISO-8601 date")
    }

    return date
}

/// Parses an FFI timestamp string that may legitimately be absent. `nil` for a null
/// pointer; throws if a non-null pointer holds a malformed date, same as
/// `parseFFIDate`.
private func parseOptionalFFIDate(_ cString: UnsafePointer<CChar>?, fieldName: String) throws -> Date? {
    guard let cString else {
        return nil
    }
    return try parseFFIDate(cString, fieldName: fieldName)
}

/// Decodes an FFI JSON-encoded string array, e.g. `["cmj","baseline"]`. Empty for a
/// null pointer or malformed JSON — mirrors how `Activity.tags` is decoded.
private func parseFFIStringArray(_ cString: UnsafePointer<CChar>?) -> [String] {
    guard let cString else {
        return []
    }
    let json = String(cString: cString)
    return (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
}

extension Session {
    internal static func from(cSession: CSession) throws -> Session {
        guard let id = cSession.id else {
            throw FFIConversionError.nullPointer("Session ID is null")
        }

        guard let name = cSession.name else {
            throw FFIConversionError.nullPointer("Session name is null")
        }

        guard let sessionName = cSession.session_name else {
            throw FFIConversionError.nullPointer("Session sessionName is null")
        }

        return Session(
            id: String(cString: id),
            user: Int(cSession.user),
            public: cSession.is_public,
            name: String(cString: name),
            sessionName: String(cString: sessionName),
            qrcode: cSession.qrcode.map { String(cString: $0) },
            activities: [],
            subject: cSession.subject == -1 ? nil : Int(cSession.subject),
            activitiesCount: Int(cSession.trials_count),
            createdAt: try parseFFIDate(cSession.created_at, fieldName: "Session createdAt"),
            updatedAt: try parseFFIDate(cSession.updated_at, fieldName: "Session updatedAt")
        )
    }
}

extension AccountInfo {
    internal static func from(cAccountInfo: CAccountInfo) throws -> AccountInfo {
        guard let username = cAccountInfo.username else {
            throw FFIConversionError.nullPointer("AccountInfo username is null")
        }

        guard let email = cAccountInfo.email else {
            throw FFIConversionError.nullPointer("AccountInfo email is null")
        }

        guard let firstName = cAccountInfo.first_name else {
            throw FFIConversionError.nullPointer("AccountInfo firstName is null")
        }

        guard let lastName = cAccountInfo.last_name else {
            throw FFIConversionError.nullPointer("AccountInfo lastName is null")
        }

        return AccountInfo(
            username: String(cString: username),
            email: String(cString: email),
            firstName: String(cString: firstName),
            lastName: String(cString: lastName),
            institution: cAccountInfo.institution.map { String(cString: $0) },
            profession: cAccountInfo.profession.map { String(cString: $0) },
            country: cAccountInfo.country.map { String(cString: $0) }
        )
    }
}

extension Subject {
    internal static func from(cSubject: CSubject) throws -> Subject {
        guard let name = cSubject.name else {
            throw FFIConversionError.nullPointer("Subject name is null")
        }

        guard let characteristics = cSubject.characteristics else {
            throw FFIConversionError.nullPointer("Subject characteristics is null")
        }

        return Subject(
            id: Int(cSubject.id),
            name: String(cString: name),
            weight: cSubject.weight == 0.0 ? nil : cSubject.weight,
            height: cSubject.height == 0.0 ? nil : cSubject.height,
            age: cSubject.age == -1 ? nil : Int(cSubject.age),
            birthYear: cSubject.birth_year == 0 ? nil : Int(cSubject.birth_year),
            gender: optionalGenderFromI32(cSubject.gender),
            sexAtBirth: optionalSexFromI32(cSubject.sex_at_birth),
            characteristics: String(cString: characteristics),
            firstName: cSubject.first_name.map { String(cString: $0) },
            lastName: cSubject.last_name.map { String(cString: $0) },
            tags: parseFFIStringArray(cSubject.tags),
            activityCount: cSubject.activity_count == -1 ? nil : Int(cSubject.activity_count),
            lastActivity: try parseOptionalFFIDate(cSubject.last_activity, fieldName: "Subject lastActivity"),
            createdAt: try parseOptionalFFIDate(cSubject.created_at, fieldName: "Subject createdAt"),
            updatedAt: try parseOptionalFFIDate(cSubject.updated_at, fieldName: "Subject updatedAt")
        )
    }
}

extension Video {
    internal static func from(cVideo: CVideo) throws -> Video {
        guard let id = cVideo.id else {
            throw FFIConversionError.nullPointer("Video ID is null")
        }

        guard let trial = cVideo.trial else {
            throw FFIConversionError.nullPointer("Video trial is null")
        }

        return Video(
            id: String(cString: id),
            activity: String(cString: trial),
            video: cVideo.video.map { String(cString: $0) },
            videoThumb: cVideo.video_thumb.map { String(cString: $0) }
        )
    }
}

extension Activity.Result {
    internal static func from(cResult: CTrialResult) throws -> Activity.Result {
        guard let trial = cResult.trial else {
            throw FFIConversionError.nullPointer("Trial result trial is null")
        }

        return Activity.Result(
            id: Int(cResult.id),
            activity: String(cString: trial),
            tag: cResult.tag.map { String(cString: $0) },
            media: cResult.media.map { String(cString: $0) }
        )
    }
}

extension Activity {
    internal static func from(cTrial: CTrial) throws -> Activity {
        guard let id = cTrial.id else {
            throw FFIConversionError.nullPointer("Trial ID is null")
        }

        guard let session = cTrial.session else {
            throw FFIConversionError.nullPointer("Trial session is null")
        }

        guard let status = cTrial.status else {
            throw FFIConversionError.nullPointer("Trial status is null")
        }

        var videos: [Video] = []
        if cTrial.videos.count > 0, let videosPtr = cTrial.videos.videos {
            videos = try (0..<Int(cTrial.videos.count)).map { index in
                try Video.from(cVideo: videosPtr[index])
            }
        }

        var results: [Activity.Result] = []
        if cTrial.results.count > 0, let resultsPtr = cTrial.results.results {
            results = try (0..<Int(cTrial.results.count)).map { index in
                try Activity.Result.from(cResult: resultsPtr[index])
            }
        }

        let tags = parseFFIStringArray(cTrial.tags)

        let activityType: ActivityTypeInfo?
        if cTrial.activity_type_id == -1 {
            activityType = nil
        } else {
            activityType = ActivityTypeInfo(
                id: Int(cTrial.activity_type_id),
                name: cTrial.activity_type_name.map { String(cString: $0) } ?? "",
                displayName: cTrial.activity_type_display_name.map { String(cString: $0) } ?? ""
            )
        }

        return Activity(
            id: String(cString: id),
            session: String(cString: session),
            name: cTrial.name.map { String(cString: $0) },
            status: String(cString: status),
            videos: videos,
            results: results,
            activityType: activityType,
            tags: tags,
            notes: cTrial.notes.map { String(cString: $0) },
            createdBy: cTrial.created_by.map { String(cString: $0) },
            analysisStatus: cTrial.analysis_status.map { String(cString: $0) },
            trashed: cTrial.trashed,
            createdAt: try parseFFIDate(cTrial.created_at, fieldName: "Activity createdAt"),
            updatedAt: try parseFFIDate(cTrial.updated_at, fieldName: "Activity updatedAt")
        )
    }
}

extension ActivityTag {
    internal static func from(cTag: CActivityTag) throws -> ActivityTag {
        guard let value = cTag.value else {
            throw FFIConversionError.nullPointer("ActivityTag value is null")
        }

        guard let label = cTag.label else {
            throw FFIConversionError.nullPointer("ActivityTag label is null")
        }

        return ActivityTag(
            value: String(cString: value),
            label: String(cString: label)
        )
    }
}

extension Analysis {
    internal static func from(cTask: CAnalysis) throws -> Analysis {
        guard let taskId = cTask.task_id else {
            throw FFIConversionError.nullPointer("Analysis task ID is null")
        }

        return Analysis(id: String(cString: taskId))
    }
}

extension ActivityStatus {
    internal static func from(
        statusCode: Int32,
        uploaded: Int32,
        total: Int32,
        analysisTask: CAnalysis
    ) -> ActivityStatus {
        switch statusCode {
        case 0:
            return .uploading(uploaded: Int(uploaded), total: Int(total))

        case 1:
            return .processing

        case 2:
            return .ready

        case 3:
            return .failed

        case 4:
            if let task = try? Analysis.from(cTask: analysisTask) {
                return .analyzing(task)
            }
            return .failed

        default:
            return .failed
        }
    }
}

extension AnalysisStatus {
    internal static func from(statusCode: Int32) throws -> AnalysisStatus {
        switch statusCode {
        case 0:
            return .processing

        case 1:
            return .completed

        case 2:
            return .failed

        default:
            throw FFIConversionError.invalidData("Unknown analysis status code: \(statusCode)")
        }
    }
}

extension Archive {
    internal static func from(cArchive: CArchive) throws -> Archive {
        guard let archiveId = cArchive.archive_id else {
            throw FFIConversionError.nullPointer("Archive ID is null")
        }

        return Archive(id: String(cString: archiveId))
    }
}

extension ArchiveStatus {
    internal static func from(statusCode: Int32) throws -> ArchiveStatus {
        switch statusCode {
        case 0:
            return .processing

        case 1:
            return .ready

        case 2:
            return .failed

        default:
            throw FFIConversionError.invalidData("Unknown archive status code: \(statusCode)")
        }
    }
}

extension ImportStatus {
    internal static func from(jsonString: String) throws -> ImportStatus {
        guard let data = jsonString.data(using: .utf8) else {
            throw FFIConversionError.invalidData("Failed to convert JSON string to data")
        }

        do {
            let codable = try JSONDecoder().decode(CodableImportStatus.self, from: data)
            return codable.toPublic()
        } catch {
            throw FFIConversionError.invalidData("Failed to decode ImportStatus: \(error)")
        }
    }
}

extension CalibrationStatus {
    internal static func from(jsonString: String) throws -> CalibrationStatus {
        guard let data = jsonString.data(using: .utf8) else {
            throw FFIConversionError.invalidData("Failed to convert JSON string to data")
        }

        do {
            let codable = try JSONDecoder().decode(CodableCalibrationStatus.self, from: data)
            return codable.toPublic()
        } catch {
            throw FFIConversionError.invalidData("Failed to decode CalibrationStatus: \(error)")
        }
    }
}

extension LogEvent {
    internal static func from(jsonString: String) throws -> LogEvent {
        guard let data = jsonString.data(using: .utf8) else {
            throw FFIConversionError.invalidData("Failed to convert JSON string to data")
        }

        do {
            return try JSONDecoder().decode(LogEvent.self, from: data)
        } catch {
            throw FFIConversionError.invalidData("Failed to decode LogEvent: \(error)")
        }
    }
}

// MARK: - Helper Functions

private func genderFromI32(_ value: Int32) -> Subject.Gender {
    switch value {
    case 0:
        .man

    case 1:
        .woman

    case 2:
        .transgender

    case 3:
        .nonBinary

    case 4:
        .noResponse

    default:
        .noResponse
    }
}

private func sexFromI32(_ value: Int32) -> Subject.Sex {
    switch value {
    case 0:
        .man

    case 1:
        .woman

    case 2:
        .intersex

    case 3:
        .notListed

    case 4:
        .noResponse

    default:
        .noResponse
    }
}

/// Like `genderFromI32`, but -1 (not reported / not recognized) stays `nil` instead
/// of collapsing into `.noResponse`.
private func optionalGenderFromI32(_ value: Int32) -> Subject.Gender? {
    value == -1 ? nil : genderFromI32(value)
}

/// See `optionalGenderFromI32`.
private func optionalSexFromI32(_ value: Int32) -> Subject.Sex? {
    value == -1 ? nil : sexFromI32(value)
}

extension Subject.Gender {
    var cValue: Int32 {
        switch self {
        case .man:
            return 0

        case .woman:
            return 1

        case .transgender:
            return 2

        case .nonBinary:
            return 3

        case .noResponse:
            return 4
        }
    }
}

extension Subject.Sex {
    var cValue: Int32 {
        switch self {
        case .man:
            return 0

        case .woman:
            return 1

        case .intersex:
            return 2

        case .notListed:
            return 3

        case .noResponse:
            return 4
        }
    }
}

extension CheckerboardPlacement {
    var cValue: Int32 {
        switch self {
        case .perpendicular:
            return 0

        case .parallel:
            return 1
        }
    }
}

extension LogLevel {
    var cValue: Int32 {
        switch self {
        case .off:
            return 0

        case .error:
            return 1

        case .warn:
            return 2

        case .info:
            return 3
        }
    }
}

extension ActivityType {
    var cValue: Int32 {
        switch self {
        case .counterMovementJump:
            return 0

        case .gait:
            return 1

        case .treadmillRunning:
            return 2

        case .sitToStand:
            return 3

        case .squats:
            return 4

        case .rangeOfMotion:
            return 5

        case .overgroundRunning:
            return 6

        case .dropJump:
            return 7

        case .hop:
            return 8

        case .treadmillGait:
            return 9

        case .changeOfDirection:
            return 10

        case .cut:
            return 11

        case .sprint:
            return 12

        case .lateralStepdown:
            return 13

        case .lunge:
            return 14
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    init?(cValue: Int32) {
        switch cValue {
        case 0:
            self = .counterMovementJump

        case 1:
            self = .gait

        case 2:
            self = .treadmillRunning

        case 3:
            self = .sitToStand

        case 4:
            self = .squats

        case 5:
            self = .rangeOfMotion

        case 6:
            self = .overgroundRunning

        case 7:
            self = .dropJump

        case 8:
            self = .hop

        case 9:
            self = .treadmillGait

        case 10:
            self = .changeOfDirection

        case 11:
            self = .cut

        case 12:
            self = .sprint

        case 13:
            self = .lateralStepdown

        case 14:
            self = .lunge

        default:
            return nil
        }
    }
}

extension VideoUploadMode {
    var cValue: Int32 {
        switch self {
        case .enabled:
            return 0

        case .disabled:
            return 1

        case .flush:
            return 2
        }
    }

    init?(cValue: Int32) {
        switch cValue {
        case 0:
            self = .enabled

        case 1:
            self = .disabled

        case 2:
            self = .flush

        default:
            return nil
        }
    }
}

extension MotionDataType {
    var cValue: Int32 {
        switch self {
        case .animation:
            return 0

        case .kinematics(.mot):
            return 1

        case .kinematics(.csv):
            return 2

        case .markers(.trc):
            return 3

        case .markers(.csv):
            return 4

        case .model:
            return 5

        case .tagged:
            return -1
        }
    }

    init?(cValue: Int32) {
        switch cValue {
        case 0:
            self = .animation

        case 1:
            self = .kinematics(.mot)

        case 2:
            self = .kinematics(.csv)

        case 3:
            self = .markers(.trc)

        case 4:
            self = .markers(.csv)

        case 5:
            self = .model

        default:
            return nil
        }
    }
}

extension AnalysisDataType {
    var cValue: Int32 {
        switch self {
        case .metrics:
            return 0

        case .data:
            return 1

        case .report:
            return 2
        }
    }

    init?(cValue: Int32) {
        switch cValue {
        case 0:
            self = .metrics

        case 1:
            self = .data

        case 2:
            self = .report

        default:
            return nil
        }
    }
}

extension SessionFramerate {
    var cValue: Int32 {
        switch self {
        case .fps60:
            return 0

        case .fps120:
            return 1

        case .fps240:
            return 2
        }
    }
}

extension SessionOpenSimModel {
    var cValue: Int32 {
        switch self {
        case .laiUhlrich2022Shoulder:
            return 0

        case .laiUhlrich2022:
            return 1
        }
    }
}

extension SessionScalingSetup {
    var cValue: Int32 {
        switch self {
        case .uprightStandingPose:
            return 0

        case .anyPose:
            return 1
        }
    }
}

extension SessionCoreEngine {
    var cValue: Int32 {
        switch self {
        case .v0_2:
            return 0

        case .v0_3:
            return 1

        case .v1_0:
            return 2
        }
    }
}

extension FilterFrequency {
    var cValue: Int32 {
        switch self {
        case .default:
            return -1

        case .hz(let value):
            return Int32(value)
        }
    }
}

extension SessionDataSharing {
    var cValue: Int32 {
        switch self {
        case .shareProcessedDataAndIdentifiedVideos:
            return 0

        case .shareProcessedDataAndDeidentifiedVideos:
            return 1

        case .shareProcessedData:
            return 2

        case .shareNoData:
            return 3
        }
    }
}

extension SubjectGroup {
    internal static func from(cSubjectGroup: CSubjectGroup) throws -> SubjectGroup {
        guard let name = cSubjectGroup.name else {
            throw FFIConversionError.nullPointer("SubjectGroup name is null")
        }

        guard let description = cSubjectGroup.description else {
            throw FFIConversionError.nullPointer("SubjectGroup description is null")
        }

        return SubjectGroup(
            id: Int(cSubjectGroup.id),
            name: String(cString: name),
            description: String(cString: description),
            subjectCount: Int(cSubjectGroup.subject_count),
            totalActivities: Int(cSubjectGroup.total_activities),
            lastActivity: try parseOptionalFFIDate(
                cSubjectGroup.last_activity, fieldName: "SubjectGroup lastActivity"
            ),
            createdBy: cSubjectGroup.created_by.map { String(cString: $0) },
            isOwner: cSubjectGroup.is_owner,
            canEdit: cSubjectGroup.can_edit,
            createdAt: try parseFFIDate(cSubjectGroup.created_at, fieldName: "SubjectGroup createdAt"),
            updatedAt: try parseFFIDate(cSubjectGroup.updated_at, fieldName: "SubjectGroup updatedAt"),
            trashed: cSubjectGroup.trashed,
            trashedAt: try parseOptionalFFIDate(
                cSubjectGroup.trashed_at, fieldName: "SubjectGroup trashedAt"
            )
        )
    }
}
