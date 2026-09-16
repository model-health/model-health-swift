import Foundation

// MARK: - Filter date formatting

/// Filter date ranges are whole days, so they cross the boundary as bare `YYYY-MM-DD`.
///
/// The day is read in the current time zone, not UTC. A date built for the first of January
/// is written to mean that day; east of UTC the same instant belongs to the previous one, and
/// rendering it in UTC would start the range a day early with nothing to show for it.
private let filterDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

internal func formatFilterDate(_ date: Date?) -> String? {
    date.map { filterDateFormatter.string(from: $0) }
}

/// Encodes a filter payload as the JSON object the core layer expects.
///
/// Keys are converted to `snake_case` and `nil` fields are omitted, so the receiving side
/// applies its own default for anything left out.
internal func encodeFilter<T: Encodable>(_ filter: T) -> String {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    guard let data = try? encoder.encode(filter), let json = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return json
}

// MARK: - Reading a list

/// Where an ``ItemReader`` gets its items, and how it lets them go.
///
/// Closures rather than a protocol so a test can stand in, and so a list that could not be
/// opened can be represented by closures that report why.
internal struct ItemSource<Element> {
    let nextItems: () async throws -> [Element]
    let readTotal: () async throws -> Int
    let readAll: () async throws -> [Element]
    let release: () -> Void
}

/// Hands out one item at a time from what a ``ItemSource`` supplies.
///
/// `Sendable` is unchecked because a reader holds mutable state, and a sequence can be
/// handed to another task even though it is meant to be read by one. `claim()` is what
/// makes that safe: a second reader is turned away rather than allowed to interleave with
/// the first, which would otherwise leave both the position here and the state the source
/// reads from being written from two places at once.
internal final class ItemReader<Element>: @unchecked Sendable {
    private let source: ItemSource<Element>
    private var held: [Element] = []
    private var position = 0
    private var finished = false
    private let gate = NSLock()
    private var reading = false

    internal init(source: ItemSource<Element>) {
        self.source = source
    }

    deinit {
        source.release()
    }

    internal func next() async throws -> Element? {
        try claim()
        defer {
            yield()
        }

        if position < held.count {
            defer {
                position += 1
            }
            return held[position]
        }
        if finished {
            return nil
        }

        held = try await source.nextItems()
        position = 0
        if held.isEmpty {
            finished = true
            return nil
        }
        position = 1
        return held[0]
    }

    internal func total() async throws -> Int {
        try claim()
        defer {
            yield()
        }

        return try await source.readTotal()
    }

    internal func all() async throws -> [Element] {
        try claim()
        defer {
            yield()
        }

        var items = Array(held[position...])
        held = []
        position = 0
        if !finished {
            items.append(contentsOf: try await source.readAll())
            finished = true
        }
        return items
    }

    /// Takes sole possession of the reader for the duration of one read.
    ///
    /// Taken and released without suspending in between, so two tasks cannot both come away
    /// believing they have it.
    private func claim() throws {
        gate.lock()
        defer {
            gate.unlock()
        }
        guard !reading else {
            throw ModelHealthError.internalError(
                "this sequence is already being read; a sequence is read by one task at a time"
            )
        }
        reading = true
    }

    private func yield() {
        gate.lock()
        reading = false
        gate.unlock()
    }
}

/// An async sequence of activities matching a filter.
///
/// Not constructed directly — ``ActivitiesResource/list(...)`` returns one:
///
/// ```swift
/// for try await item in stream {
///     print(item)
/// }
/// ```
///
/// Read ``total`` for the number of items matching the filter, or call ``all()`` to collect
/// what is left into an array.
///
/// A sequence is single-pass and meant for one task at a time: iterating draws from what has
/// already been gathered, so ``all()`` returns what remains rather than starting over.
public struct ActivityStream: AsyncSequence {
    public typealias Element = Activity

    private let reader: ItemReader<Activity>

    internal init(reader: ItemReader<Activity>) {
        self.reader = reader
    }

    /// Builds a sequence over activity values you already have.
    ///
    /// For a mock, a preview or a test double: a conformer with its own items needs a way to
    /// hand them over, and everything else about a sequence is decided inside the SDK.
    public init(_ items: [Activity]) {
        self.init(reader: ItemReader(source: fixed(items)))
    }

    /// The full count of activities matching the filter.
    public var total: Int {
        get async throws {
            try await reader.total()
        }
    }

