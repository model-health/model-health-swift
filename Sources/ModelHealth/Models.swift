import Foundation

// MARK: - Session

/// Create with ``ModelHealthService/createSession()`` before performing camera calibration.
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
    /// Support for SwiftUI ForEach and List
    public static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
}

extension Session: Hashable {
    /// Support for SwiftUI ForEach and List
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Subject

/// An individual being monitored or assessed in the ModelHealth system.
///
/// ```swift
/// let subjects = try await service.subjectList()
/// let filtered = subjects.filter { $0.subjectTags.contains("high-risk") }
/// ```
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

    /// Weight in kilograms
    public let weight: Double?

    /// Height in centimeters
    public let height: Double?

    /// Age in years
    public let age: Int?

    /// Year of birth
    public let birthYear: Int?

    public let gender: Gender

    public let sexAtBirth: Sex

    /// Freeform text describing relevant characteristics or medical conditions
    public let characteristics: String

    /// Tags for categorization and filtering
    public let subjectTags: [String]
}

extension Subject: Hashable {
    /// Support for SwiftUI ForEach and List
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Parameters for creating a new subject.
///
/// All fields except `sexAtBirth`, `gender`, and `characteristics` are required.
///
/// ```swift
/// let params = SubjectParameters(
///     name: "John Doe",
///     weight: 75.0,        // kilograms
///     height: 180.0,       // centimeters
///     birthYear: 1990,
///     gender: .man,
///     sexAtBirth: .man,
///     characteristics: "Regular training schedule",
///     subjectTags: ["athlete", "unimpaired"],
///     terms: true
/// )
///
/// let subject = try await service.createSubject(parameters: params)
/// ```
public struct SubjectParameters: Sendable {
    public let name: String

    /// Weight in kilograms
    public let weight: Double

    /// Height in centimeters
    public let height: Double

    /// Year of birth
    public let birthYear: Int

    public let sexAtBirth: Subject.Sex
    public let gender: Subject.Gender

    /// Freeform text describing relevant characteristics or medical conditions
    public let characteristics: String

    /// Tags for categorization and filtering (must contain at least one tag)
    public let subjectTags: [String]

    /// Confirmation that informed consent has been obtained
    public let terms: Bool

    public init(
        name: String,
        weight: Double,
        height: Double,
        birthYear: Int,
        subjectTags: [String],
        sexAtBirth: Subject.Sex? = nil,
        gender: Subject.Gender? = nil,
        characteristics: String = "",
        terms: Bool = true
    ) {
        self.name = name
        self.weight = weight
        self.height = height
        self.birthYear = birthYear
        self.subjectTags = subjectTags
        self.sexAtBirth = sexAtBirth ?? .noResponse
        self.gender = gender ?? .noResponse
        self.characteristics = characteristics
        self.terms = terms
    }
}

// MARK: - Video

/// A recorded video file from an activity.
///
/// Videos are automatically uploaded to the cloud during recording.
/// Use `video` to download the full video or `videoThumb` for preview thumbnails.
public struct Video: Sendable {
    public let id: String
    public let activity: String
    public let video: String?
    public let videoThumb: String?
}

/// Specifies the type of video to retrieve from an activity.
///
/// Videos in an activity can exist in different processing states. Use this enumeration to specify
/// which version of the videos you want to download.
public enum VideoVersion: Sendable {
    /// The original, unprocessed video as captured or uploaded.
    ///
    /// Raw videos represent the source material before any synchronization has been applied.
    case raw

    /// Videos that have been synchronized.
    ///
    /// Synced videos have undergone processing and may include temporal alignment,
    /// or other transformations applied during analysis.
    case synced
}

// MARK: - Activity Management

/// A movement recording session with associated videos and analysis results.
///
/// Trials track the complete lifecycle of a recording from capture through
/// processing to final analysis.
///
/// ```swift
/// let activities = try await service.activityList()
/// let completed = activities.filter { $0.status == "completed" && !$0.trashed }
/// ```
public struct Activity: Sendable {
    public struct Result: Sendable {
        public let id: Int
        public let activity: String
        public let tag: String?
        public let media: String?
    }

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
/// Specifies how activities should be ordered when retrieved from the API.
///
/// ```swift
/// let activities = try await service.getActivities(
///     forSubject: subjectId,
///     startIndex: 0,
///     count: 20,
///     sortedBy: .updatedAt
/// )
/// ```
public enum ActivitySort: Sendable {
    case updatedAt
}

/// A tag that can be applied to activities for categorization.
///
/// Activity tags provide a way to organize and filter activities.
/// Common tags might include activity types (e.g., "CMJ", "Squat"),
/// conditions (e.g., "Baseline", "Post-Training"), or any custom categorization.
///
/// ```swift
/// let tags = try await service.getActivityTags()
/// let cmjTag = tags.first { $0.value == "cmj" }
/// print("CMJ activities: \(cmjTag?.label ?? "")")
/// ```
public struct ActivityTag: Sendable {
    public let value: String
    public let label: String
}

/// Specifies the type of result data to retrieve from an activity, including the desired file format.
///
/// Trials can generate different types of output data during processing and analysis.
/// Use this enumeration to specify which types of data you want to download and in which format.
///
/// ```swift
/// // Download animation data (JSON only)
/// let animationData = await service.data(ofType: [.animation], for: activity)
///
/// // Download kinematics in MOT format
/// let motData = await service.data(ofType: [.kinematics(.mot)], for: activity)
///
/// // Download kinematics in both formats
/// let bothFormats = await service.data(ofType: [.kinematics(.mot), .kinematics(.csv)], for: activity)
/// ```
public enum ResultDataType: Hashable, Sendable {
    /// Animation data for interpreting movement analysis results. Always JSON format.
    case animation

