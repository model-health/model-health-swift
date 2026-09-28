// swiftlint:disable file_length

import Foundation
import ModelHealthFFI

private let metricDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

// swiftlint:disable type_body_length
/// Internal implementation of ModelHealthProvider
internal final class ModelHealthProviderImpl: ModelHealthProvider {
    private let handle: UnsafeMutablePointer<ModelHealthProviderHandle>

    /// Retained context for the persistent log handler, if one is registered.
    ///
    /// Unlike the per-call `CallbackContext` below (retained just for the duration of one
    /// synchronous FFI call), this must survive for as long as a handler stays registered —
    /// see `setLogHandler(level:_:)`.
    private var logHandlerContextPtr: UnsafeMutableRawPointer?

    /// Creates a new provider with the given API key and optional transport overrides.
    ///
    /// The service URL is fixed and cannot be changed — there is intentionally no base-URL parameter.
    /// `timeout`/`maxRetries` override the defaults; `nil` keeps them.
    /// - Throws: ModelHealthError if provider creation fails
    init(apiKey: String, timeout: TimeInterval? = nil, maxRetries: Int? = nil) throws {
        let osVersion = ModelHealthProviderImpl.currentOSVersion()
        let timeoutSeconds = timeout ?? -1.0
        let maxRetriesValue = Int32(maxRetries ?? -1)

        self.handle = try apiKey.withCString { apiKeyPtr in
            try "swift".withCString { languagePtr in
                try osVersion.withCString { osVersionPtr in
                    guard let handle = model_health_provider_new(
                        apiKeyPtr, languagePtr, osVersionPtr, timeoutSeconds, maxRetriesValue
                    ) else {
                        throw ModelHealthError.internalError("Failed to create provider with API key")
                    }
                    return handle
                }
            }
        }
    }

    deinit {
        // Teardown order: clear the handler, then free the provider, then release the
        // Swift-side retained context — only once the provider can no longer call back.
        _ = model_health_set_log_handler(handle, nil, nil, LogLevel.off.cValue)
        model_health_provider_free(handle)
        if let logHandlerContextPtr = logHandlerContextPtr {
            Unmanaged<LogHandlerContext>.fromOpaque(logHandlerContextPtr).release()
        }
    }

