import Foundation

// MARK: - SubjectGroup

/// A named collection of subjects.
///
/// ```swift
/// for try await group in client.groups.list() {
///     print("\(group.name): \(group.subjectCount) subjects")
/// }
/// ```
public struct SubjectGroup: Identifiable, Sendable {
    public let id: Int
    public let name: String

    /// Freeform description, or an empty string if none was set.
    public let description: String

    /// Number of subjects in this group.
    public let subjectCount: Int

    /// Total activities recorded across every subject in this group.
    public let totalActivities: Int

    /// Timestamp of the most recent activity across the group, or `nil` if there are none.
    public let lastActivity: Date?

    /// Username of the account that created this group, or `nil` if not reported.
    public let createdBy: String?

    /// Whether the authenticated account owns this group.
    public let isOwner: Bool

    /// Whether the authenticated account can edit this group.
    public let canEdit: Bool

    /// When the group was created.
    public let createdAt: Date

    /// When the group was last modified.
    public let updatedAt: Date

    /// Whether the group is in the trash.
    public let trashed: Bool

    /// When the group was trashed, or `nil` if it isn't.
    public let trashedAt: Date?
}

extension SubjectGroup: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension SubjectGroup {
    public static func forPreview(
        customizing: (inout PreviewBuilder) -> Void = { _ in }
    ) -> Self {
        var builder = PreviewBuilder()
        customizing(&builder)
        return builder.build()
    }

    public struct PreviewBuilder {
        public var id = 1
        public var name = "Cohort A"
        public var description = ""
        public var subjectCount = 2
        public var totalActivities = 34
        public var lastActivity: Date? = Date(timeIntervalSince1970: 1_753_047_851)
        public var createdBy: String? = "jane_doe"
        public var isOwner = true
        public var canEdit = true
        public var createdAt = Date(timeIntervalSince1970: 1_756_809_900)
        public var updatedAt = Date(timeIntervalSince1970: 1_756_809_900)
        public var trashed = false
        public var trashedAt: Date?

        func build() -> SubjectGroup {
            SubjectGroup(
                id: id,
                name: name,
                description: description,
                subjectCount: subjectCount,
                totalActivities: totalActivities,
                lastActivity: lastActivity,
                createdBy: createdBy,
                isOwner: isOwner,
                canEdit: canEdit,
                createdAt: createdAt,
                updatedAt: updatedAt,
                trashed: trashed,
                trashedAt: trashedAt
            )
        }
    }
}