    /// Raw kinematics data including joint positions, angles, and velocities.
    ///
    /// (**Only available in dynamic activities**)
    case kinematics(KinematicsFormat)

    /// Marker trajectory data.
    case markers(MarkersFormat)

    /// OpenSim model. Always OSim format.
    ///
    /// (**Only available in neutral activities**)
    case model

    /// Available file formats for kinematics result data.
    public enum KinematicsFormat: Sendable {
        /// OpenSim Motion (.mot) format
        case mot
        /// Comma-separated values (.csv) format
        case csv
    }

    /// Available file formats for marker result data.
    public enum MarkersFormat: Sendable {
        /// TRC marker trajectory (.trc) format
        case trc
        /// Comma-separated values (.csv) format
        case csv
    }
}

/// Result data downloaded from an activity.
///
/// Each instance carries the ``resultDataType`` that was requested, which also
/// implies the file format. Use ``resultDataType`` to determine how to parse ``data``.
///
/// ```swift
/// let results = await service.data(ofType: [.kinematics(.mot)], for: activity)
///
/// for result in results {
///     // result.resultDataType identifies both the type and implicit file format
///     // Use result.data directly as a .mot file
/// }
/// ```
public struct ResultData: Sendable {
    /// The type of result data and its file format. Use this to determine how to parse the raw data.
    public let resultDataType: ResultDataType


    /// The raw file data
    ///
    /// Parse this data according to the file format of the associated ``ResultDataType``. For JSON files, use `JSONDecoder`.
    /// For CSV files, convert to a string with UTF-8 encoding, etc.
    public let data: Data
}

// MARK: - Analysis Result Data

/// Type of analysis result data to download from a completed trial.
///
/// After analysis completes, three result types are available. The file format
/// is implicit in the type:
/// - ``metrics`` — JSON containing computed biomechanical metrics
/// - ``data`` — ZIP containing raw analysis data
/// - ``report`` — PDF report
public enum AnalysisResultDataType: Hashable, Sendable {
    /// Computed biomechanical metrics. Always JSON format.
    case metrics
    /// Raw analysis data. Always ZIP format.
    case data
    /// Analysis report. Always PDF format.
    case report
}

/// Downloaded analysis result data from a completed trial.
///
/// The file format is implicit in ``resultDataType``:
/// - ``AnalysisResultDataType/metrics`` → JSON
/// - ``AnalysisResultDataType/data`` → ZIP
/// - ``AnalysisResultDataType/report`` → PDF
///
/// ```swift
/// let results = await service.analysisResultData(ofType: [.metrics, .report, .data], for: activity)
///
/// for result in results {
///     switch result.resultDataType {
///     case .metrics:
///         let decoder = JSONDecoder()
///         // Decode metrics JSON from result.data
///     case .report:
///         // Use result.data directly as a PDF
///     case .data:
///         // Use result.data directly as a ZIP file
///     }
/// }
/// ```
public struct AnalysisResultData: Sendable {
    /// The type of analysis result, which implies the file format.
    public let resultDataType: AnalysisResultDataType

    /// The raw file data.
    ///
    /// Parse according to the format implied by ``resultDataType``.
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
    /// Checkerboard facing camera directly
    case perpendicular

    /// Checkerboard placed on the ground
    case parallel
}

extension CheckerboardPlacement {
    /// Support for SwiftUI ForEach and Picker
    public var id: String {
        self.rawValue
    }
}

// MARK: - Checkerboard Details

/// Configuration for a calibration checkerboard pattern.
///
/// **Important:** Row and column counts refer to internal corners, not squares.
/// For a standard 5×6 checkerboard, use `rows: 4, columns: 5`.
/// Square size must be measured precisely in millimeters for accurate calibration.
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
    /// Number of internal corners (rows). For 5×6 squares, use 4
    public let rows: Int

    /// Number of internal corners (columns). For 5x6 squares, use 5
    public let columns: Int

    /// Size of each square in millimeters (must be precise)
    public let squareSize: Int

    /// Checkerboard orientation
    public let placement: CheckerboardPlacement