    /// Verifies the API key and returns information about the authenticated account.
    func accountInfo() async throws -> AccountInfo {
        try await withCheckedThrowingContinuation { continuation in
            var cInfo = CAccountInfo(
                username: nil,
                email: nil,
                first_name: nil,
                last_name: nil,
                institution: nil,
                profession: nil,
                country: nil
            )
            let result = model_health_account_info(handle, &cInfo)

            if result.success {
                do {
                    let info = try AccountInfo.from(cAccountInfo: cInfo)
                    model_health_free_account_info(cInfo)
                    continuation.resume(returning: info)
                } catch {
                    model_health_free_account_info(cInfo)
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                model_health_free_account_info(cInfo)
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    /// Fetches the current billing/quota state for the authenticated account.
    func usage() async throws -> UsageInfo {
        try await withCheckedThrowingContinuation { continuation in
            var cInfo = CUsageInfo(
                recording_allowed: false,
                reason: -1,
                activities_used: -1,
                activities_max: -1,
                period_end: nil,
                plan_name: nil,
                is_free_trial: -1,
                reset_period: -1,
                will_auto_renew: -1
            )
            let result = model_health_usage(handle, &cInfo)

            if result.success {
                do {
                    let info = try UsageInfo.from(cUsageInfo: cInfo)
                    model_health_free_usage_info(cInfo)
                    continuation.resume(returning: info)
                } catch {
                    model_health_free_usage_info(cInfo)
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                model_health_free_usage_info(cInfo)
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    // MARK: - List Operations

    func sessionList() async throws -> [Session] {
        try await withCheckedThrowingContinuation { continuation in
            var cArray = CSessionArray(sessions: nil, count: 0)
            let result = model_health_session_list(handle, &cArray)

            defer {
                model_health_free_session_array(cArray)
            }

            if result.success {
                do {
                    var sessions: [Session] = []
                    if cArray.count > 0, let sessionsPtr = cArray.sessions {
                        sessions = try (0..<Int(cArray.count)).map { index in
                            try Session.from(cSession: sessionsPtr[index])
                        }
                    }
                    continuation.resume(returning: sessions)
                } catch {
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func getSession(id sessionId: String) async throws -> Session {
        try await withCheckedThrowingContinuation { continuation in
            var cSession = CSession(
                id: nil,
                name: nil,
                session_name: nil,
                user: 0,
                is_public: false,
                qrcode: nil,
                subject: 0,
                trials_count: 0,
                created_at: nil,
                updated_at: nil
            )

            let result = sessionId.withCString { sessionIdPtr in
                model_health_get_session(handle, sessionIdPtr, &cSession)
            }

            if result.success {
                do {
                    let session = try Session.from(cSession: cSession)
                    freeSessionFields(cSession)
                    continuation.resume(returning: session)
                } catch {
                    freeSessionFields(cSession)
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func newSession(from session: Session) async throws -> Session {
        try await withCheckedThrowingContinuation { continuation in
            var cSession = CSession(
                id: nil,
                name: nil,
                session_name: nil,
                user: 0,
                is_public: false,
                qrcode: nil,
                subject: 0,
                trials_count: 0,
                created_at: nil,
                updated_at: nil
            )

            let result = session.id.withCString { sessionIdPtr in
                model_health_new_session_from_session_id(handle, sessionIdPtr, &cSession)
            }

            if result.success {
                do {
                    let newSession = try Session.from(cSession: cSession)
                    freeSessionFields(cSession)
                    continuation.resume(returning: newSession)
                } catch {
                    freeSessionFields(cSession)
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func switchSubject(to subject: Subject, in session: Session) async throws -> Session {
        try await withCheckedThrowingContinuation { continuation in
            var cSession = CSession(
                id: nil,
                name: nil,
                session_name: nil,
                user: 0,
                is_public: false,
                qrcode: nil,
                subject: 0,
                trials_count: 0,
                created_at: nil,
                updated_at: nil
            )

            let result = session.id.withCString { sessionIdPtr in
                model_health_switch_subject(handle, sessionIdPtr, Int32(subject.id), &cSession)
            }

            if result.success {
                do {
                    let switched = try Session.from(cSession: cSession)
                    freeSessionFields(cSession)
                    continuation.resume(returning: switched)
                } catch {
                    freeSessionFields(cSession)
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    // MARK: - Filtered list streams

    func activitiesStream(
        filterJSON: String,
        orderBy: String?,
        limit: Int?
    ) -> ActivityStream {
        var stream: UnsafeMutablePointer<ModelHealthActivityStreamHandle>?
        let opened = withOptionalCString(orderBy) { orderByPtr in
            filterJSON.withCString { filterPtr in
                model_health_activities_stream_new(
                    handle, filterPtr, orderByPtr, Int64(limit ?? -1), &stream
                )
            }
        }

        guard opened.success, let stream else {
            return ActivityStream(reader: ItemReader(source: unopened(ffiError(opened))))
        }

        let source = ItemSource<Activity>(
            nextItems: {
                try await withCheckedThrowingContinuation { continuation in
                    var cArray = CTrialArray(trials: nil, count: 0)
                    var total: UInt32 = 0
                    var finished = false
                    let result = model_health_activities_stream_next(stream, &cArray, &total, &finished)
                    defer { model_health_free_trial_array(cArray) }
                    resume(continuation, result, cArray) { index, itemsPtr in
                        try Activity.from(cTrial: itemsPtr[index])
                    }
                }
            },
            readTotal: {
                try await withCheckedThrowingContinuation { continuation in
                    var total: UInt32 = 0
                    let result = model_health_activities_stream_total(stream, &total)
                    if result.success {
                        continuation.resume(returning: Int(total))
                    } else {
                        continuation.resume(throwing: ffiError(result))
                    }
                }
            },
            readAll: {
                try await withCheckedThrowingContinuation { continuation in
                    var cArray = CTrialArray(trials: nil, count: 0)
                    var total: UInt32 = 0
                    let result = model_health_activities_stream_all(stream, &cArray, &total)
                    defer { model_health_free_trial_array(cArray) }
                    resume(continuation, result, cArray) { index, itemsPtr in
                        try Activity.from(cTrial: itemsPtr[index])
                    }
                }
            },
            release: { model_health_activities_stream_free(stream) }
        )

        return ActivityStream(reader: ItemReader(source: source))
    }

    func subjectsStream(
        filterJSON: String,
        orderBy: String?,
        limit: Int?
    ) -> SubjectStream {
        var stream: UnsafeMutablePointer<ModelHealthSubjectStreamHandle>?
        let opened = withOptionalCString(orderBy) { orderByPtr in
            filterJSON.withCString { filterPtr in
                model_health_subjects_stream_new(
                    handle, filterPtr, orderByPtr, Int64(limit ?? -1), &stream
                )
            }
        }

        guard opened.success, let stream else {
            return SubjectStream(reader: ItemReader(source: unopened(ffiError(opened))))
        }

        let source = ItemSource<Subject>(
            nextItems: {
                try await withCheckedThrowingContinuation { continuation in
                    var cArray = CSubjectArray(subjects: nil, count: 0)
                    var total: UInt32 = 0
                    var finished = false
                    let result = model_health_subjects_stream_next(stream, &cArray, &total, &finished)
                    defer { model_health_free_subject_array(cArray) }
                    resume(continuation, result, cArray) { index, itemsPtr in
                        try Subject.from(cSubject: itemsPtr[index])
                    }
                }
            },
            readTotal: {
                try await withCheckedThrowingContinuation { continuation in
                    var total: UInt32 = 0
                    let result = model_health_subjects_stream_total(stream, &total)
                    if result.success {
                        continuation.resume(returning: Int(total))
                    } else {
                        continuation.resume(throwing: ffiError(result))
                    }
                }
            },
            readAll: {
                try await withCheckedThrowingContinuation { continuation in
                    var cArray = CSubjectArray(subjects: nil, count: 0)
                    var total: UInt32 = 0
                    let result = model_health_subjects_stream_all(stream, &cArray, &total)
                    defer { model_health_free_subject_array(cArray) }
                    resume(continuation, result, cArray) { index, itemsPtr in
                        try Subject.from(cSubject: itemsPtr[index])
                    }
                }
            },
            release: { model_health_subjects_stream_free(stream) }
        )

        return SubjectStream(reader: ItemReader(source: source))
    }

    func sessionsStream(
        filterJSON: String,
        orderBy: String?,
        limit: Int?
    ) -> SessionStream {
        var stream: UnsafeMutablePointer<ModelHealthSessionStreamHandle>?
        let opened = withOptionalCString(orderBy) { orderByPtr in
            filterJSON.withCString { filterPtr in
                model_health_sessions_stream_new(
                    handle, filterPtr, orderByPtr, Int64(limit ?? -1), &stream
                )
            }
        }

        guard opened.success, let stream else {
            return SessionStream(reader: ItemReader(source: unopened(ffiError(opened))))
        }

        let source = ItemSource<Session>(
            nextItems: {
                try await withCheckedThrowingContinuation { continuation in
                    var cArray = CSessionArray(sessions: nil, count: 0)
                    var total: UInt32 = 0
                    var finished = false
                    let result = model_health_sessions_stream_next(stream, &cArray, &total, &finished)
                    defer { model_health_free_session_array(cArray) }
                    resume(continuation, result, cArray) { index, itemsPtr in
                        try Session.from(cSession: itemsPtr[index])
                    }
                }
            },
            readTotal: {
                try await withCheckedThrowingContinuation { continuation in
                    var total: UInt32 = 0
                    let result = model_health_sessions_stream_total(stream, &total)
                    if result.success {
                        continuation.resume(returning: Int(total))
                    } else {
                        continuation.resume(throwing: ffiError(result))
                    }
                }
            },
            readAll: {
                try await withCheckedThrowingContinuation { continuation in
                    var cArray = CSessionArray(sessions: nil, count: 0)
                    var total: UInt32 = 0
                    let result = model_health_sessions_stream_all(stream, &cArray, &total)
                    defer { model_health_free_session_array(cArray) }
                    resume(continuation, result, cArray) { index, itemsPtr in
                        try Session.from(cSession: itemsPtr[index])
                    }
                }
            },
            release: { model_health_sessions_stream_free(stream) }
        )

        return SessionStream(reader: ItemReader(source: source))
    }

    func groupsStream(
        filterJSON: String,
        orderBy: String?,
        limit: Int?
    ) -> GroupStream {
        var stream: UnsafeMutablePointer<ModelHealthGroupStreamHandle>?
        let opened = withOptionalCString(orderBy) { orderByPtr in
            filterJSON.withCString { filterPtr in
                model_health_groups_stream_new(
                    handle, filterPtr, orderByPtr, Int64(limit ?? -1), &stream
                )
            }
        }

        guard opened.success, let stream else {
            return GroupStream(reader: ItemReader(source: unopened(ffiError(opened))))
        }

        let source = ItemSource<SubjectGroup>(
            nextItems: {
                try await withCheckedThrowingContinuation { continuation in
                    var cArray = CSubjectGroupArray(groups: nil, count: 0)
                    var total: UInt32 = 0
                    var finished = false
                    let result = model_health_groups_stream_next(stream, &cArray, &total, &finished)
                    defer { model_health_free_subject_group_array(cArray) }
                    resume(continuation, result, cArray) { index, itemsPtr in
                        try SubjectGroup.from(cSubjectGroup: itemsPtr[index])
                    }
                }
            },
            readTotal: {
                try await withCheckedThrowingContinuation { continuation in
                    var total: UInt32 = 0
                    let result = model_health_groups_stream_total(stream, &total)
                    if result.success {
                        continuation.resume(returning: Int(total))
                    } else {
                        continuation.resume(throwing: ffiError(result))
                    }
                }
            },
            readAll: {
                try await withCheckedThrowingContinuation { continuation in
                    var cArray = CSubjectGroupArray(groups: nil, count: 0)
                    var total: UInt32 = 0
                    let result = model_health_groups_stream_all(stream, &cArray, &total)
                    defer { model_health_free_subject_group_array(cArray) }
                    resume(continuation, result, cArray) { index, itemsPtr in
                        try SubjectGroup.from(cSubjectGroup: itemsPtr[index])
                    }
                }
            },
            release: { model_health_groups_stream_free(stream) }
        )

        return GroupStream(reader: ItemReader(source: source))
    }

    func fetch(subject subjectId: Int) async throws -> Subject {
        try await withCheckedThrowingContinuation { continuation in
            var cSubject = CSubject.emptySubject()

            let result = model_health_fetch_subject(handle, Int32(subjectId), &cSubject)

            if result.success {
                do {
                    let subject = try Subject.from(cSubject: cSubject)
                    freeSubjectFields(cSubject)
                    continuation.resume(returning: subject)
                } catch {
                    freeSubjectFields(cSubject)
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func activityList(for session: Session) async throws -> [Activity] {
        try await withCheckedThrowingContinuation { continuation in
            var cArray = CTrialArray(trials: nil, count: 0)
            let result = session.id.withCString { sessionId in
                model_health_trial_list_for_session(handle, sessionId, &cArray)
            }

            defer {
                model_health_free_trial_array(cArray)
            }

            if result.success {
                do {
                    var trials: [Activity] = []
                    if cArray.count > 0, let trialsPtr = cArray.trials {
                        trials = try (0..<Int(cArray.count)).map { index in
                            try Activity.from(cTrial: trialsPtr[index])
                        }
                    }
                    continuation.resume(returning: trials)
                } catch {
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func fetch(activity activityId: String) async throws -> Activity {
        try await withCheckedThrowingContinuation { continuation in
            var cTrial = CTrial.emptyTrial()

            let result = activityId.withCString { activityIdPtr in
                model_health_fetch_activity(handle, activityIdPtr, &cTrial)
            }

            if result.success {
                do {
                    let activity = try Activity.from(cTrial: cTrial)
                    continuation.resume(returning: activity)
                } catch {
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func update(activity: Activity, config: ActivityConfig? = nil) async throws -> Activity {
        try await withCheckedThrowingContinuation { continuation in
            var cTrial = CTrial.emptyTrial()
            let nameString: String? = config?.name

            let addTagsJsonString: String? = {
                guard let tags = config?.addTags, !tags.isEmpty else {
                    return nil
                }

                guard
                    let data = try? JSONSerialization.data(withJSONObject: tags),
                    let str = String(data: data, encoding: .utf8)
                else {
                    return nil
                }

                return str
            }()

            let removeTagsJsonString: String? = {
                guard let tags = config?.removeTags, !tags.isEmpty else {
                    return nil
                }

                guard
                    let data = try? JSONSerialization.data(withJSONObject: tags),
                    let str = String(data: data, encoding: .utf8)
                else {
                    return nil
                }

                return str
            }()

            let result = activity.id.withCString { activityIdPtr in
                let callFFI = { (namePtr: UnsafePointer<CChar>?) -> FFIResult in
                    let callFFIWithAddTags = { (addTagsPtr: UnsafePointer<CChar>?) -> FFIResult in
                        if let removeTagsJson = removeTagsJsonString {
                            return removeTagsJson.withCString { removeTagsPtr in
                                model_health_update_activity(
                                    self.handle,
                                    activityIdPtr,
                                    namePtr,
                                    addTagsPtr,
                                    removeTagsPtr,
                                    &cTrial
                                )
                            }
                        }

                        return model_health_update_activity(
                            self.handle,
                            activityIdPtr,
                            namePtr,
                            addTagsPtr,
                            nil,
                            &cTrial
                        )
                    }
                    if let addTagsJson = addTagsJsonString {
                        return addTagsJson.withCString { addTagsPtr in callFFIWithAddTags(addTagsPtr) }
                    }
                    return callFFIWithAddTags(nil)
                }
                if let name = nameString {
                    return name.withCString { namePtr in callFFI(namePtr) }
                }
                return callFFI(nil)
            }

            if result.success {
                do {
                    let updatedActivity = try Activity.from(cTrial: cTrial)
                    continuation.resume(returning: updatedActivity)
                } catch {
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func delete(activity: Activity) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let result = activity.id.withCString { activityIdPtr in
                model_health_delete_activity(handle, activityIdPtr)
            }

            handleFFIResult(result, continuation: continuation)
        }
    }

    func activityTypes() async throws -> [ActivityTypeInfo] {
        try await withCheckedThrowingContinuation { continuation in
            var cArray = CActivityTypeInfoArray(types: nil, count: 0)
            let result = model_health_activity_types(handle, &cArray)

            defer {
                model_health_free_activity_type_array(cArray)
            }

            if result.success {
                var types: [ActivityTypeInfo] = []
                if cArray.count > 0, let typesPtr = cArray.types {
                    types = (0..<Int(cArray.count)).map { index in
                        let t = typesPtr[index]
                        return ActivityTypeInfo(
                            id: Int(t.id),
                            name: t.name.map { String(cString: $0) } ?? "",
                            displayName: t.display_name.map { String(cString: $0) } ?? "",
                            slug: t.slug.map { String(cString: $0) } ?? "",
                            description: t.description.map { String(cString: $0) },
                            isCustom: t.is_custom
                        )
                    }
                }
                continuation.resume(returning: types)
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func activityTags() async throws -> [ActivityTag] {
        try await withCheckedThrowingContinuation { continuation in
            var cArray = CActivityTagArray(tags: nil, count: 0)
            let result = model_health_activity_tags(handle, &cArray)

            defer {
                model_health_free_activity_tag_array(cArray)
            }

            if result.success {
                do {
                    var tags: [ActivityTag] = []
                    if cArray.count > 0, let tagsPtr = cArray.tags {
                        tags = try (0..<Int(cArray.count)).map { index in
                            try ActivityTag.from(cTag: tagsPtr[index])
                        }
                    }
                    continuation.resume(returning: tags)
                } catch {
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func videos(for trial: Activity, version: VideoVersion) async -> [Data] {
        await withCheckedContinuation { continuation in
            var cArray = CDataArray(items: nil, count: 0)

            let versionCode: Int32 = version == .raw ? 0 : 1

            let result = trial.id.withCString { trialId in
                trial.session.withCString { sessionId in
                    model_health_download_trial_videos(
                        handle,
                        trialId,
                        sessionId,
                        versionCode,
                        &cArray
                    )
                }
            }

            defer {
                model_health_free_data_array(cArray)
            }

            if result.success, cArray.count > 0, let itemsPtr = cArray.items {
                let dataArray = (0..<Int(cArray.count)).compactMap { index -> Data? in
                    let item = itemsPtr[index]
                    guard let dataPtr = item.data, item.length > 0 else {
                        return nil
                    }

                    return Data(bytes: dataPtr, count: Int(item.length))
                }
                continuation.resume(returning: dataArray)
            } else {
                continuation.resume(returning: [])
            }
        }
    }

    func motionData(ofType types: Set<MotionDataType>, for trial: Activity) async -> [MotionData] {
        await withCheckedContinuation { continuation in
            guard !types.isEmpty else {
                continuation.resume(returning: [])
                return
            }

            let standardTypes = types.filter {
                if case .tagged = $0 {
                    return false
                }
                return true
            }
            let taggedTypes: [(String, String)] = types.compactMap {
                if case let .tagged(tag, fileExtension) = $0 {
                    return (tag, fileExtension)
                }
                return nil
            }

            var allResults: [MotionData] = []

            if !standardTypes.isEmpty {
                let typeCodes: [Int32] = standardTypes.map(\.cValue)
                var cArray = CMotionDataArray(items: nil, count: 0)

                let result = trial.id.withCString { trialId in
                    trial.session.withCString { sessionId in
                        typeCodes.withUnsafeBufferPointer { buffer in
                            guard let baseAddress = buffer.baseAddress else {
                                return FFIResult(
                                    success: false,
                                    error_code: -1,
                                    error_sub_code: -1,
                                    error_status_code: 0,
                                    error_message: nil
                                )
                            }

                            return model_health_download_trial_result_data(
                                handle,
                                trialId,
                                sessionId,
                                baseAddress,
                                UInt(typeCodes.count),
                                &cArray
                            )
                        }
                    }
                }

                if result.success, cArray.count > 0, let itemsPtr = cArray.items {
                    let fetched: [MotionData] = (0..<Int(cArray.count)).compactMap { index in
                        let item = itemsPtr[index]
                        guard
                            let dataType = MotionDataType(cValue: item.data_type),
                            let dataPtr = item.data,
                            item.length > 0
                        else {
                            return nil
                        }
                        return MotionData(type: dataType, data: Data(bytes: dataPtr, count: Int(item.length)))
                    }
                    allResults.append(contentsOf: fetched)
                }
                model_health_free_result_data_array(cArray)
            }

            for (tag, fileExtension) in taggedTypes {
                var cData = CData(data: nil, length: 0)

                let result = trial.id.withCString { trialId in
                    trial.session.withCString { sessionId in
                        tag.withCString { tagPtr in
                            model_health_download_tagged_result_data(
                                handle,
                                trialId,
                                sessionId,
                                tagPtr,
                                &cData
                            )
                        }
                    }
                }

                if result.success, cData.length > 0, let dataPtr = cData.data {
                    let motionData = MotionData(
                        type: .tagged(tag, fileExtension),
                        data: Data(bytes: dataPtr, count: Int(cData.length))
                    )
                    allResults.append(motionData)
                }
                model_health_free_data(cData)
            }

            continuation.resume(returning: allResults)
        }
    }

    func addMotionData(
        _ files: [ExternalResultFile],
        to trial: Activity
    ) async throws -> Activity {
        try await withCheckedThrowingContinuation { continuation in
            guard !files.isEmpty else {
                continuation.resume(throwing: ModelHealthError.internalError("files array must not be empty"))
                return
            }

            var dataPtrs: [UnsafeMutablePointer<UInt8>] = []
            var tagPtrs: [UnsafeMutablePointer<CChar>] = []
            var extPtrs: [UnsafeMutablePointer<CChar>] = []

            defer {
                dataPtrs.forEach { $0.deallocate() }
                tagPtrs.forEach { $0.deallocate() }
                extPtrs.forEach { $0.deallocate() }
            }

            let cFiles: [CExternalResultFile] = files.map {
                makeCExternalResultFile(from: $0, dataPtrs: &dataPtrs, tagPtrs: &tagPtrs, extPtrs: &extPtrs)
            }

            var cTrial = CTrial.emptyTrial()

            let result = trial.id.withCString { trialId in
                trial.session.withCString { sessionId in
                    cFiles.withUnsafeBufferPointer { buffer in
                        guard let baseAddress = buffer.baseAddress else {
                            return FFIResult(
                                success: false,
                                error_code: -1,
                                error_sub_code: -1,
                                error_status_code: 0,
                                error_message: nil
                            )
                        }

                        return model_health_add_motion_data_to_activity(
                            handle,
                            trialId,
                            sessionId,
                            baseAddress,
                            UInt(cFiles.count),
                            &cTrial
                        )
                    }
                }
            }

            defer {
                freeTrialFields(cTrial)
            }

            if result.success {
                do {
                    let activity = try Activity.from(cTrial: cTrial)
                    continuation.resume(returning: activity)
                } catch {
                    continuation.resume(throwing: error)
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func analysisData(
        ofType types: Set<AnalysisDataType>,
        for trial: Activity
    ) async -> [AnalysisData] {
        await withCheckedContinuation { continuation in
            let typeCodes: [Int32] = types.map(\.cValue)

            guard !typeCodes.isEmpty else {
                continuation.resume(returning: [])
                return
            }

            var cArray = CAnalysisDataArray(items: nil, count: 0)

            let result = trial.id.withCString { trialId in
                trial.session.withCString { sessionId in
                    typeCodes.withUnsafeBufferPointer { buffer in
                        guard let baseAddress = buffer.baseAddress else {
                            return FFIResult(
                                success: false,
                                error_code: -1,
                                error_sub_code: -1,
                                error_status_code: 0,
                                error_message: nil
                            )
                        }

                        return model_health_download_trial_analysis_result_data(
                            handle,
                            trialId,
                            sessionId,
                            baseAddress,
                            UInt(typeCodes.count),
                            &cArray
                        )
                    }
                }
            }

            defer {
                model_health_free_analysis_result_data_array(cArray)
            }

            guard result.success, cArray.count > 0, let itemsPtr = cArray.items else {
                continuation.resume(returning: [])
                return
            }

            let results: [AnalysisData] = (0..<Int(cArray.count)).compactMap { index in
                let item = itemsPtr[index]
                guard
                    let dataType = AnalysisDataType(cValue: item.data_type),
                    let dataPtr = item.data,
                    item.length > 0
                else {
                    return nil
                }

                return AnalysisData(type: dataType, data: Data(bytes: dataPtr, count: Int(item.length)))
            }

            continuation.resume(returning: results)
        }
    }

    // MARK: - Create Operations

    func createSession() async throws -> Session {
        try await withCheckedThrowingContinuation { continuation in
            var cSession = CSession(
                id: nil,
                name: nil,
                session_name: nil,
                user: 0,
                is_public: false,
                qrcode: nil,
                subject: 0,
                trials_count: 0,
                created_at: nil,
                updated_at: nil
            )
            let result = model_health_create_session(handle, &cSession)

            if result.success {
                do {
                    let session = try Session.from(cSession: cSession)
                    freeSessionFields(cSession)
                    continuation.resume(returning: session)
                } catch {
                    freeSessionFields(cSession)
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func configure(session: Session, config: SessionConfig) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let result = session.id.withCString { sessionIdPtr in
                model_health_configure_session(
                    handle,
                    sessionIdPtr,
                    config.framerate.cValue,
                    config.opensimModel.cValue,
                    config.scalingSetup.cValue,
                    config.coreEngine.cValue,
                    config.filterFrequency.cValue,
                    config.dataSharing.cValue
                )
            }

            if result.success {
                continuation.resume()
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func createSubject(parameters: SubjectParameters) async throws -> Subject {
        try await withCheckedThrowingContinuation { continuation in
            var cSubject = CSubject.emptySubject()

            let result = parameters.name.withCString { name in
                model_health_create_subject(
                    handle,
                    name,
                    parameters.weight,
                    parameters.height,
                    parameters.birthYear.map(Int32.init) ?? -1,
                    parameters.sexAtBirth.cValue,
                    parameters.gender.cValue,
                    &cSubject
                )
            }

            if result.success {
                do {
                    let subject = try Subject.from(cSubject: cSubject)
                    freeSubjectFields(cSubject)
                    continuation.resume(returning: subject)
                } catch {
                    freeSubjectFields(cSubject)
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    // MARK: - Recording Operations

    func startRecording(activityNamed name: String, in session: Session, config: ActivityConfig? = nil) async throws -> Activity {
        try await withCheckedThrowingContinuation { continuation in
            var cTrial = CTrial.emptyTrial()
            let cActivityType: Int32 = config?.activityType?.cValue ?? -1
            let cFramerate: Int32 = config?.config?.framerate.map(\.cValue) ?? -1
            let cFilterFrequency: Int32 = config?.config?.filterFrequency.map(\.cValue) ?? -1

            let addTagsJsonString: String? = {
                guard let tags = config?.addTags, !tags.isEmpty else {
                    return nil
                }

                guard
                    let data = try? JSONSerialization.data(withJSONObject: tags),
                    let str = String(data: data, encoding: .utf8)
                else {
                    return nil
                }

                return str
            }()

            let result = name.withCString { trialName in
                session.id.withCString { sessionId in
                    if let tagsJson = addTagsJsonString {
                        return tagsJson.withCString { tagsPtr in
                            model_health_start_recording(
                                handle,
                                trialName,
                                sessionId,
                                cActivityType,
                                cFramerate,
                                cFilterFrequency,
                                tagsPtr,
                                &cTrial
                            )
                        }
                    }

                    return model_health_start_recording(
                        handle,
                        trialName,
                        sessionId,
                        cActivityType,
                        cFramerate,
                        cFilterFrequency,
                        nil,
                        &cTrial
                    )
                }
            }

            if result.success {
                do {
                    let trial = try Activity.from(cTrial: cTrial)
                    freeTrialFields(cTrial)
                    continuation.resume(returning: trial)
                } catch {
                    freeTrialFields(cTrial)
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func stopRecording(_ session: Session) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let result = session.id.withCString { sessionId in
                model_health_stop_recording(handle, sessionId)
            }

            handleFFIResult(result, continuation: continuation)
        }
    }

    // MARK: - Calibration Operations

    func calibrateCamera(
        _ session: Session,
        checkerboardDetails: CheckerboardDetails,
        statusUpdate: @escaping @Sendable (CalibrationStatus) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = CallbackContext(
                statusUpdate: statusUpdate,
                continuation: continuation
            )
            let contextPtr = Unmanaged.passRetained(context).toOpaque()

            let result = session.id.withCString { sessionId in
                model_health_calibrate_camera(
                    handle,
                    sessionId,
                    Int32(checkerboardDetails.rows),
                    Int32(checkerboardDetails.columns),
                    Int32(checkerboardDetails.squareSize),
                    checkerboardDetails.placement.cValue,
                    { userDataPtr, statusJsonPtr in
                        guard
                            let userDataPtr = userDataPtr,
                            let statusJsonPtr = statusJsonPtr
                        else {
                            return
                        }

                        let context = Unmanaged<CallbackContext<CalibrationStatus>>.fromOpaque(userDataPtr)
                            .takeUnretainedValue()
                        let jsonString = String(cString: statusJsonPtr)

                        do {
                            let status = try CalibrationStatus.from(jsonString: jsonString)
                            context.statusUpdate(status)
                        } catch {
                            // Ignore parsing errors in callback
                        }
                    },
                    contextPtr
                )
            }

            Unmanaged<CallbackContext<CalibrationStatus>>.fromOpaque(contextPtr).release()

            handleFFIResult(result, continuation: continuation)
        }
    }

    func calibrateSubject(
        _ subject: Subject,
        in session: Session,
        statusUpdate: @escaping @Sendable (CalibrationStatus) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = CallbackContext(
                statusUpdate: statusUpdate,
                continuation: continuation
            )
            let contextPtr = Unmanaged.passRetained(context).toOpaque()

            let result = session.id.withCString { sessionId in
                model_health_calibrate_subject(
                    handle,
                    sessionId,
                    Int32(subject.id),
                    { userDataPtr, statusJsonPtr in
                        guard
                            let userDataPtr = userDataPtr,
                            let statusJsonPtr = statusJsonPtr
                        else {
                            return
                        }

                        let context = Unmanaged<CallbackContext<CalibrationStatus>>.fromOpaque(userDataPtr)
                            .takeUnretainedValue()
                        let jsonString = String(cString: statusJsonPtr)

                        do {
                            let status = try CalibrationStatus.from(jsonString: jsonString)
                            context.statusUpdate(status)
                        } catch {
                            // Ignore parsing errors in callback
                        }
                    },
                    contextPtr
                )
            }

            Unmanaged<CallbackContext<CalibrationStatus>>.fromOpaque(contextPtr).release()
            handleFFIResult(result, continuation: continuation)
        }
    }

    // MARK: - Import Operations

    func importSession(
        _ activitiesJson: String,
        subject: Subject,
        config: SessionConfig,
        statusUpdate: @escaping @Sendable (ImportStatus) -> Void
    ) async throws -> Session {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Session, Error>) in
            let context = CallbackContext(
                statusUpdate: statusUpdate,
                continuation: continuation
            )
            let contextPtr = Unmanaged.passRetained(context).toOpaque()

            var cSession = CSession(
                id: nil,
                name: nil,
                session_name: nil,
                user: 0,
                is_public: false,
                qrcode: nil,
                subject: 0,
                trials_count: 0,
                created_at: nil,
                updated_at: nil
            )

            let result: FFIResult = activitiesJson.withCString { activitiesJsonPtr in
                model_health_import_session(
                    handle,
                    activitiesJsonPtr,
                    Int32(subject.id),
                    config.framerate.cValue,
                    config.opensimModel.cValue,
                    config.scalingSetup.cValue,
                    config.coreEngine.cValue,
                    config.filterFrequency.cValue,
                    config.dataSharing.cValue,
                    { userDataPtr, statusJsonPtr in
                        guard let userDataPtr, let statusJsonPtr else {
                            return
                        }
                        let ctx = Unmanaged<CallbackContext<ImportStatus>>
                            .fromOpaque(userDataPtr).takeUnretainedValue()
                        if let status = try? ImportStatus.from(
                            jsonString: String(cString: statusJsonPtr)
                        ) {
                            ctx.statusUpdate(status)
                        }
                    },
                    contextPtr,
                    &cSession
                )
            }

            Unmanaged<CallbackContext<ImportStatus>>.fromOpaque(contextPtr).release()

            if result.success {
                do {
                    let completedSession = try Session.from(cSession: cSession)
                    freeSessionFields(cSession)
                    continuation.resume(returning: completedSession)
                } catch {
                    freeSessionFields(cSession)
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    // MARK: - Analysis Operations

    func activityStatus(for activity: Activity) async throws -> ActivityStatus {
        try await withCheckedThrowingContinuation { continuation in
            var statusCode: Int32 = -1
            var uploaded: Int32 = 0
            var total: Int32 = 0
            var cTask = CAnalysis(task_id: nil)

            let result = activity.id.withCString { trialId in
                activity.session.withCString { sessionId in
                    model_health_activity_status(
                        handle,
                        trialId,
                        sessionId,
                        &statusCode,
                        &uploaded,
                        &total,
                        &cTask
                    )
                }
            }

            if result.success {
                let status = ActivityStatus.from(
                    statusCode: statusCode,
                    uploaded: uploaded,
                    total: total,
                    analysisTask: cTask
                )
                if let taskId = cTask.task_id {
                    model_health_free_string(taskId)
                }
                continuation.resume(returning: status)
            } else {
                if let taskId = cTask.task_id {
                    model_health_free_string(taskId)
                }
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func startAnalysis(
        _ activityType: ActivityType,
        for trial: Activity,
        in session: Session
    ) async throws -> Analysis {
        try await withCheckedThrowingContinuation { continuation in
            guard let trialName = trial.name else {
                continuation.resume(
                    throwing: ModelHealthError.internalError("Trial name is required for analysis")
                )
                return
            }

            var cTask = CAnalysis(task_id: nil)

            let result = trial.id.withCString { trialId in
                session.id.withCString { sessionId in
                    model_health_start_analysis(
                        handle,
                        activityType.cValue,
                        trialId,
                        trialName,
                        sessionId,
                        &cTask
                    )
                }
            }

            if result.success {
                do {
                    let task = try Analysis.from(cTask: cTask)
                    if let taskId = cTask.task_id {
                        model_health_free_string(taskId)
                    }
                    continuation.resume(returning: task)
                } catch {
                    if let taskId = cTask.task_id {
                        model_health_free_string(taskId)
                    }
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func analysisStatus(for task: Analysis) async throws -> AnalysisStatus {
        try await withCheckedThrowingContinuation { continuation in
            var statusCode: Int32 = -1

            let result = task.id.withCString { taskId in
                model_health_analysis_status(handle, taskId, &statusCode)
            }

            if result.success {
                do {
                    let status = try AnalysisStatus.from(statusCode: statusCode)
                    continuation.resume(returning: status)
                } catch {
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    // MARK: - Archive Operations

    func prepareArchive(for session: Session, withVideos: Bool) async throws -> Archive {
        try await withCheckedThrowingContinuation { continuation in
            var cArchive = CArchive(archive_id: nil)

            let result = session.id.withCString { sessionId in
                model_health_prepare_archive(handle, sessionId, withVideos ? 1 : 0, &cArchive)
            }

            if result.success {
                do {
                    let archive = try Archive.from(cArchive: cArchive)
                    model_health_free_archive(cArchive)
                    continuation.resume(returning: archive)
                } catch {
                    model_health_free_archive(cArchive)
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func archiveStatus(for archive: Archive) async throws -> ArchiveStatus {
        try await withCheckedThrowingContinuation { continuation in
            var statusCode: Int32 = -1

            let result = archive.id.withCString { archiveId in
                model_health_archive_status(handle, archiveId, &statusCode)
            }

            if result.success {
                do {
                    let status = try ArchiveStatus.from(statusCode: statusCode)
                    continuation.resume(returning: status)
                } catch {
                    continuation.resume(
                        throwing: ModelHealthError.internalError(error.localizedDescription)
                    )
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func archiveData(for archive: Archive) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            var cData = CData(data: nil, length: 0)

            let result = archive.id.withCString { archiveId in
                model_health_archive_data(handle, archiveId, &cData)
            }

            if result.success {
                if let dataPtr = cData.data, cData.length > 0 {
                    let data = Data(bytes: dataPtr, count: Int(cData.length))
                    model_health_free_data(cData)
                    continuation.resume(returning: data)
                } else {
                    model_health_free_data(cData)
                    continuation.resume(returning: Data())
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    // MARK: - Metrics Operations

    func activityMetrics(for activityId: String) async throws -> ActivityMetrics? {
        try await withCheckedThrowingContinuation { continuation in
            var cMetrics = CActivityMetrics(
                activity_id: nil,
                activity_type_id: 0,
                groups: CMetricsGroupArray(items: nil, count: 0)
            )

            let result = activityId.withCString { activityIdPtr in
                model_health_activity_metrics(handle, activityIdPtr, &cMetrics)
            }

            if result.success {
                guard cMetrics.activity_id != nil else {
                    continuation.resume(returning: nil)
                    return
                }
                do {
                    let metrics = try ActivityMetrics.from(cMetrics: cMetrics)
                    model_health_free_activity_metrics(cMetrics)
                    continuation.resume(returning: metrics)
                } catch {
                    model_health_free_activity_metrics(cMetrics)
                    continuation.resume(throwing: error)
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    func subjectMetrics(forSubject subjectId: Int, start: Date?, end: Date?) async throws -> [ActivityMetrics] {
        let startStr = start.map { metricDateFormatter.string(from: $0) }
        let endStr = end.map { metricDateFormatter.string(from: $0) }

        return try await withCheckedThrowingContinuation { continuation in
            var cArray = CActivityMetricsArray(items: nil, count: 0)

            func callFFI(startPtr: UnsafePointer<CChar>?, endPtr: UnsafePointer<CChar>?) -> FFIResult {
                model_health_subject_metrics(handle, Int32(subjectId), startPtr, endPtr, &cArray)
            }

            let result: FFIResult
            switch (startStr, endStr) {
            case (let startValue?, let endValue?):
                result = startValue.withCString { startPtr in
                    endValue.withCString { endPtr in
                        callFFI(startPtr: startPtr, endPtr: endPtr)
                    }
                }

            case (let startValue?, nil):
                result = startValue.withCString { startPtr in
                    callFFI(startPtr: startPtr, endPtr: nil)
                }

            case (nil, let endValue?):
                result = endValue.withCString { endPtr in
                    callFFI(startPtr: nil, endPtr: endPtr)
                }

            case (nil, nil):
                result = callFFI(startPtr: nil, endPtr: nil)
            }

            if result.success {
                do {
                    var allMetrics: [ActivityMetrics] = []
                    if cArray.count > 0, let itemsPtr = cArray.items {
                        allMetrics = try (0..<Int(cArray.count)).map { index in
                            try ActivityMetrics.from(cMetrics: itemsPtr[index])
                        }
                    }
                    model_health_free_activity_metrics_array(cArray)
                    continuation.resume(returning: allMetrics)
                } catch {
                    model_health_free_activity_metrics_array(cArray)
                    continuation.resume(throwing: error)
                }
            } else {
                handleFFIError(result, continuation: continuation)
            }
        }
    }

    // MARK: - Profile Operations

    func setVideoUploadMode(_ mode: VideoUploadMode) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let result = model_health_set_video_upload_mode(handle, mode.cValue)

            handleFFIResult(result, continuation: continuation)
        }
    }

    // MARK: - Logging

    func setLogLevel(_ level: LogLevel) throws {
        let result = model_health_set_log_level(handle, level.cValue)

        if !result.success {
            throw makeError(from: result)
        }
    }

    func setLogHandler(level: LogLevel, _ handler: (@Sendable (LogEvent) -> Void)?) throws {
        let isRegistering = handler != nil
        let newContext = handler.map { LogHandlerContext(handler: $0) }
        let newContextPtr = newContext.map { Unmanaged.passRetained($0).toOpaque() }

        let result: FFIResult
        if isRegistering {
            result = model_health_set_log_handler(
                handle,
                { userDataPtr, eventJsonPtr in
                    guard
                        let userDataPtr = userDataPtr,
                        let eventJsonPtr = eventJsonPtr
                    else {
                        return
                    }

                    let context = Unmanaged<LogHandlerContext>.fromOpaque(userDataPtr)
                        .takeUnretainedValue()
                    let jsonString = String(cString: eventJsonPtr)

                    do {
                        let event = try LogEvent.from(jsonString: jsonString)
                        context.handler(event)
                    } catch {
                        // Ignore parsing errors in callback
                    }
                },
                newContextPtr,
                level.cValue
            )
        } else {
            result = model_health_set_log_handler(handle, nil, nil, level.cValue)
        }

        guard result.success else {
            // Registration failed — release what was just retained; nothing was swapped in.
            if let newContextPtr = newContextPtr {
                Unmanaged<LogHandlerContext>.fromOpaque(newContextPtr).release()
            }
            throw makeError(from: result)
        }

        // Only release the old context once the FFI swap has succeeded.
        if let oldContextPtr = logHandlerContextPtr {
            Unmanaged<LogHandlerContext>.fromOpaque(oldContextPtr).release()
        }
        logHandlerContextPtr = newContextPtr
    }
}
// swiftlint:enable type_body_length

// MARK: - FFI Error Decoding

extension ModelHealthError {
    /// Reconstructs the exact `ModelHealthError` case.
    ///
    /// Falls back to `.internalError(message)` for ad hoc validation strings
    /// (`code == -1`) and for any code/sub-code this version of the SDK doesn't recognize.
    static func from(code: Int32, subCode: Int32, statusCode: UInt16, message: String) -> ModelHealthError {
        switch code {
        case 0:
            return calibrationError(subCode: subCode, message: message)

        case 1:
            return httpError(subCode: subCode, statusCode: Int(statusCode), message: message)

        case 2:
            return .url(URLError.Code(rawValue: Int(subCode)))

        case 3:
            return .unexpectedResponse

        case 7:
            return .notSupported

        default: // InternalError, InvalidApiKey, InvalidInput, or an unrecognized code
            return .internalError(message)
        }
    }

    private static func calibrationError(subCode: Int32, message: String) -> ModelHealthError {
        switch subCode {
        case 0:
            return .calibration(.notEnoughCameras)

        case 1:
            return .calibration(.calibrationFailed)

        default:
            return .internalError(message)
        }
    }

    private static func httpError(subCode: Int32, statusCode: Int, message: String) -> ModelHealthError {
        switch subCode {
        case 0:
            return .http(.clientError(statusCode: statusCode))

        case 1:
            return .http(.serverError(statusCode: statusCode))

        case 2:
            return .http(.unexpectedStatusCode(statusCode: statusCode))

        default:
            return .internalError(message)
        }
    }
}

// MARK: - Helper Methods

private extension ModelHealthProviderImpl {
    static func currentOSVersion() -> String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    func handleFFIResult(
        _ result: FFIResult,
        continuation: CheckedContinuation<Void, Error>
    ) {
        if result.success {
            continuation.resume()
        } else {
            handleFFIError(result, continuation: continuation)
        }
    }

    func handleFFIError<T>(
        _ result: FFIResult,
        continuation: CheckedContinuation<T, Error>
    ) {
        continuation.resume(throwing: makeError(from: result))
    }

    func makeError(from result: FFIResult) -> ModelHealthError {
        let message: String
        if let errorMessage = result.error_message {
            message = String(cString: errorMessage)
            model_health_free_error(errorMessage)
        } else {
            message = "Unknown error"
        }

        return ModelHealthError.from(
            code: result.error_code,
            subCode: result.error_sub_code,
            statusCode: result.error_status_code,
            message: message
        )
    }

    func freeSessionFields(_ session: CSession) {
        session.id.map { model_health_free_string($0) }
        session.name.map { model_health_free_string($0) }
        session.session_name.map { model_health_free_string($0) }
        session.qrcode.map { model_health_free_string($0) }
        session.created_at.map { model_health_free_string($0) }
        session.updated_at.map { model_health_free_string($0) }
    }

    func freeSubjectFields(_ subject: CSubject) {
        subject.name.map { model_health_free_string($0) }
        subject.characteristics.map { model_health_free_string($0) }
        subject.first_name.map { model_health_free_string($0) }
        subject.last_name.map { model_health_free_string($0) }
        subject.tags.map { model_health_free_string($0) }
        subject.last_activity.map { model_health_free_string($0) }
        subject.created_at.map { model_health_free_string($0) }
        subject.updated_at.map { model_health_free_string($0) }
    }

    func freeTrialFields(_ trial: CTrial) {
        trial.id.map { model_health_free_string($0) }
        trial.session.map { model_health_free_string($0) }
        trial.name.map { model_health_free_string($0) }
        trial.status.map { model_health_free_string($0) }
        trial.tags.map { model_health_free_string($0) }
        trial.created_at.map { model_health_free_string($0) }
        trial.updated_at.map { model_health_free_string($0) }
        trial.activity_type_name.map { model_health_free_string($0) }
        trial.activity_type_display_name.map { model_health_free_string($0) }
        trial.notes.map { model_health_free_string($0) }
        trial.created_by.map { model_health_free_string($0) }
        trial.analysis_status.map { model_health_free_string($0) }
        model_health_free_video_array(trial.videos)
        model_health_free_trial_result_array(trial.results)
    }

    func makeCExternalResultFile(
        from file: ExternalResultFile,
        dataPtrs: inout [UnsafeMutablePointer<UInt8>],
        tagPtrs: inout [UnsafeMutablePointer<CChar>],
        extPtrs: inout [UnsafeMutablePointer<CChar>]
    ) -> CExternalResultFile {
        let dataPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: file.data.count)
        file.data.copyBytes(to: dataPtr, count: file.data.count)
        dataPtrs.append(dataPtr)

        let tagCString = file.tag.utf8CString
        let tagPtr = UnsafeMutablePointer<CChar>.allocate(capacity: tagCString.count)
        tagCString.withUnsafeBufferPointer { buf in
            guard let baseAddress = buf.baseAddress else {
                return
            }
            tagPtr.initialize(from: baseAddress, count: tagCString.count)
        }
        tagPtrs.append(tagPtr)

        let extCString = file.fileExtension.utf8CString
        let extPtr = UnsafeMutablePointer<CChar>.allocate(capacity: extCString.count)
        extCString.withUnsafeBufferPointer { buf in
            guard let baseAddress = buf.baseAddress else {
                return
            }
            extPtr.initialize(from: baseAddress, count: extCString.count)
        }
        extPtrs.append(extPtr)

        return CExternalResultFile(
            data_type: -1,
            tag: UnsafePointer(tagPtr),
            file_extension: UnsafePointer(extPtr),
            data: UnsafePointer(dataPtr),
            data_len: UInt(file.data.count)
        )
    }
}

private extension CSubject {
    /// A zeroed buffer for the C layer to write a subject into. Numeric fields carry
    /// the sentinel that stands for an absent value, so a partially written struct
    /// decodes as "not reported" rather than as real data.
    static func emptySubject() -> CSubject {
        return CSubject(
            id: 0,
            name: nil,
            weight: 0,
            height: 0,
            age: -1,
            birth_year: 0,
            gender: -1,
            sex_at_birth: -1,
            characteristics: nil,
            first_name: nil,
            last_name: nil,
            tags: nil,
            activity_count: -1,
            last_activity: nil,
            created_at: nil,
            updated_at: nil
        )
    }
}

private extension CTrial {
    static func emptyTrial() -> CTrial {
        return CTrial(
            id: nil,
            session: nil,
            name: nil,
            status: nil,
            videos: CVideoArray(videos: nil, count: 0),
            results: CTrialResultArray(results: nil, count: 0),
            tags: nil,
            created_at: nil,
            updated_at: nil,
            activity_type_id: -1,
            activity_type_name: nil,
            activity_type_slug: nil,
            activity_type_display_name: nil,
            notes: nil,
            created_by: nil,
            analysis_status: nil,
            trashed: false
        )
    }
}

// MARK: - Callback Context

private class CallbackContext<T>: @unchecked Sendable {
    let statusUpdate: @Sendable (T) -> Void
    let continuation: Any

    init(statusUpdate: @escaping @Sendable (T) -> Void, continuation: Any) {
        self.statusUpdate = statusUpdate
        self.continuation = continuation
    }
}

/// Unlike `CallbackContext` above, this is retained for as long as a log handler stays
/// registered rather than just for the duration of one synchronous FFI call — see
/// `ModelHealthProviderImpl.setLogHandler(level:_:)`.
private class LogHandlerContext: @unchecked Sendable {
    let handler: @Sendable (LogEvent) -> Void

    init(handler: @escaping @Sendable (LogEvent) -> Void) {
        self.handler = handler
    }
}

// MARK: - Stream helpers

/// Turns a failed FFI result into the error it describes, freeing its message.
private func ffiError(_ result: FFIResult) -> ModelHealthError {
    let message: String
    if let errorMessage = result.error_message {
        message = String(cString: errorMessage)
        model_health_free_error(errorMessage)
    } else {
        message = "Unknown error"
    }
    return ModelHealthError.from(
        code: result.error_code,
        subCode: result.error_sub_code,
        statusCode: result.error_status_code,
        message: message
    )
}

/// A source for a list that could not be opened: every read reports why.
///
/// Opening is deliberately not a throwing call — `list(...)` returns a sequence without
/// sending anything, and the sort field is a typed enum, so the only way opening can fail is
/// an internal one. Reporting it at the first read keeps `list(...)` free of `try`.
private func unopened<Element>(_ error: ModelHealthError) -> ItemSource<Element> {
    ItemSource(
        nextItems: { throw error },
        readTotal: { throw error },
        readAll: { throw error },
        release: {}
    )
}

/// Resumes `continuation` with the models decoded from a chunk, or with the reason it failed.
private func resume<Element, CArray, CItem>(
    _ continuation: CheckedContinuation<[Element], Error>,
    _ result: FFIResult,
    _ array: CArray,
    convert: (Int, UnsafeMutablePointer<CItem>) throws -> Element
) where CArray: CItemArray, CArray.Item == CItem {
    guard result.success else {
        continuation.resume(throwing: ffiError(result))
        return
    }
    do {
        var items: [Element] = []
        if array.itemCount > 0, let itemsPtr = array.itemsPointer {
            items = try (0..<array.itemCount).map { try convert($0, itemsPtr) }
        }
        continuation.resume(returning: items)
    } catch {
        continuation.resume(throwing: ModelHealthError.internalError(error.localizedDescription))
    }
}

/// Lets the chunk decoder reach into any of the C array wrappers, each of which names its
/// pointer field after its own resource.
private protocol CItemArray {
    associatedtype Item
    var itemsPointer: UnsafeMutablePointer<Item>? { get }
    var itemCount: Int { get }
}

extension CTrialArray: CItemArray {
    fileprivate var itemsPointer: UnsafeMutablePointer<CTrial>? { trials }
    fileprivate var itemCount: Int { Int(count) }
}

extension CSubjectArray: CItemArray {
    fileprivate var itemsPointer: UnsafeMutablePointer<CSubject>? { subjects }
    fileprivate var itemCount: Int { Int(count) }
}

extension CSessionArray: CItemArray {
    fileprivate var itemsPointer: UnsafeMutablePointer<CSession>? { sessions }
    fileprivate var itemCount: Int { Int(count) }
}

extension CSubjectGroupArray: CItemArray {
    fileprivate var itemsPointer: UnsafeMutablePointer<CSubjectGroup>? { groups }
    fileprivate var itemCount: Int { Int(count) }
}
