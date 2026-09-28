import Foundation

/// Coalesces rapid calls into periodic flushes, always carrying the most
/// recently supplied value — a lone call still flushes on its own rather
/// than waiting indefinitely for a second one.
///
/// Used by `View3DController.seek(to:)` to keep a caller driving playback at
/// native video frame rate (30-60Hz) from producing one round-trip per call.
@MainActor
final class SeekCoalescer {
    private let interval: TimeInterval
    private let flush: (Double) -> Void
    private let sleep: (TimeInterval) async -> Void

    private var pendingValue: Double?
    private var flushTask: Task<Void, Never>?
    private var lastFlushedAt: Date?

    init(
        interval: TimeInterval,
        flush: @escaping (Double) -> Void,
        sleep: @escaping (TimeInterval) async -> Void = SeekCoalescer.defaultSleep
    ) {
        self.interval = interval
        self.flush = flush
        self.sleep = sleep
    }

    /// Requests `value` be flushed. Safe to call at high frequency — rapid
    /// calls are coalesced to one flush per `interval`, always carrying the
    /// latest value.
    func call(_ value: Double) {
        pendingValue = value

        guard flushTask == nil else {
            return
        }

        let elapsed = lastFlushedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        let delay = max(0, interval - elapsed)

        flushTask = Task { [weak self] in
            if delay > 0 {
                await self?.sleep(delay)
            }
            self?.performFlush()
        }
    }

    private func performFlush() {
        flushTask = nil
        lastFlushedAt = Date()

        guard let value = pendingValue else {
            return
        }

        pendingValue = nil
        flush(value)
    }

    private static func defaultSleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