    public init(rows: Int, columns: Int, squareSize: Int, placement: CheckerboardPlacement) {
        self.rows = rows
        self.columns = columns
        self.squareSize = squareSize
        self.placement = placement
    }
}

/// Represents the current status of a calibration process.
///
/// This enum tracks the progression of either camera calibration or neutral pose calibration,
/// providing real-time feedback on the recording, upload, and processing stages.
///
/// ## Usage
/// ```swift
/// try await service.calibrateNeutralPose(
///     for: subject,
///     in: session
/// ) { status in
///     switch status {
///     case .recording:
///         print("Recording...")
///
///     case .uploading(let uploaded, let total):
///         print("Uploading: \(uploaded)/\(total)")
///
///     case .processing(let percent):
///         print("Processing: \(percent ?? 0)%")
///
///     case .done(let images):
///         print("Complete! \(images.count) videos processed")
///     }
/// }
/// ```
public enum CalibrationStatus: Sendable {
    /// The recording phase is in progress.
    ///
    /// During this phase, all connected cameras are actively recording.
    /// If calibrating the neutral pose the subject should remain still and hold their pose until this phase completes.
    case recording

    /// Recordings have been stopped and videos are being uploaded from cameras.
    ///
    /// - Parameters:
    ///   - uploaded: The number of videos successfully uploaded so far.
    ///   - total: The total number of videos expected from all cameras.
    ///
    /// Use this status to display upload progress to users. The subject can relax
    /// during this phase as recording has completed.
    case uploading(uploaded: Int, total: Int)

    /// The server is processing the uploaded videos.
    ///
    /// - Parameter percent: The processing completion percentage (0-100), or `nil` if
    ///   processing has not yet started or progress is unavailable.
    case processing(percent: Int?)

    /// Calibration has completed successfully.
    case done
}

/// Represents available analysis functions for motion capture data.
///
/// Each analysis type processes activity data to extract specific biomechanical metrics
/// and insights. Analysis can only be performed on activities that have completed processing.
public enum AnalysisType: String, CaseIterable, Sendable {
    /// Counter Movement Jump
    case counterMovementJump = "Counter Movement Jump"

    /// Overground Walking
    case gait = "Overground Walking"

    /// Treadmill Running
    case treadmillRunning = "Treadmill Running"

    /// Sit-to-Stand Transfer
    case sitToStand = "Sit-to-Stand Transfer"

    /// Squat Exercise
    case squats = "Squats"

    /// Range of Motion (ROM)
    case rangeOfMotion = "Range of Motion"

    /// Overground Running
    case overgroundRunning = "Overground Running"

    /// Drop Vertical Jump
    case dropJump = "Drop Vertical Jump"

    /// Hop Test
    case hop = "Hop Test"

    /// Treadmill Walking
    case treadmillGait = "Treadmill Walking"

    /// 5-0-5 Test
    case changeOfDirection = "5-0-5 Test"

    /// Cutting Manoeuvre
    case cut = "Cutting Manoeuvre"
}

/// Represents the current processing state of an activity.
///
/// Trials must reach the `ready` state before analysis can be performed.
public enum ActivityProcessingStatus: Sendable {
    case uploading(uploaded: Int, total: Int)
    case processing
    case ready
    case failed
}

/// Represents an active analysis task.
///
/// Use the `taskId` to poll for analysis completion status.
public struct AnalysisTask: Sendable {
    public let taskId: String
}

/// Represents the current state of an analysis task.
public enum AnalysisTaskStatus: Sendable {
    case processing
    case completed
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
        public var subjectTags: [String] = []

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
                characteristics: characteristics,
                subjectTags: subjectTags
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

extension ResultData {
    public static func forPreview(
        resultDataType: ResultDataType,
        customizing: (inout PreviewBuilder) -> Void = { _ in }
    ) -> Self {
        var builder = PreviewBuilder(resultDataType: resultDataType)
        customizing(&builder)
        return builder.build()
    }

    public struct PreviewBuilder {
        public let resultDataType: ResultDataType
        public let data: Data = Data("time,position,velocity\n0.0,0.0,0.0\n1.0,1.0,1.0".utf8)

        func build() -> ResultData {
            ResultData(
                resultDataType: resultDataType,
                data: data
            )
        }
    }
}

extension AnalysisTask {
    public static func forPreview(
        customizing: (inout PreviewBuilder) -> Void = { _ in }
    ) -> Self {
        var builder = PreviewBuilder()
        customizing(&builder)
        return builder.build()
    }

    public struct PreviewBuilder {
        public var taskId = "preview-analysis-task"

        func build() -> AnalysisTask {
            AnalysisTask(taskId: taskId)
        }
    }
}

extension AnalysisResultData {
    public static func forPreview(
        customizing: (inout PreviewBuilder) -> Void = { _ in }
    ) -> Self {
        var builder = PreviewBuilder()
        customizing(&builder)
        return builder.build()
    }

    public struct PreviewBuilder {
        public let resultDataType: AnalysisResultDataType = .metrics
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

        func build() -> AnalysisResultData {
            AnalysisResultData(
                resultDataType: resultDataType,
                data: data
            )
        }
    }
}