    /// Returns every remaining matching activity as an array.
    ///
    /// Continues from wherever iteration has got to — call it on a freshly returned sequence
    /// to collect everything it matches.
    public func all() async throws -> [Activity] {
        try await reader.all()
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(reader: reader)
    }

    public struct Iterator: AsyncIteratorProtocol {
        fileprivate let reader: ItemReader<Activity>

        public mutating func next() async throws -> Activity? {
            try await reader.next()
        }
    }
}

/// An async sequence of subjects matching a filter.
///
/// Not constructed directly — ``SubjectsResource/list(...)`` returns one:
///
/// ```swift
/// for try await item in stream {
///     print(item)
/// }
/// ```
///
/// Read ``total`` for the number of items matching the filter, or call ``all()`` to collect
/// what is left into an array.
///
/// A sequence is single-pass and meant for one task at a time: iterating draws from what has
/// already been gathered, so ``all()`` returns what remains rather than starting over.
public struct SubjectStream: AsyncSequence {
    public typealias Element = Subject

    private let reader: ItemReader<Subject>

    internal init(reader: ItemReader<Subject>) {
        self.reader = reader
    }

    /// Builds a sequence over subject values you already have.
    ///
    /// For a mock, a preview or a test double: a conformer with its own items needs a way to
    /// hand them over, and everything else about a sequence is decided inside the SDK.
    public init(_ items: [Subject]) {
        self.init(reader: ItemReader(source: fixed(items)))
    }

    /// The full count of subjects matching the filter.
    public var total: Int {
        get async throws {
            try await reader.total()
        }
    }

    /// Returns every remaining matching subject as an array.
    ///
    /// Continues from wherever iteration has got to — call it on a freshly returned sequence
    /// to collect everything it matches.
    public func all() async throws -> [Subject] {
        try await reader.all()
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(reader: reader)
    }

    public struct Iterator: AsyncIteratorProtocol {
        fileprivate let reader: ItemReader<Subject>

        public mutating func next() async throws -> Subject? {
            try await reader.next()
        }
    }
}

/// An async sequence of sessions matching a filter.
///
/// Not constructed directly — ``SessionsResource/list(...)`` returns one:
///
/// ```swift
/// for try await item in stream {
///     print(item)
/// }
/// ```
///
/// Read ``total`` for the number of items matching the filter, or call ``all()`` to collect
/// what is left into an array.
///
/// A sequence is single-pass and meant for one task at a time: iterating draws from what has
/// already been gathered, so ``all()`` returns what remains rather than starting over.
public struct SessionStream: AsyncSequence {
    public typealias Element = Session

    private let reader: ItemReader<Session>

    internal init(reader: ItemReader<Session>) {
        self.reader = reader
    }

    /// Builds a sequence over session values you already have.
    ///
    /// For a mock, a preview or a test double: a conformer with its own items needs a way to
    /// hand them over, and everything else about a sequence is decided inside the SDK.
    public init(_ items: [Session]) {
        self.init(reader: ItemReader(source: fixed(items)))
    }

    /// The full count of sessions matching the filter.
    public var total: Int {
        get async throws {
            try await reader.total()
        }
    }

    /// Returns every remaining matching session as an array.
    ///
    /// Continues from wherever iteration has got to — call it on a freshly returned sequence
    /// to collect everything it matches.
    public func all() async throws -> [Session] {
        try await reader.all()
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(reader: reader)
    }

    public struct Iterator: AsyncIteratorProtocol {
        fileprivate let reader: ItemReader<Session>

        public mutating func next() async throws -> Session? {
            try await reader.next()
        }
    }
}

/// An async sequence of subject groups matching a filter.
///
/// Not constructed directly — ``GroupsResource/list(...)`` returns one:
///
/// ```swift
/// for try await item in stream {
///     print(item)
/// }
/// ```
///
/// Read ``total`` for the number of items matching the filter, or call ``all()`` to collect
/// what is left into an array.
///
/// A sequence is single-pass and meant for one task at a time: iterating draws from what has
/// already been gathered, so ``all()`` returns what remains rather than starting over.
public struct GroupStream: AsyncSequence {
    public typealias Element = SubjectGroup

    private let reader: ItemReader<SubjectGroup>

    internal init(reader: ItemReader<SubjectGroup>) {
        self.reader = reader
    }

