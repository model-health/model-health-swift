import Foundation
import ModelHealthFFI

private let metricDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

/// Internal implementation of ModelHealthProvider using Rust FFI
internal final class ModelHealthProviderImpl: ModelHealthProvider {
    private let handle: UnsafeMutablePointer<ModelHealthProviderHandle>

    /// Creates a new provider with the given API key
    /// - Parameter apiKey: The API key for authentication
    /// - Throws: ModelHealthError if provider creation fails
    init(apiKey: String) throws {
        let handle = try apiKey.withCString { apiKeyPtr in
            guard let handle = model_health_provider_new(apiKeyPtr) else {
                throw ModelHealthError.internalError("Failed to create provider with API key")
            }
            return handle
        }

        self.handle = handle
    }

    deinit {
        model_health_provider_free(handle)
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
                        sessions = try (0..<Int(cArray.count)).map { i in
                            try Session.from(cSession: sessionsPtr[i])
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
                id: nil, name: nil, session_name: nil,
                user: 0, is_public: false, qrcode: nil,
                subject: 0, trials_count: 0
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

    func subjectList() async throws -> [Subject] {
        try await withCheckedThrowingContinuation { continuation in
            var cArray = CSubjectArray(subjects: nil, count: 0)
            let result = model_health_subject_list(handle, &cArray)

            defer {
                model_health_free_subject_array(cArray)
            }

            if result.success {
                do {
                    var subjects: [Subject] = []
                    if cArray.count > 0, let subjectsPtr = cArray.subjects {
                        subjects = try (0..<Int(cArray.count)).map { i in
                            try Subject.from(cSubject: subjectsPtr[i])
                        }
                    }
                    continuation.resume(returning: subjects)
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
                        trials = try (0..<Int(cArray.count)).map { i in
                            try Activity.from(cTrial: trialsPtr[i])
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

    func activities(
        forSubject subjectId: Int,
        startIndex: Int,
        count: Int,
        sortedBy sort: ActivitySort
    ) async throws -> [Activity] {
        try await withCheckedThrowingContinuation { continuation in
            var cArray = CTrialArray(trials: nil, count: 0)
            let sortCode = activitySortToI32(sort)

            let result = model_health_activities_for_subject(
                handle,
                Int32(subjectId),
                UInt32(startIndex),
                UInt32(count),
                sortCode,
                &cArray
            )

            defer {
                model_health_free_trial_array(cArray)
            }

            if result.success {
                do {
                    var activities: [Activity] = []
                    if cArray.count > 0, let trialsPtr = cArray.trials {
                        activities = try (0..<Int(cArray.count)).map { i in
                            try Activity.from(cTrial: trialsPtr[i])
                        }
                    }
                    continuation.resume(returning: activities)
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
            var cTrial = CTrial(
                id: nil,
                session: nil,
                name: nil,
                status: nil,
                videos: CVideoArray(videos: nil, count: 0),
                results: CTrialResultArray(results: nil, count: 0),
                activity_type: -1,
                tags: nil
            )

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
            var cTrial = CTrial(
                id: nil,
                session: nil,
                name: nil,
                status: nil,
                videos: CVideoArray(videos: nil, count: 0),
                results: CTrialResultArray(results: nil, count: 0),
                activity_type: -1,
                tags: nil
            )

            let nameString: String? = config?.name

            let addTagsJsonString: String? = {
                guard let tags = config?.addTags, !tags.isEmpty else { return nil }
                guard let data = try? JSONSerialization.data(withJSONObject: tags),
                      let str = String(data: data, encoding: .utf8) else { return nil }
                return str
            }()

            let removeTagsJsonString: String? = {
                guard let tags = config?.removeTags, !tags.isEmpty else { return nil }
                guard let data = try? JSONSerialization.data(withJSONObject: tags),
                      let str = String(data: data, encoding: .utf8) else { return nil }
                return str
            }()

            let result = activity.id.withCString { activityIdPtr in
                let callFFI = { (namePtr: UnsafePointer<CChar>?) -> FFIResult in
                    let callFFIWithAddTags = { (addTagsPtr: UnsafePointer<CChar>?) -> FFIResult in
                        if let removeTagsJson = removeTagsJsonString {
                            return removeTagsJson.withCString { removeTagsPtr in
                                model_health_update_activity(self.handle, activityIdPtr, namePtr, addTagsPtr, removeTagsPtr, &cTrial)
                            }
                        }
                        return model_health_update_activity(self.handle, activityIdPtr, namePtr, addTagsPtr, nil, &cTrial)
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
                        tags = try (0..<Int(cArray.count)).map { i in
                            try ActivityTag.from(cTag: tagsPtr[i])
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
                let dataArray = (0..<Int(cArray.count)).compactMap { i -> Data? in
                    let item = itemsPtr[i]
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
                                return FFIResult(success: false, error_message: nil)
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
                    let fetched: [MotionData] = (0..<Int(cArray.count)).compactMap { i in
                        let item = itemsPtr[i]
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

            let cFiles: [CExternalResultFile] = files.map { file in
                let dataPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: file.data.count)
                file.data.copyBytes(to: dataPtr, count: file.data.count)
                dataPtrs.append(dataPtr)

                let tagCString = file.tag.utf8CString
                let tagPtr = UnsafeMutablePointer<CChar>.allocate(capacity: tagCString.count)
                tagCString.withUnsafeBufferPointer { buf in
                    tagPtr.initialize(from: buf.baseAddress!, count: tagCString.count)
                }
                tagPtrs.append(tagPtr)

                let extCString = file.fileExtension.utf8CString
                let extPtr = UnsafeMutablePointer<CChar>.allocate(capacity: extCString.count)
                extCString.withUnsafeBufferPointer { buf in
                    extPtr.initialize(from: buf.baseAddress!, count: extCString.count)
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

            var cTrial = CTrial(
                id: nil, session: nil, name: nil, status: nil,
                videos: CVideoArray(videos: nil, count: 0),
                results: CTrialResultArray(results: nil, count: 0),
                activity_type: -1, tags: nil
            )

            let result = trial.id.withCString { trialId in
                trial.session.withCString { sessionId in
                    cFiles.withUnsafeBufferPointer { buffer in
                        model_health_add_motion_data_to_activity(
                            handle,
                            trialId,
                            sessionId,
                            buffer.baseAddress!,
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
                            return FFIResult(success: false, error_message: nil)
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

            let results: [AnalysisData] = (0..<Int(cArray.count)).compactMap { i in
                let item = itemsPtr[i]
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
                id: nil, name: nil, session_name: nil,
                user: 0, is_public: false, qrcode: nil,
                subject: 0, trials_count: 0
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
            var cSubject = CSubject(
                id: 0, name: nil, weight: 0, height: 0,
                age: 0, birth_year: 0, gender: 0, sex_at_birth: 0,
                characteristics: nil
            )

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
            var cTrial = CTrial(
                id: nil, session: nil, name: nil, status: nil,
                videos: CVideoArray(videos: nil, count: 0),
                results: CTrialResultArray(results: nil, count: 0),
                activity_type: -1, tags: nil
            )
            let cActivityType: Int32 = config?.activityType?.cValue ?? -1
            let cFramerate: Int32 = config?.config?.framerate.map(\.cValue) ?? -1
            let cFilterFrequency: Int32 = config?.config?.filterFrequency.map(\.cValue) ?? -1

            let addTagsJsonString: String? = {
                guard let tags = config?.addTags, !tags.isEmpty else { return nil }
                guard let data = try? JSONSerialization.data(withJSONObject: tags),
                      let str = String(data: data, encoding: .utf8) else { return nil }
                return str
            }()

            let result = name.withCString { trialName in
                session.id.withCString { sessionId in
                    if let tagsJson = addTagsJsonString {
                        return tagsJson.withCString { tagsPtr in
                            model_health_start_recording(handle, trialName, sessionId, cActivityType, cFramerate, cFilterFrequency, tagsPtr, &cTrial)
                        }
                    }

                    return model_health_start_recording(handle, trialName, sessionId, cActivityType, cFramerate, cFilterFrequency, nil, &cTrial)
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
                id: nil, name: nil, session_name: nil,
                user: 0, is_public: false, qrcode: nil,
                subject: 0, trials_count: 0
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
            case (let s?, let e?):
                result = s.withCString { sp in e.withCString { ep in callFFI(startPtr: sp, endPtr: ep) } }

            case (let s?, nil):
                result = s.withCString { sp in callFFI(startPtr: sp, endPtr: nil) }

            case (nil, let e?):
                result = e.withCString { ep in callFFI(startPtr: nil, endPtr: ep) }

            case (nil, nil):
                result = callFFI(startPtr: nil, endPtr: nil)
            }

            if result.success {
                do {
                    var allMetrics: [ActivityMetrics] = []
                    if cArray.count > 0, let itemsPtr = cArray.items {
                        allMetrics = try (0..<Int(cArray.count)).map { i in
                            try ActivityMetrics.from(cMetrics: itemsPtr[i])
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
}

// MARK: - Helper Methods

private extension ModelHealthProviderImpl {
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
        if let errorMessage = result.error_message {
            let error = String(cString: errorMessage)
            model_health_free_error(errorMessage)
            if error.contains("not supported") {
                continuation.resume(throwing: ModelHealthError.notSupported)
            } else {
                continuation.resume(throwing: ModelHealthError.internalError(error))
            }
        } else {
            continuation.resume(throwing: ModelHealthError.internalError("Unknown error"))
        }
    }

    func freeSessionFields(_ session: CSession) {
        session.id.map { model_health_free_string($0) }
        session.name.map { model_health_free_string($0) }
        session.session_name.map { model_health_free_string($0) }
        session.qrcode.map { model_health_free_string($0) }
    }

    func freeSubjectFields(_ subject: CSubject) {
        subject.name.map { model_health_free_string($0) }
        subject.characteristics.map { model_health_free_string($0) }
    }

    func freeTrialFields(_ trial: CTrial) {
        trial.id.map { model_health_free_string($0) }
        trial.session.map { model_health_free_string($0) }
        trial.name.map { model_health_free_string($0) }
        trial.status.map { model_health_free_string($0) }
        trial.tags.map { model_health_free_string($0) }
        model_health_free_video_array(trial.videos)
        model_health_free_trial_result_array(trial.results)
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
