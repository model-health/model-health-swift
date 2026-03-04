import Foundation

// MARK: - Session

/// A parent container for a movement capture workflow.
/// Sessions link related entities such as activities and subjects, and provide the context used by subsequent operations.
///
/// Create a session with ``ModelHealthService/createSession()`` before performing subsequent operations like camera calibration.
///
/// When connecting or re-connecting to a Session, use the ``qrcode`` URL to retrieve the QR code image for pairing cameras.
///
/// ```swift
/// let session = try await service.createSession()
/// try await service.calibrateCamera(session, checkerboardDetails: details)
/// ```
public struct Session: Identifiable, Sendable {
    public let id: String
    public let user: Int
    public let `public`: Bool
    public let name: String
    public let sessionName: String
    public let qrcode: String?
    public let activities: [Activity]
    public let subject: Int?
    public let activitiesCount: Int
}

extension Session: Equatable {
    public static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
}

extension Session: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Subject

/// An individual being monitored or assessed.
public struct Subject: Identifiable, Sendable {
    public enum Gender: CaseIterable, Sendable {
        case woman
        case man
        case transgender
        case nonBinary
        case noResponse
    }

    public enum Sex: CaseIterable, Sendable {
        case woman
        case man
        case intersex
        case notListed
        case noResponse
    }

    public let id: Int
    public let name: String

    /// Weight in kilograms.
    public let weight: Double?

    /// Height in centimeters.
    public let height: Double?

    /// Age in years.
    public let age: Int?

    /// Year of birth.
    public let birthYear: Int?

    public let gender: Gender

    public let sexAtBirth: Sex

    /// Freeform text describing relevant characteristics or medical conditions.
    public let characteristics: String
}

extension Subject: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Parameters for creating a new subject.
///
/// `name`, `weight` and `height` are required.
/// All other fields are optional and default to `.noResponse` or empty/nil values.
///
/// ```swift
/// let params = SubjectParameters(
///     name: "John Smith",
///     weight: 75.0,
///     height: 180.0
/// )
///
/// let subject = try await service.createSubject(parameters: params)
/// ```
public struct SubjectParameters: Sendable {
    public let name: String

    /// Weight in kilograms.
    public let weight: Double

    /// Height in centimeters.
    public let height: Double

    /// Year of birth.
    public let birthYear: Int?

    public let sexAtBirth: Subject.Sex
    public let gender: Subject.Gender

    /// Freeform text describing relevant characteristics or medical conditions.
    public let characteristics: String

    public init(
        name: String,
        weight: Double,
        height: Double,
        birthYear: Int? = nil,
        sexAtBirth: Subject.Sex? = nil,
        gender: Subject.Gender? = nil,
        characteristics: String = ""
    ) {
        self.name = name
        self.weight = weight
        self.height = height
        self.birthYear = birthYear
        self.sexAtBirth = sexAtBirth ?? .noResponse
        self.gender = gender ?? .noResponse
        self.characteristics = characteristics
    }
}

// MARK: - Video

/// A recorded video file from an activity.
///
/// Videos are automatically uploaded to the cloud during recording.
/// Use `video` as the URL for the full video.
public struct Video: Sendable {
    public let id: String
    public let activity: String
    public let video: String?
    public let videoThumb: String?
}

/// The processing version of the video to retrieve from an activity.
public enum VideoVersion: Sendable {
    /// The original, unprocessed video as captured or uploaded.
    ///
    /// Raw videos represent the source material before any synchronization has been applied.
    case raw

    /// Videos that have been synchronized.
    ///
    /// Synced videos have undergone processing and may include temporal alignment
    /// or other transformations applied during analysis.
    case synced
}

// MARK: - Activity Management

/// A movement recording trial with associated videos and results.
///
/// Activities represent individual recording trials and contain references to
/// captured videos and results.
///
/// ```swift
/// let activities = try await service.activityList(for: session)
/// for activity in activities {
///     print("\(activity.name ?? activity.id): \(activity.status)")
/// }
/// ```
public struct Activity: Sendable {
    /// A processed result file associated with an activity.
    public struct Result: Sendable {
        public let id: Int
        public let activity: String
        public let tag: String?
        public let media: String?
    }