    /// Builds a sequence over subjectgroup values you already have.
    ///
    /// For a mock, a preview or a test double: a conformer with its own items needs a way to
    /// hand them over, and everything else about a sequence is decided inside the SDK.
    public init(_ items: [SubjectGroup]) {
        self.init(reader: ItemReader(source: fixed(items)))
    }

    /// The full count of subject groups matching the filter.
    public var total: Int {
        get async throws {
            try await reader.total()
        }
    }

    /// Returns every remaining matching subjectgroup as an array.
    ///
    /// Continues from wherever iteration has got to — call it on a freshly returned sequence
    /// to collect everything it matches.
    public func all() async throws -> [SubjectGroup] {
        try await reader.all()
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(reader: reader)
    }

    public struct Iterator: AsyncIteratorProtocol {
        fileprivate let reader: ItemReader<SubjectGroup>

        public mutating func next() async throws -> SubjectGroup? {
            try await reader.next()
        }
    }
}

// MARK: - Sort fields

/// Sort field for ``ActivitiesResource/list(subject:calibrationSession:activityType:excludeCalibration:createdAfter:createdBefore:search:tags:createdBy:onlyCompleted:excludeAnalysisError:orderBy:limit:)``.
///
/// A `descending` case sorts newest/highest first.
public enum ActivityOrderBy: String, Sendable {
    case createdAt = "created_at"
    case createdAtDescending = "-created_at"
    case status
    case statusDescending = "-status"
    case createdBy = "created_by"
    case createdByDescending = "-created_by"
    case activityType = "activity_type"
    case activityTypeDescending = "-activity_type"
}

/// Sort field for ``SubjectsResource/list(search:createdAfter:createdBefore:groups:tags:createdBy:activityType:activityComplete:session:orderBy:limit:)``.
public enum SubjectOrderBy: String, Sendable {
    case name
    case nameDescending = "-name"
    case createdAt = "created_at"
    case createdAtDescending = "-created_at"
    case updatedAt = "updated_at"
    case updatedAtDescending = "-updated_at"
}

/// Sort field for ``SessionsResource/list(subject:orderBy:limit:)``.
public enum SessionOrderBy: String, Sendable {
    case name
    case nameDescending = "-name"
    case createdAt = "created_at"
    case createdAtDescending = "-created_at"
}

/// Sort field for ``GroupsResource/list(search:orderBy:limit:)``.
public enum GroupOrderBy: String, Sendable {
    case name
    case nameDescending = "-name"
}

// MARK: - Filter payloads

/// Wire shape of ``ActivityListFilter`` in the core layer. `activityType` is not here — it
/// crosses as a discriminant so the enum's wire name stays on the Rust side.
internal struct ActivityFilterPayload: Encodable {
    var subjectId: Int?
    var calibrationSessionId: String?
    var excludeCalibrate: Bool
    var excludeNeutral: Bool
    var createdAfter: String?
    var createdBefore: String?
    var search: String?
    var tags: [String]?
    var createdBy: [Int]?
    var onlyCompleted: Bool
    var excludeAnalysisError: Bool
}

internal struct SubjectFilterPayload: Encodable {
    var search: String?
    var createdAfter: String?
    var createdBefore: String?
    var groups: [String]?
    var tags: [String]?
    var createdBy: [Int]?
    var activityComplete: Bool?
    var sessionId: String?
}

internal struct SessionFilterPayload: Encodable {
    var subjectId: Int?
}

internal struct GroupFilterPayload: Encodable {
    var search: String?
}

/// A source over items the caller already has, handed over all at once.
internal func fixed<Element>(_ items: [Element]) -> ItemSource<Element> {
    var remaining: [Element]? = items
    return ItemSource(
        nextItems: {
            defer {
                remaining = nil
            }
            return remaining ?? []
        },
        readTotal: { items.count },
        readAll: {
            defer {
                remaining = nil
            }
            return remaining ?? []
        },
        release: {}
    )
}

/// A source for a conformer that has not implemented the sequence it was asked for.
internal func notImplemented<Element>(_ method: String, by conformer: Any) -> ItemSource<Element> {
    let error = ModelHealthError.internalError(
        "\(method)(...) is not implemented by \(type(of: conformer))"
    )
    return ItemSource(
        nextItems: { throw error },
        readTotal: { throw error },
        readAll: { throw error },
        release: {}
    )
}
