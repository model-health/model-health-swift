import Foundation

/// The primary interface for Model Health's movement analysis platform.
///
/// ModelHealthService enables you to measure and analyze human movement from smartphone
/// videos. It provides a complete workflow for:
/// - Authentication and session management
/// - Subject profile management
/// - Camera and subject calibration
/// - Movement data collection
/// - Analysis and result retrieval
///
/// ## Overview
///
/// The SDK follows a structured workflow:
///
/// 1. **Initialization**: Create a service with your API key
/// 2. **Session Creation**: Create a session
/// 3. **Camera Calibration**: Calibrate cameras using a checkerboard pattern
/// 4. **Subject Creation**: Create a subject profile with anthropometric measurements
/// 5. **Subject Calibration**: Calibrate subject using videos of a neutral pose
/// 6. **Movement Recording**: Record movement activities (squats, jumps, etc.)
/// 7. **Movement Analysis**: Trigger advanced analysis and fetch processed biomechanical data
///
/// ## Usage Example
///
/// ```swift
/// let service = try ModelHealthService(apiKey: "your-api-key")
///
/// // Create session
/// let session = try await service.createSession()
///
/// // Calibrate cameras
/// let details = CheckerboardDetails(rows: 4, columns: 5, squareSize: 35, placement: .perpendicular)
/// try await service.calibrateCamera(session, checkerboardDetails: details) { status in }
///
/// // Create subject and calibrate
/// let params = SubjectParameters(name: "Jane Doe", weight: 65, height: 170, birthYear: 1990, gender: .woman, sexAtBirth: .woman)
/// let subject = try await service.createSubject(parameters: params)
/// try await service.calibrateSubject(subject, in: session) { status in }
///
/// // Record a movement activity
/// let activity = try await service.startRecording(activityNamed: "cmj", in: session)
/// // Subject performs movement...
/// try await service.stopRecording(session)
///
/// // Check if activity is ready for analysis (poll until .ready)
/// let status = try await service.activityStatus(for: activity)
/// // Run advanced biomechanical analysis when ready
/// if case .ready = status {
///     let task = try await service.startAnalysis(.counterMovementJump, for: activity, in: session)
///     // Poll for analysis completion...
/// }
/// ```
///
/// ## Topics
///
/// ### Data Retrieval
/// - ``subjectList()``
/// - ``activityList(for:)``
///
/// ### Session & Calibration
/// - ``createSession()``
/// - ``calibrateCamera(_:checkerboardDetails:statusUpdate:)``
/// - ``calibrateSubject(_:in:statusUpdate:)``
///
/// ### Recording & Analysis
/// - ``startRecording(activityNamed:in:)``
/// - ``stopRecording(_:)``
/// - ``activityStatus(for:)``
/// - ``startAnalysis(_:for:in:)``
/// - ``analysisStatus(for:)``
/// - ``analysisData(ofType:for:)``
public final class ModelHealthService: ObservableObject, @unchecked Sendable {
    private let serviceProvider: ModelHealthProvider

    /// Creates a new ModelHealth SDK instance with an API key.
    ///
    /// The SDK requires an API key for authentication. Contact support@modelhealth.io
    /// to obtain one.
    ///
    /// ```swift
    /// let service = try ModelHealthService(apiKey: "your-api-key-here")
    /// let session = try await service.createSession()
    /// ```
    ///
    /// - Parameter apiKey: Your ModelHealth API key, available in the dashboard at modelhealth.io
    /// - Throws: A ``ModelHealthError`` if the API key is empty or invalid
    public init(apiKey: String) throws {
        self.serviceProvider = try ModelHealthProviderImpl(apiKey: apiKey)
    }

    /// Creates a ModelHealth SDK instance with a custom service provider.
    ///
    /// Use this initializer to inject a custom ``ModelHealthProvider`` implementation — typically
    /// a mock for unit testing or an alternative provider for staging environments.
    ///
    /// ```swift
    /// let mock = MockModelHealthProvider()
    /// let service = ModelHealthService(serviceProvider: mock)
    /// ```
    ///
    /// - Parameter serviceProvider: A custom implementation of ``ModelHealthProvider``,
    ///   typically a mock for unit testing or a custom provider for staging environments.
    public init(serviceProvider: ModelHealthProvider) {
        self.serviceProvider = serviceProvider
    }

    // MARK: - Data Retrieval

