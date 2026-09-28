import Foundation

// MARK: - Activities

/// Filtered access to activities.
///
/// Reached through ``ModelHealthClient/activities`` — do not construct directly.
public struct ActivitiesResource {
    private let provider: ModelHealthProvider

    internal init(provider: ModelHealthProvider) {
        self.provider = provider
    }

    /// Lazily lists activities matching the given filters.
    ///
    /// ```swift
    /// let activities = client.activities.list(subject: subject, orderBy: .createdAtDescending)
    /// print("\(try await activities.total) total")
    /// for try await activity in activities {
    ///     print(activity.name ?? activity.id)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - subject: Only activities belonging to this subject.
    ///   - calibrationSession: Only activities recorded under this calibration session.
    ///   - activityType: Only activities of this type.
    ///   - excludeCalibration: Excludes calibration and neutral-pose activities. Default
    ///     `true`, since these are rarely what you want when browsing a subject's history.
    ///   - createdAfter: Only activities created on or after this date, inclusive. The day
    ///     is the one the date falls on in the current time zone, not in UTC.
    ///   - createdBefore: Only activities created on or before this date, inclusive. As
    ///     ``createdAfter``.
    ///   - search: Free-text search against the activity's name.
    ///   - tags: Only activities carrying every tag in this list.
    ///   - createdBy: Only activities belonging to one of these accounts, by numeric account id.
    ///   - onlyCompleted: Only activities whose analysis has finished.
    ///   - excludeAnalysisError: Excludes activities whose analysis failed.
    ///   - orderBy: Field to sort by. Defaults to newest first.
    ///   - limit: Caps the total number of activities the stream yields across the whole
    ///     iteration. `nil` iterates every match.
    /// - Returns: An ``ActivityStream`` you iterate directly.
    public func list(
        subject: Subject? = nil,
        calibrationSession: Session? = nil,
        activityType: ActivityTypeInfo? = nil,
        excludeCalibration: Bool = true,
        createdAfter: Date? = nil,
        createdBefore: Date? = nil,
        search: String? = nil,
        tags: [String]? = nil,
        createdBy: [Int]? = nil,
        onlyCompleted: Bool = false,
        excludeAnalysisError: Bool = false,
        orderBy: ActivityOrderBy? = nil,
        limit: Int? = nil
    ) -> ActivityStream {
        let filter = ActivityFilterPayload(
            subjectId: subject?.id,
            calibrationSessionId: calibrationSession?.id,
            activityType: activityType?.name,
            activityTypeId: nil,
            excludeCalibrate: excludeCalibration,
            excludeNeutral: excludeCalibration,
            createdAfter: formatFilterDate(createdAfter),
            createdBefore: formatFilterDate(createdBefore),
            search: search,
            tags: tags,
            createdBy: createdBy,
            onlyCompleted: onlyCompleted,
            excludeAnalysisError: excludeAnalysisError
        )
        let filterJSON = encodeFilter(filter)
        let provider = provider

        return provider.activitiesStream(
            filterJSON: filterJSON,
            orderBy: orderBy?.rawValue,
            limit: limit
        )
    }
}

// MARK: - Subjects

/// Filtered access to subjects.
///
/// Reached through ``ModelHealthClient/subjects`` — do not construct directly.
public struct SubjectsResource {
    private let provider: ModelHealthProvider

    internal init(provider: ModelHealthProvider) {
        self.provider = provider
    }