    /// The processing status of an activity on the server.
    public enum Status: Sendable {
        case done
        case error
        case stopped
        case processing
    }

    public let id: String
    public let session: String
    public let name: String?
    public let status: String
    public let videos: [Video]
    public let results: [Result]
}

/// Sort order for activity lists.
///
/// ```swift
/// let activities = try await service.activities(
///     forSubject: subjectId,
///     startIndex: 0,
///     count: 20,
///     sortedBy: .updatedAt
/// )
/// ```
public enum ActivitySort: Sendable {
    /// Sort by most recently updated.
    case updatedAt
}

/// A tag that can be applied to activities for categorization.
///
/// Use tags to organize and filter activities by type or condition
/// (e.g., `"cmj"`, `"squat"`, `"baseline"`).
///
/// ```swift
/// let tags = try await service.activityTags()
/// let cmjTag = tags.first { $0.value == "cmj" }
/// print("CMJ activities: \(cmjTag?.label ?? "")")
/// ```
public struct ActivityTag: Sendable {
    /// The API value used to identify the tag.
    public let value: String
    /// The human-readable display label.
    public let label: String
}

/// The type of motion result data to retrieve from a processed activity, including the desired file format.
///
/// ```swift
/// // Download animation data (JSON only)
/// let animationData = await service.motionData(ofType: [.animation], for: activity)
///
/// // Download kinematics in MOT format
/// let motData = await service.motionData(ofType: [.kinematics(.mot)], for: activity)
///
/// // Download kinematics in both MOT and CSV formats
/// let bothFormats = await service.motionData(ofType: [.kinematics(.mot), .kinematics(.csv)], for: activity)
/// ```
public enum MotionDataType: Hashable, Sendable {
    /// Animation data for visualizing movement analysis results. Always JSON format.
    case animation

    /// Kinematic data including joint angles and positions.
    ///
    /// (**Only available in dynamic activities**)
    case kinematics(KinematicsFormat)

    /// Marker trajectory data.
    case markers(MarkersFormat)

    /// OpenSim model. Always OSIM format.
    ///
    /// (**Only available in neutral activities**)
    case model

    /// Available file formats for kinematics result data.
    public enum KinematicsFormat: Sendable {
        /// OpenSim motion (.mot) format.
        case mot
        /// Comma-separated values (.csv) format.
        case csv
    }

    /// Available file formats for markers result data.
    public enum MarkersFormat: Sendable {
        /// TRC marker trajectory (.trc) format.
        case trc
        /// Comma-separated values (.csv) format.
        case csv
    }
}

@available(*, deprecated, renamed: "MotionDataType")
public enum ResultDataType: Hashable, Sendable {
    case animation
}

/// Motion data downloaded from a processed activity.
///
/// Each instance carries the ``type`` that was requested, which also
/// implies the file format. Use ``type`` to determine how to parse ``data``.
///
/// ```swift
/// let results = await service.motionData(ofType: [.kinematics(.mot)], for: activity)
///
/// for result in results {
///     // result.type identifies both the type and implicit file format
///     // Use result.data directly as a .mot file
/// }
/// ```
public struct MotionData: Sendable {
    /// The type of result data and its file format. Use this to determine how to parse the raw data.
    public let type: MotionDataType

    /// The raw file data. Parse according to the format implied by ``type``.
    public let data: Data
}

@available(*, deprecated, renamed: "MotionData")
public struct ResultData: Sendable {
    public let resultDataType: ResultDataType
    public let data: Data
}

// MARK: - Analysis Result Data

/// The type of analysis result data to download from an activity with a completed analysis.
///
/// ```swift
/// let results = await service.analysisData(ofType: [.metrics, .report], for: activity)
/// ```
public enum AnalysisDataType: Hashable, Sendable {
    /// Computed biomechanical metrics. Always JSON format.
    case metrics
    /// Extended analysis data. Always ZIP format.
    case data
    /// Analysis report. Always PDF format.
    case report
}

@available(*, deprecated, renamed: "AnalysisDataType")
public enum AnalysisResultDataType: Hashable, Sendable {
    case metrics
}