    /// Retrieves all sessions for the account associated with the API key.
    ///
    /// Use this to list existing sessions before creating a new one, or to resume a previous
    /// capture workflow.
    ///
    /// To connect to a device to a specific session, use the session's ``Session/qrcode`` to download
    /// the QR code image data, then display it on your app to be captured by the ModelHealth mobile app.
    ///
    /// ```swift
    /// let sessions = try await service.sessionList()
    /// print("Found \(sessions.count) sessions")
    ///
    /// // Download and display QR code for the first session
    /// guard
    ///     let firstSession = sessions.first,
    ///     let qrCode = firstSession.qrcode,
    ///     let url = URL(string: qrCode)
    /// else {
    ///     // handle failure
    /// }
    /// ```
    ///
    /// - Returns: An array of ``Session`` objects, or an empty array if none exist.
    /// - Throws: A ``ModelHealthError`` if the request fails due to network or authentication issues.
    public func sessionList() async throws -> [Session] {
        try await serviceProvider.sessionList()
    }

    /// Retrieves all movement activities associated with a session.
    ///
    /// Activities represent individual recording trials and contain references to
    /// captured videos and results. Use this to review past data or
    /// fetch results for completed activities.
    ///
    /// ```swift
    /// let activities = try await service.activityList(for: session)
    ///
    /// for activity in activities {
    ///     print("Activity: \(activity.name ?? activity.id)")
    ///     print("Videos: \(activity.videos.count)")
    ///     print("Results: \(activity.results.count)")
    /// }
    /// ```
    ///
    /// - Parameter session: The session to retrieve activities for.
    /// - Returns: An array of ``Activity`` objects, or an empty array if none exist.
    /// - Throws: A ``ModelHealthError`` if the request fails due to network or authentication issues.
    public func activityList(for session: Session) async throws -> [Activity] {
        try await serviceProvider.activityList(for: session)
    }

    /// Downloads video data for a specific activity.
    ///
    /// Fetches all videos associated with the activity that match the specified version.
    /// Downloads run concurrently. Videos with invalid URLs or failed downloads are silently
    /// excluded from the result.
    ///
    /// ```swift
    /// let videoData = await service.videos(for: activity, version: .raw)
    /// for data in videoData {
    ///     // Process video data
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - activity: The activity whose videos should be downloaded.
    ///   - version: The version of videos to download (e.g., `.raw`, `.synced`).
    /// - Returns: An array of `Data` objects. May be empty if no videos are available or all
    ///   downloads fail.
    public func videos(for activity: Activity, version: VideoVersion) async -> [Data] {
        await serviceProvider.videos(for: activity, version: version)
    }

    /// Downloads motion data from a processed activity.
    ///
    /// Use this after an activity reaches `.ready` status to retrieve biomechanical result files
    /// such as kinematics, marker data, or an OpenSim model. Downloads run concurrently and
    /// failed downloads are silently excluded from results.
    ///
    /// ```swift
    /// let results = await service.motionData(ofType: [.kinematics(.mot), .animation], for: activity)
    ///
    /// for result in results {
    ///     switch result.resultDataType {
    ///     case .kinematics(.mot):
    ///         // Use result.data directly as a .mot file
    ///     case .animation:
    ///         // Use result.data directly as an animation file
    ///     default:
    ///         break
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - types: The result data types to download (e.g., `.kinematics(.mot)`, `.markers`, `.animation`).
    ///   - activity: The activity to download data from. Must have completed processing.
    /// - Returns: An array of ``MotionData``, one entry per successfully downloaded type. May be empty
    ///   if no results are available or all downloads fail.
    public func motionData(ofType types: Set<MotionDataType>, for activity: Activity) async -> [MotionData] {
        await serviceProvider.motionData(ofType: types, for: activity)
    }

    /// Downloads result data for an activity with a completed analysis.
    ///
    /// Use this after ``analysisStatus(for:)`` returns `.completed` to retrieve metrics,
    /// a report, or raw data. Downloads run concurrently and failed downloads are silently
    /// excluded from results.
    ///
    /// ```swift
    /// let results = await service.analysisData(ofType: [.metrics, .report, .data], for: activity)
    ///
    /// for result in results {
    ///     switch result.resultDataType {
    ///     case .metrics:
    ///         // Decode result.data as JSON
    ///     case .report:
    ///         // Use result.data directly as a PDF
    ///     case .data:
    ///         // Use result.data directly as a ZIP file
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - types: The analysis result types to download (e.g., `.metrics`, `.report`, `.data`).
    ///   - activity: The activity to download results from. Must have a completed analysis.
    /// - Returns: An array of ``AnalysisData``, one entry per successfully downloaded type.
    ///   May be empty if no results are available or all downloads fail.
    public func analysisData(
        ofType types: Set<AnalysisDataType>,
        for activity: Activity
    ) async -> [AnalysisData] {
        await serviceProvider.analysisData(ofType: types, for: activity)
    }

