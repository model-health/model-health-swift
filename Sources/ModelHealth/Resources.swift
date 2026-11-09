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
    ///   - subjects: Only activities belonging to any of these subjects, in one request
    ///     rather than one per subject. Together with `subject`, matches activities of
    ///     `subject` *or* any of `subjects` (a union, not an intersection). Every subject
    ///     must be one you may view. Each activity's ``Activity/subjectInfo`` says whose it is.
    ///     An empty list is refused when the stream is first read, rather than read as
    ///     every subject: pass `nil` to match them all. Requires the V2 API: on a V1
    ///     provider, reading the stream throws a not-supported error.
    ///   - calibrationSession: Only activities recorded under this calibration session: the
    ///     session itself and every session that reuses its calibration.
    ///   - session: Only activities recorded in this session, and that session only.
    ///   - activityType: Only activities of this type.
    ///   - activityTypes: Only activities of any of these types. Together with
    ///     `activityType`, matches either (a union). An empty list is refused when the
    ///     stream is first read, rather than read as every type: pass `nil` to match them
    ///     all. Requires the V2 API, as `subjects`.
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
        subjects: [Subject]? = nil,
        calibrationSession: Session? = nil,
        session: Session? = nil,
        activityType: ActivityTypeInfo? = nil,
        activityTypes: [ActivityTypeInfo]? = nil,
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
            subjectIds: subjects?.map(\.id),
            calibrationSessionId: calibrationSession?.id,
            sessionId: session?.id,
            activityType: activityType?.name,
            activityTypeId: nil,
            activityTypes: activityTypes?.map(\.name),
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

    /// The subject with exactly this name, or `nil` when nobody has it.
    ///
    /// `search` on ``list(search:createdAfter:createdBefore:groups:tags:createdBy:activityType:activityComplete:session:orderBy:limit:)``
    /// narrows by substring; this matches the whole name, ignoring case. A prefix is not
    /// a name, and no match is `nil` rather than an error.
    ///
    /// - Parameter name: The subject's full name.
    /// - Returns: The ``Subject``, or `nil` when nobody has this name.
    /// - Throws: ``ModelHealthError/ambiguousMatch(_:)`` when more than one subject has
    ///   this name — the message lists their ids, so you can pick one with
    ///   ``ModelHealthClient/fetch(subject:)``. A blank name is refused before anything
    ///   is sent.
    public func find(name: String) async throws -> Subject? {
        try await provider.find(subject: name)
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