/// Analysis result data downloaded from an activity with a completed analysis.
///
/// Use ``type`` to determine how to parse ``data``.
///
/// ```swift
/// let results = await service.analysisData(ofType: [.metrics, .report, .data], for: activity)
///
/// for result in results {
///     switch result.type {
///     case .metrics:
///         // Decode result.data as JSON
///     case .report:
///         // Use result.data directly as a PDF
///     case .data:
///         // Use result.data directly as a ZIP file
///     }
/// }
/// ```
public struct AnalysisData: Sendable {
    /// The type of analysis result. Use this to determine how to parse ``data``.
    public let type: AnalysisDataType

    /// The raw file data. Parse according to the format implied by ``type``.
    public let data: Data
}

@available(*, deprecated, renamed: "AnalysisData")
public struct AnalysisResultData: Sendable {
    public let resultDataType: AnalysisResultDataType
    public let data: Data
}

// MARK: - Checkerboard Placement

/// Orientation of the calibration checkerboard relative to the camera.
///
/// ```swift
/// let details = CheckerboardDetails(
///     rows: 4, columns: 5, squareSize: 35, placement: .perpendicular
/// )
/// ```
public enum CheckerboardPlacement: String, CaseIterable, Identifiable, Sendable {
    /// Checkerboard upright (vertical), so its plane is perpendicular to the ground.
    case perpendicular

    /// Checkerboard flat on the floor, so its plane is parallel to the ground.
    case parallel
}

extension CheckerboardPlacement {
    public var id: String {
        self.rawValue
    }
}

// MARK: - Checkerboard Details

/// Configuration for a calibration checkerboard pattern.
///
/// > Note: Row and column counts refer to internal corners, not squares.
/// > For a standard 5×6 checkerboard, use `rows: 4, columns: 5`.
/// > Square size must be measured precisely in millimeters for accurate calibration.
///
/// ```swift
/// let details = CheckerboardDetails(
///     rows: 4,
///     columns: 5,
///     squareSize: 35,
///     placement: .perpendicular
/// )
/// try await service.calibrateCamera(session, checkerboardDetails: details)
/// ```
public struct CheckerboardDetails: Sendable {
    /// Number of internal corner rows. For a 5×6 checkerboard, use `4`.
    public let rows: Int

    /// Number of internal corner columns. For a 5×6 checkerboard, use `5`.
    public let columns: Int

    /// Size of each square in millimeters. Must be measured precisely.
    public let squareSize: Int

    /// Checkerboard orientation relative to the ground.
    public let placement: CheckerboardPlacement

    public init(rows: Int, columns: Int, squareSize: Int, placement: CheckerboardPlacement) {
        self.rows = rows
        self.columns = columns
        self.squareSize = squareSize
        self.placement = placement
    }
}

/// The current status of a calibration process.
///
/// Reported during both camera calibration and subject calibration,
/// tracking the recording, uploading and processing stages.
///
/// ```swift
/// try await service.calibrateSubject(
///     subject,
///     in: session
/// ) { status in
///     switch status {
///     case .recording:
///         print("Recording...")
///     case .uploading(let uploaded, let total):
///         print("Uploading: \(uploaded)/\(total)")
///     case .processing(let percent):
///         print("Processing: \(percent ?? 0)%")
///     case .done:
///         print("Complete!")
///     }
/// }
/// ```
public enum CalibrationStatus: Sendable {
    /// All connected cameras are actively recording.
    case recording

    /// Videos are being uploaded from cameras.
    ///
    /// - Parameters:
    ///   - uploaded: The number of videos successfully uploaded so far.
    ///   - total: The total number of videos expected from all cameras.
    case uploading(uploaded: Int, total: Int)

    /// The server is processing the uploaded videos.
    ///
    /// - Parameter percent: The processing completion percentage (0-100), or `nil` if
    ///   processing has not yet started or progress is unavailable.
    case processing(percent: Int?)

    /// Calibration has completed successfully.
    case done
}

/// Available analysis types for motion capture activities.
///
/// Analysis can only be performed on activities that have reached `.ready` status.
public enum AnalysisType: String, CaseIterable, Sendable {
    /// Counter Movement Jump.
    case counterMovementJump = "Counter Movement Jump"

    /// Overground Walking.
    case gait = "Overground Walking"

    /// Treadmill Running.
    case treadmillRunning = "Treadmill Running"

    /// Sit-to-Stand Transfer.
    case sitToStand = "Sit-to-Stand Transfer"