    // MARK: - Subject Management

    /// Retrieves all subjects associated with the API key.
    ///
    /// Subjects represent individuals being monitored or assessed. Each subject may
    /// contain demographic information, physical measurements, and categorization tags.
    ///
    /// ```swift
    /// let subjects = try await service.subjectList()
    /// for subject in subjects {
    ///     print("\(subject.name): \(subject.height ?? 0)cm, \(subject.weight ?? 0)kg")
    /// }
    /// ```
    ///
    /// - Returns: An array of ``Subject`` objects, or an empty array if none exist.
    /// - Throws: A ``ModelHealthError`` if the request fails due to network or authentication issues.
    public func subjectList() async throws -> [Subject] {
        try await serviceProvider.subjectList()
    }

    /// Retrieves activities for a specific subject with pagination and sorting.
    ///
    /// Use this to display a subject's activity history or implement paginated list interfaces.
    ///
    /// ```swift
    /// // First page
    /// let page1 = try await service.activities(
    ///     forSubject: subject.id,
    ///     startIndex: 0,
    ///     count: 20,
    ///     sortedBy: .updatedAt
    /// )
    ///
    /// // Next page
    /// let page2 = try await service.activities(
    ///     forSubject: subject.id,
    ///     startIndex: 20,
    ///     count: 20,
    ///     sortedBy: .updatedAt
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - subjectId: The ID of the subject whose activities to retrieve.
    ///   - startIndex: Zero-based index to start from. Use `0` for the first page.
    ///   - count: Number of activities to retrieve per request.
    ///   - sort: Sort order for the results (e.g., `.updatedAt` for most recent first).
    /// - Returns: An array of ``Activity`` objects, or an empty array if none exist.
    /// - Throws: A ``ModelHealthError`` if the request fails due to network or authentication issues.
    public func activities(
        forSubject subjectId: String,
        startIndex: Int,
        count: Int,
        sortedBy sort: ActivitySort
    ) async throws -> [Activity] {
        try await serviceProvider.activities(
            forSubject: subjectId,
            startIndex: startIndex,
            count: count,
            sortedBy: sort
        )
    }

    /// Retrieves an activity by its ID.
    ///
    /// Use this to fetch the latest state of an activity, including its videos, results,
    /// and current processing status.
    ///
    /// ```swift
    /// let activity = try await service.fetch(activity: "abc123")
    /// print("Activity: \(activity.name ?? "Unnamed")")
    /// print("Status: \(activity.status)")
    /// ```
    ///
    /// - Parameter activityId: The unique identifier of the activity.
    /// - Returns: The ``Activity`` with its current details.
    /// - Throws: A ``ModelHealthError`` if the activity doesn't exist or the request fails.
    public func fetch(activity activityId: String) async throws -> Activity {
        try await serviceProvider.fetch(activity: activityId)
    }

    /// Updates an activity.
    ///
    /// Only mutable fields (such as `name`) are applied on the server. The server-side
    /// state is returned, so use the result rather than the input going forward.
    ///
    /// ```swift
    /// var activity = try await service.fetch(activity: "abc123")
    /// activity.name = "CMJ Baseline Test"
    /// let updated = try await service.update(activity: activity)
    /// ```
    ///
    /// - Parameter activity: The activity to update, with modified properties.
    /// - Returns: The updated ``Activity`` as stored on the server.
    /// - Throws: A ``ModelHealthError`` if the update fails or the request fails.
    public func update(activity: Activity) async throws -> Activity {
        try await serviceProvider.update(activity: activity)
    }

    /// Deletes an activity.
    ///
    /// Permanently removes the activity and all associated videos, results, and metadata.
    ///
    /// ```swift
    /// try await service.delete(activity: activity)
    /// ```
    ///
    /// > Warning: This operation is irreversible.
    ///
    /// - Parameter activity: The activity to delete.
    /// - Throws: A ``ModelHealthError`` if the deletion fails or the request fails.
    public func delete(activity: Activity) async throws {
        try await serviceProvider.delete(activity: activity)
    }