    /// Lazily lists subjects matching the given filters.
    ///
    /// ```swift
    /// for try await subject in client.subjects.list(search: "Falisse") {
    ///     print(subject.name)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - search: Free-text search against the subject's name.
    ///   - createdAfter: Only subjects created on or after this date, inclusive. The day
    ///     is the one the date falls on in the current time zone, not in UTC.
    ///   - createdBefore: Only subjects created on or before this date, inclusive. As
    ///     ``createdAfter``.
    ///   - groups: Only subjects belonging to one of these subject groups, by group id.
    ///   - tags: Only subjects carrying every tag in this list.
    ///   - createdBy: Only subjects belonging to one of these accounts, by numeric account id.
    ///   - activityType: Only subjects with at least one activity of this type.
    ///   - activityComplete: Only subjects whose activities have (`true`) or have not
    ///     (`false`) all finished analysis.
    ///   - session: Only the subject calibrated under this session.
    ///   - orderBy: Field to sort by. Defaults to name, ascending.
    ///   - limit: Caps the total number of subjects the stream yields across the whole
    ///     iteration. `nil` iterates every match.
    /// - Returns: A ``SubjectStream`` you iterate directly.
    public func list(
        search: String? = nil,
        createdAfter: Date? = nil,
        createdBefore: Date? = nil,
        groups: [String]? = nil,
        tags: [String]? = nil,
        createdBy: [Int]? = nil,
        activityType: ActivityTypeInfo? = nil,
        activityComplete: Bool? = nil,
        session: Session? = nil,
        orderBy: SubjectOrderBy? = nil,
        limit: Int? = nil
    ) -> SubjectStream {
        let filter = SubjectFilterPayload(
            search: search,
            createdAfter: formatFilterDate(createdAfter),
            createdBefore: formatFilterDate(createdBefore),
            groups: groups,
            tags: tags,
            createdBy: createdBy,
            activityType: activityType?.name,
            activityTypeId: nil,
            activityComplete: activityComplete,
            sessionId: session?.id
        )
        let filterJSON = encodeFilter(filter)
        let provider = provider

        return provider.subjectsStream(
            filterJSON: filterJSON,
            orderBy: orderBy?.rawValue,
            limit: limit
        )
    }
}

// MARK: - Sessions

/// Filtered access to sessions.
///
/// Reached through ``ModelHealthClient/sessions`` — do not construct directly.
public struct SessionsResource {
    private let provider: ModelHealthProvider

    internal init(provider: ModelHealthProvider) {
        self.provider = provider
    }

    /// Lazily lists sessions matching the given filters.
    ///
    /// - Parameters:
    ///   - subject: Only the session(s) belonging to this subject.
    ///   - orderBy: Field to sort by. Defaults to newest first.
    ///   - limit: Caps the total number of sessions the stream yields across the whole
    ///     iteration. `nil` iterates every match.
    /// - Returns: A ``SessionStream`` you iterate directly.
    public func list(
        subject: Subject? = nil,
        orderBy: SessionOrderBy? = nil,
        limit: Int? = nil
    ) -> SessionStream {
        let filterJSON = encodeFilter(SessionFilterPayload(subjectId: subject?.id))
        let provider = provider

        return provider.sessionsStream(
            filterJSON: filterJSON,
            orderBy: orderBy?.rawValue,
            limit: limit
        )
    }
}

// MARK: - Groups

/// Filtered access to subject groups.
///
/// Reached through ``ModelHealthClient/groups`` — do not construct directly.
public struct GroupsResource {
    private let provider: ModelHealthProvider

    internal init(provider: ModelHealthProvider) {
        self.provider = provider
    }

    /// Lazily lists subject groups matching the given filters.
    ///
    /// - Parameters:
    ///   - search: Free-text search against the group's name.
    ///   - orderBy: Field to sort by. Defaults to name, ascending.
    ///   - limit: Caps the total number of groups the stream yields across the whole
    ///     iteration. `nil` iterates every match.
    /// - Returns: A ``GroupStream`` you iterate directly.
    public func list(
        search: String? = nil,
        orderBy: GroupOrderBy? = nil,
        limit: Int? = nil
    ) -> GroupStream {
        let filterJSON = encodeFilter(GroupFilterPayload(search: search))
        let provider = provider

        return provider.groupsStream(
            filterJSON: filterJSON,
            orderBy: orderBy?.rawValue,
            limit: limit
        )
    }
}