    /// Squat Exercise.
    case squats = "Squats"

    /// Range of Motion (ROM).
    case rangeOfMotion = "Range of Motion"

    /// Overground Running.
    case overgroundRunning = "Overground Running"

    /// Drop Vertical Jump.
    case dropJump = "Drop Vertical Jump"

    /// Hop Test.
    case hop = "Hop Test"

    /// Treadmill Walking.
    case treadmillGait = "Treadmill Walking"

    /// 5-0-5 Test.
    case changeOfDirection = "5-0-5 Test"

    /// Cutting Maneuver.
    case cut = "Cutting Maneuver"
}

/// The current processing state of an activity.
///
/// Activities must reach `.ready` before analysis can begin.
public enum ActivityStatus: Sendable {
    /// Videos are being uploaded. `uploaded` and `total` track progress.
    case uploading(uploaded: Int, total: Int)
    /// Videos have been uploaded and are being processed.
    case processing
    /// Processing is complete. The activity is ready for analysis.
    case ready
    /// Processing failed.
    case failed
}

@available(*, deprecated, renamed: "ActivityStatus")
public enum ActivityProcessingStatus: Sendable {
    case failed
}

/// An active analysis returned by ``ModelHealthService/startAnalysis(_:for:in:)``.
///
/// Pass to ``ModelHealthService/analysisStatus(for:)`` to poll for completion.
public struct Analysis: Sendable, Identifiable {
    public let id: String
}

@available(*, deprecated, renamed: "Analysis")
public struct AnalysisTask: Sendable {
    public let taskId: String
}

/// The current state of an analysis.
public enum AnalysisStatus: Sendable {
    /// Analysis is in progress.
    case processing
    /// Analysis completed successfully.
    case completed
    /// Analysis failed.
    case failed
}

@available(*, deprecated, renamed: "AnalysisStatus")
public enum AnalysisTaskStatus: Sendable {
    case failed
}

// MARK: - SwiftUI #Preview support

extension Session {
    public static func forPreview(
        customizing: (inout PreviewBuilder) -> Void = { _ in }
    ) -> Self {
        var builder = PreviewBuilder()
        customizing(&builder)
        return builder.build()
    }

    public struct PreviewBuilder {
        public var id = "preview-session"
        public var user = 1
        public var `public` = false
        public var name = "Preview Session"
        public var sessionName = "Session Name"
        public var qrcode: String? = "https://example.com/qr.png"
        public var activities: [Activity] = []
        public var subject: Int? = nil
        public var activitiesCount = 0

        func build() -> Session {
            Session(
                id: id,
                user: user,
                public: `public`,
                name: name,
                sessionName: sessionName,
                qrcode: qrcode,
                activities: activities,
                subject: subject,
                activitiesCount: activitiesCount
            )
        }
    }
}

extension Subject {
    public static func forPreview(
        customizing: (inout PreviewBuilder) -> Void = { _ in }
    ) -> Self {
        var builder = PreviewBuilder()
        customizing(&builder)
        return builder.build()
    }

    public struct PreviewBuilder {
        public var id = 42
        public var name = "Subject: THX 1138"
        public var weight: Double? = 70.0
        public var height: Double? = 180.0
        public var age: Int? = 42
        public var birthYear: Int? = 1983
        public var gender: Subject.Gender = .man
        public var sexAtBirth: Subject.Sex = .man
        public var characteristics = ""

        func build() -> Subject {
            Subject(
                id: id,
                name: name,
                weight: weight,
                height: height,
                age: age,
                birthYear: birthYear,
                gender: gender,
                sexAtBirth: sexAtBirth,
                characteristics: characteristics
            )
        }
    }
}

extension Video {
    public static func forPreview(
        customizing: (inout PreviewBuilder) -> Void = { _ in }
    ) -> Self {
        var builder = PreviewBuilder()
        customizing(&builder)
        return builder.build()
    }

    public struct PreviewBuilder {
        public var id = "preview-video"
        public var activity = "preview-activity"
        public var video: String? = "video-id"
        public var videoUrl: String? = "https://example.com/video.mp4"
        public var videoThumb: String? = "https://example.com/thumb.jpg"