    /// Retrieves all available activity tags.
    ///
    /// Use the returned tags to populate a tag picker or validate tag values before
    /// assigning them to activities.
    ///
    /// ```swift
    /// let tags = try await service.activityTags()
    /// for tag in tags {
    ///     print("\(tag.label): \(tag.value)")
    /// }
    /// ```
    ///
    /// - Returns: An array of ``ActivityTag`` objects, or an empty array if none are configured.
    /// - Throws: A ``ModelHealthError`` if the request fails due to network or authentication issues.
    public func activityTags() async throws -> [ActivityTag] {
        try await serviceProvider.activityTags()
    }

    /// Creates a subject profile.
    ///
    /// Height and weight are required for biomechanical analysis. Once created, the subject
    /// can be calibrated using ``calibrateSubject(_:in:statusUpdate:)``.
    ///
    /// ```swift
    /// let params = SubjectParameters(
    ///     name: "John Smith",
    ///     weight: 75.0,
    ///     height: 180.0,
    ///     birthYear: 1990,
    /// )
    /// let subject = try await service.createSubject(parameters: params)
    /// print("Created subject with ID: \(subject.id)")
    ///
    /// // Use the subject for calibration
    /// try await service.calibrateSubject(subject, in: session) { _ in }
    /// ```
    ///
    /// - Parameter parameters: The subject's profile details including name and anthropometrics.
    /// - Returns: The newly created ``Subject`` with its assigned ID.
    /// - Throws: A ``ModelHealthError`` if creation fails (e.g., validation error or duplicate name).
    public func createSubject(parameters: SubjectParameters) async throws -> Subject {
        try await serviceProvider.createSubject(parameters: parameters)
    }

    // MARK: - Session & Calibration

    /// Creates a session.
    ///
    /// A session is the parent container for a movement capture workflow. It links
    /// related entities such as activities and subjects, and provides the context
    /// used by subsequent operations.
    ///
    /// ```swift
    /// let session = try await service.createSession()
    /// ```
    ///
    /// - Returns: A new ``Session`` with a unique identifier.
    /// - Throws: A ``ModelHealthError`` if session creation fails.
    public func createSession() async throws -> Session {
        try await serviceProvider.createSession()
    }

    /// Calibrates cameras using a checkerboard pattern.
    ///
    /// Determines each camera's position and orientation in 3D space (extrinsics), enabling
    /// reconstruction of real-world movement from multiple 2D video feeds. Required once per
    /// session setup — recalibrate only if cameras are moved.
    ///
    /// > Note: `rows` and `columns` refer to internal corners, not squares. A 5×6 board has
    /// > 4 internal corner rows and 5 internal corner columns.
    ///
    /// ```swift
    /// let details = CheckerboardDetails(
    ///     rows: 4,
    ///     columns: 5,
    ///     squareSize: 35,
    ///     placement: .perpendicular
    /// )
    /// try await service.calibrateCamera(session, checkerboardDetails: details) { status in
    ///     print(status)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - session: The session context in which calibration is performed.
    ///   - checkerboardDetails: The checkerboard dimensions and placement used for calibration.
    ///   - statusUpdate: Closure called with progress updates during calibration.
    /// - Throws: A ``ModelHealthError`` if calibration fails (e.g., pattern not detected).
    public func calibrateCamera(
        _ session: Session,
        checkerboardDetails: CheckerboardDetails,
        statusUpdate: @escaping @Sendable (CalibrationStatus) -> Void
    ) async throws {
        try await serviceProvider.calibrateCamera(
            session,
            checkerboardDetails: checkerboardDetails,
            statusUpdate: statusUpdate
        )
    }

    /// Calibrates a subject by recording a neutral standing pose.
    ///
    /// Scales the 3D biomechanical model to the subject's body size. Must be run after
    /// camera calibration and requires the subject profile to include height and weight.
    ///
    /// > Important: The subject must stand upright, feet pointing forward, completely still,
    /// > and fully visible to all cameras for the duration of the recording.
    ///
    /// ```swift
    /// try await service.calibrateSubject(subject, in: session) { status in
    ///     print(status)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - subject: The subject to calibrate
    ///   - session: The session context in which calibration is performed
    ///   - statusUpdate: Closure called with calibration status updates
    /// - Throws: An error if pose capture fails (subject not detected, insufficient visibility, etc.)
    public func calibrateSubject(
        _ subject: Subject,
        in session: Session,
        statusUpdate: @escaping @Sendable (CalibrationStatus) -> Void
    ) async throws {
        try await serviceProvider.calibrateSubject(
            subject,
            in: session,
            statusUpdate: statusUpdate
        )
    }

    // MARK: - Recording & Analysis

    /// Creates an activity and starts recording a dynamic movement trial.
    ///
    /// Must be called after both camera and subject calibration are complete.
    /// Call ``stopRecording(_:)`` when the subject has finished the movement.
    ///
    /// ```swift
    /// let activity = try await service.startRecording(activityNamed: "cmj", in: session)
    /// // Subject performs movement...
    /// try await service.stopRecording(session)
    /// ```
    ///
    /// - Parameters:
    ///   - name: A descriptive name for this activity (e.g., `"cmj"`, `"squat"`).
    ///   - session: The session this activity is associated with.
    /// - Returns: The newly created ``Activity``.
    /// - Throws: A ``ModelHealthError`` if recording cannot start (e.g., missing calibration).
    public func startRecording(activityNamed name: String, in session: Session) async throws -> Activity {
        try await serviceProvider.startRecording(activityNamed: name, in: session)
    }

    /// Stops the active recording for a movement trial.
    ///
    /// Call this after the subject has completed the movement. Once stopped, the recorded
    /// videos begin uploading and can be tracked with ``activityStatus(for:)``.
    ///
    /// ```swift
    /// try await service.stopRecording(session)
    /// ```
    ///
    /// - Parameter session: The session context to stop recording in.
    /// - Throws: A ``ModelHealthError`` if there is no active recording or the request fails.
    public func stopRecording(_ session: Session) async throws {
        try await serviceProvider.stopRecording(session)
    }

    /// Retrieves the current processing status of an activity.
    ///
    /// Poll this method after ``stopRecording(_:)`` to track upload and processing progress.
    /// Once the status reaches `.ready`, pass the activity to ``startAnalysis(_:for:in:)``.
    ///
    /// ```swift
    /// let status = try await service.activityStatus(for: activity)
    ///
    /// switch status {
    /// case .ready:
    ///     print("Activity ready for analysis")
    /// case .processing:
    ///     print("Still processing...")
    /// case .uploading(let uploaded, let total):
    ///     print("Uploaded \(uploaded)/\(total) videos")
    /// case .failed:
    ///     print("Processing failed")
    /// }
    /// ```
    ///
    /// - Parameter activity: The activity to check status for.
    /// - Returns: The current ``ActivityStatus``.
    /// - Throws: A ``ModelHealthError`` if the request fails.
    public func activityStatus(for activity: Activity) async throws -> ActivityStatus {
        try await serviceProvider.activityStatus(for: activity)
    }

    /// Starts an analysis task for an activity that is ready for analysis.
    ///
    /// Call this after ``activityStatus(for:)`` returns `.ready`. Use the
    /// returned ``Analysis`` with ``analysisStatus(for:)`` to poll progress.
    ///
    /// ```swift
    /// let task = try await service.startAnalysis(
    ///     .counterMovementJump,
    ///     for: activity,
    ///     in: session
    /// )
    ///
    /// let status = try await service.analysisStatus(for: task)
    /// ```
    ///
    /// - Parameters:
    ///   - analysisType: The type of analysis to run (for example, `.gait`, `.counterMovementJump`).
    ///   - activity: The activity to analyze.
    ///   - session: The session context containing the activity.
    /// - Returns: An ``Analysis`` for tracking analysis progress.
    /// - Throws: A ``ModelHealthError`` if the activity is not ready or the request fails.
    public func startAnalysis(
        _ analysisType: AnalysisType,
        for activity: Activity,
        in session: Session
    ) async throws -> Analysis {
        try await serviceProvider.startAnalysis(
            analysisType,
            for: activity,
            in: session
        )
    }

    /// Retrieves the current status of an analysis task.
    ///
    /// Poll this method after ``startAnalysis(_:for:in:)`` to monitor progress.
    /// When status reaches `.completed`, download results with ``analysisData(ofType:for:)``.
    ///
    /// ```swift
    /// let status = try await service.analysisStatus(for: task)
    ///
    /// switch status {
    /// case .processing:
    ///     print("Analysis running...")
    /// case .completed:
    ///     print("Analysis complete")
    /// case .failed:
    ///     print("Analysis failed")
    /// }
    /// ```
    ///
    /// - Parameter task: The task returned from ``startAnalysis(_:for:in:)``.
    /// - Returns: The current ``AnalysisStatus``.
    /// - Throws: A ``ModelHealthError`` if the request fails.
    public func analysisStatus(for task: Analysis) async throws -> AnalysisStatus {
        try await serviceProvider.analysisStatus(for: task)
    }
}