        func build() -> Video {
            Video(
                id: id,
                activity: activity,
                video: video,
                videoThumb: videoThumb
            )
        }
    }
}

extension Activity {
    public static func forPreview(
        customizing: (inout PreviewBuilder) -> Void = { _ in }
    ) -> Self {
        var builder = PreviewBuilder()
        customizing(&builder)
        return builder.build()
    }

    public struct PreviewBuilder {
        public var id = "preview-activity"
        public var session = "preview-session"
        public var name: String? = "Preview Trial"
        public var status: String = "done"
        public var videos: [Video] = []
        public var results: [Activity.Result] = []

        func build() -> Activity {
            Activity(
                id: id,
                session: session,
                name: name,
                status: status,
                videos: videos,
                results: results
            )
        }
    }
}

extension Activity: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Activity, rhs: Activity) -> Bool {
        lhs.id == rhs.id
    }
}

extension Activity.Result {
    public static func forPreview(
        customizing: (inout PreviewBuilder) -> Void = { _ in }
    ) -> Self {
        var builder = PreviewBuilder()
        customizing(&builder)
        return builder.build()
    }

    public struct PreviewBuilder {
        public var id = 1
        public var activity = "preview-activity"
        public var tag: String? = "analysis-result"
        public var media = "https://example.com/result.csv"

        func build() -> Activity.Result {
            Activity.Result(
                id: id,
                activity: activity,
                tag: tag,
                media: media
            )
        }
    }
}

extension ActivityTag {
    public static func forPreview(
        customizing: (inout PreviewBuilder) -> Void = { _ in }
    ) -> Self {
        var builder = PreviewBuilder()
        customizing(&builder)
        return builder.build()
    }

    public struct PreviewBuilder {
        public var value = "cmj"
        public var label = "Countermovement Jump"

        func build() -> ActivityTag {
            ActivityTag(
                value: value,
                label: label
            )
        }
    }
}

extension MotionData {
    public static func forPreview(
        resultDataType: MotionDataType,
        customizing: (inout PreviewBuilder) -> Void = { _ in }
    ) -> Self {
        var builder = PreviewBuilder(type: resultDataType)
        customizing(&builder)
        return builder.build()
    }

    public struct PreviewBuilder {
        public let type: MotionDataType
        public let data: Data = Data("time,position,velocity\n0.0,0.0,0.0\n1.0,1.0,1.0".utf8)

        func build() -> MotionData {
            MotionData(type: type, data: data)
        }
    }
}

extension Analysis {
    public static func forPreview(
        customizing: (inout PreviewBuilder) -> Void = { _ in }
    ) -> Self {
        var builder = PreviewBuilder()
        customizing(&builder)
        return builder.build()
    }

    public struct PreviewBuilder {
        public var taskId = "preview-analysis-task"

        func build() -> Analysis {
            Analysis(id: taskId)
        }
    }
}

extension AnalysisData {
    public static func forPreview(
        customizing: (inout PreviewBuilder) -> Void = { _ in }
    ) -> Self {
        var builder = PreviewBuilder()
        customizing(&builder)
        return builder.build()
    }

    public struct PreviewBuilder {
        public let resultDataType: AnalysisDataType = .metrics
        public let data: Data = Data(
            """
            {
                "00_jump_height_COM": {
                    "label": "Jump height (cm)",
                    "bilateral": false,
                    "value": 33.2,
                    "info": "Jump height is the vertical distance between the center of mass in a standing position and its highest point during the jump.",
                    "decimalPlaces": 1
                },
                "01_jump_time": {
                    "label": "Jump time (s)",
                    "bilateral": false,
                    "value": 0.73,
                    "info": "Jump time is the time between the start of the downward phase and toe-off.",
                    "decimalPlaces": 2
                },
                "06_peak_hip_extension_speed_during_takeoff": {
                    "label": "Peak hip extension speed during takeoff (deg/s)",
                    "bilateral": true,
                    "value": {
                        "left": 233.0,
                        "right": 259.0
                    },
                    "info": "Peak hip extension speed during takeoff refers to the maximum angular velocity during vertical jump takeoff.",
                    "decimalPlaces": 0
                }
            }
            """.utf8
        )

        func build() -> AnalysisData {
            AnalysisData(
                type: resultDataType,
                data: data
            )
        }
    }
}