/// Defines ModelHealth SDK operations for dependency injection and testing.
///
/// Conform to this protocol to create mock implementations for testing.
///
/// See ``ModelHealthService`` for detailed documentation of each method.
public protocol ModelHealthProvider {
    /// See ``ModelHealthService/sessionList()``
    func sessionList() async throws -> [Session]

    /// See ``ModelHealthService/subjectList()``
    func subjectList() async throws -> [Subject]

    /// See ``ModelHealthService/activities(forSubject:startIndex:count:sortedBy:)``
    func activities(
        forSubject subjectId: String,
        startIndex: Int,
        count: Int,
        sortedBy sort: ActivitySort
    ) async throws -> [Activity]

    /// See ``ModelHealthService/fetch(activity:)``
    func fetch(activity activityId: String) async throws -> Activity

    /// See ``ModelHealthService/update(activity:)``
    func update(activity: Activity) async throws -> Activity

    /// See ``ModelHealthService/delete(activity:)``
    func delete(activity: Activity) async throws

    /// See ``ModelHealthService/activityTags()``
    func activityTags() async throws -> [ActivityTag]

    /// See ``ModelHealthService/activityList(for:)``
    func activityList(for session: Session) async throws -> [Activity]

    /// See ``ModelHealthService/videos(for:version:)``
    func videos(for activity: Activity, version: VideoVersion) async -> [Data]

    /// See ``ModelHealthService/motionData(ofType:for:)``
    func motionData(ofType types: Set<MotionDataType>, for activity: Activity) async -> [MotionData]

    /// See ``ModelHealthService/analysisData(ofType:for:)``
    func analysisData(
        ofType types: Set<AnalysisDataType>,
        for activity: Activity
    ) async -> [AnalysisData]

    /// See ``ModelHealthService/createSession()``
    func createSession() async throws -> Session

    /// See ``ModelHealthService/createSubject(parameters:)``
    func createSubject(parameters: SubjectParameters) async throws -> Subject

    /// See ``ModelHealthService/startRecording(activityNamed:in:)``
    func startRecording(activityNamed name: String, in session: Session) async throws -> Activity

    /// See ``ModelHealthService/stopRecording(_:)``
    func stopRecording(_ session: Session) async throws

    /// See ``ModelHealthService/calibrateCamera(_:checkerboardDetails:statusUpdate:)``
    func calibrateCamera(
        _ session: Session,
        checkerboardDetails: CheckerboardDetails,
        statusUpdate: @escaping @Sendable (CalibrationStatus) -> Void
    ) async throws

    /// See ``ModelHealthService/calibrateSubject(_:in:statusUpdate:)``
    func calibrateSubject(
        _ subject: Subject,
        in session: Session,
        statusUpdate: @escaping @Sendable (CalibrationStatus) -> Void
    ) async throws

    /// See ``ModelHealthService/activityStatus(for:)``
    func activityStatus(for activity: Activity) async throws -> ActivityStatus

    /// See ``ModelHealthService/startAnalysis(_:for:in:)``
    func startAnalysis(
        _ analysisType: AnalysisType,
        for activity: Activity,
        in session: Session
    ) async throws -> Analysis

    /// See ``ModelHealthService/analysisStatus(for:)``
    func analysisStatus(for task: Analysis) async throws -> AnalysisStatus
}

/// Errors thrown by ``ModelHealthService``.
public enum ModelHealthError: Error, Sendable {
    /// Errors specific to camera or subject calibration
    public enum CalibrationError: Sendable {
        case notEnoughCameras
        case calibrationFailed
    }

    /// HTTP response errors with status codes and optional server message
    public enum HTTPError: Sendable {
        /// A client error response (400–499).
        case clientError(statusCode: Int)
        /// A server error response (500–599).
        case serverError(statusCode: Int)
        /// A response with an unexpected status code.
        case unexpectedStatusCode(statusCode: Int)
    }

    /// Data file conversion errors
    public enum ConversionError: Sendable {
        case invalidEncoding
        case couldNotDetermineCSVColumns
        case emptyFile
    }

    /// Errors that occur in the URL Error domain
    case url(URLError.Code)

    /// Errors that occur during calibration
    case calibration(CalibrationError)

    /// HTTP response errors
    case http(HTTPError)

    /// Unexpected response from the server
    case unexpectedResponse

    /// An internal SDK error occurred
    case internalError(String)

    /// An error related to data file parsing & converting
    case dataFile(ConversionError)
}
