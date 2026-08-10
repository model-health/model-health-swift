import Foundation
import ModelHealth
import WebKit

/// Drives playback for a `View3D` and publishes its current state.
///
/// Creating a controller starts fetching and loading the activity's
/// animation data automatically. Use `play()`, `pause()`, `seek(to:)`,
/// `step(_:)`, and `setPlaybackSpeed(_:)` to control playback, and observe
/// `isReady`, `currentTime`, `duration`, `isPlaying`, and `lastError` for
/// state.
@MainActor
public final class View3DController: NSObject, ObservableObject {
    /// Whether the controller has finished loading and is ready to accept commands.
    @Published public private(set) var isReady = false

    /// The current playhead position, in seconds, as last reported.
    @Published public private(set) var currentTime: Double = 0

    /// The total duration, in seconds — `0` until the animation data has loaded.
    @Published public private(set) var duration: Double = 0

    /// Whether playback is currently running — this reflects every
    /// transition, including playback stopping itself at the end, not just
    /// the most recent `play()`/`pause()` call.
    @Published public private(set) var isPlaying = false

    /// The most recent error surfaced while loading or preparing the
    /// animation, if any.
    @Published public private(set) var lastError: String?

    /// Whether the activity's animation data is currently being fetched.
    ///
    /// `true` immediately on construction; flips to `false` once the fetch completes,
    /// whether it succeeds or fails.
    @Published public private(set) var isLoadingTransforms = true

    weak var webView: WKWebView?

    private var pendingTransformsJSON: String?
    private var pendingExternalData: String?

    private let activity: Activity
    private let client: ModelHealthClient

    /// The tag an external file was originally uploaded under, if any.
    /// The synced result — tagged `"\(externalDataTag)-sync"` — is what
    /// actually gets fetched and loaded, not the raw upload.
    private let externalDataTag: String?

    /// Creates a controller and immediately begins fetching and loading `activity`'s
    /// `animation` motion data — no separate load step needed. Call ``reload()`` to
    /// retry after a failure. If `externalDataTag` is provided, its synced
    /// result is fetched and loaded alongside the animation data.
    public init(for activity: Activity, using client: ModelHealthClient, externalDataTag: String? = nil) {
        self.activity = activity
        self.client = client
        self.externalDataTag = externalDataTag
        super.init()
        Task { [weak self] in
            await self?.reload()
        }
    }

    /// Re-fetches the activity's `animation` motion data and loads it into the view.
    ///
    /// Called automatically on construction — call it again to retry after ``lastError``.
    public func reload() async {
        isLoadingTransforms = true
        lastError = nil

        let results = await client.motionData(ofType: [.animation], for: activity)
        isLoadingTransforms = false

        guard let data = results.first?.data else {
            lastError = "No animation data available for this activity"
            return
        }

        loadTransforms(data)

        if let externalDataTag {
            let externalResults = await client.motionData(
                ofType: [.tagged("\(externalDataTag)-sync", "sto")],
                for: activity
            )
            if let externalData = externalResults.first?.data {
                loadExternalData(externalData)
            }
        }
    }

    public func play() {
        callBridge("play")
    }

    public func pause() {
        callBridge("pause")
    }

    public func seek(to time: Double) {
        evaluate("window.viewerBridge && window.viewerBridge.seek(\(time))")
    }

    /// Steps one frame forward (`1`) or backward (`-1`).
    public func step(_ direction: Int) {
        evaluate("window.viewerBridge && window.viewerBridge.step(\(direction))")
    }

    public func setPlaybackSpeed(_ speed: Double) {
        evaluate("window.viewerBridge && window.viewerBridge.setPlaybackSpeed(\(speed))")
    }

    /// Records a load-time failure (e.g. the bundled `WebBundle` resource is
    /// missing) as ``lastError``. Called by `View3D` during view creation.
    func markLoadFailed(reason: String) {
        lastError = reason
    }
}

private extension View3DController {
    /// Forwards already-fetched transforms JSON to the page.
    ///
    /// If the page has not finished loading yet, the data is queued and sent
    /// automatically once ``isReady`` becomes `true`.
    func loadTransforms(_ data: Data) {
        guard let json = String(data: data, encoding: .utf8) else {
            lastError = "Failed to encode transforms data as UTF-8"
            return
        }

        guard isReady else {
            pendingTransformsJSON = json
            return
        }

        callBridge("loadTransforms", jsonArgument: json)
    }

    /// Forwards already-fetched external file text to the page
    ///
    /// If the page has not finished loading yet, the data is queued and sent
    /// automatically once ``isReady`` becomes `true`.
    func loadExternalData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            return
        }

        guard isReady else {
            pendingExternalData = text
            return
        }

        callBridge("loadExternalData", jsonArgument: text)
    }

    func callBridge(_ method: String, jsonArgument: String? = nil) {
        guard let jsonArgument else {
            evaluate("window.viewerBridge && window.viewerBridge.\(method)()")
            return
        }

        evaluate("window.viewerBridge && window.viewerBridge.\(method)(\(jsStringLiteral(jsonArgument)))")
    }

    func evaluate(_ script: String) {
        guard let webView else {
            return
        }

        Task {
            do {
                _ = try await webView.evaluateJavaScript(script)
            } catch {
                lastError = "JavaScript evaluation failed: \(error.localizedDescription)"
            }
        }
    }

    func handleReady() {
        isReady = true

        if let pendingTransformsJSON {
            callBridge("loadTransforms", jsonArgument: pendingTransformsJSON)
            self.pendingTransformsJSON = nil
        }

        if let pendingExternalData {
            callBridge("loadExternalData", jsonArgument: pendingExternalData)
            self.pendingExternalData = nil
        }
    }

    func handleError(_ message: String) {
        lastError = message
    }

    func handleFrameChanged(_ time: Double) {
        currentTime = time
    }

    func handlePlayingChanged(_ playing: Bool) {
        isPlaying = playing
    }

    func handleDurationChanged(_ newDuration: Double) {
        duration = newDuration
    }
}

extension View3DController: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else {
            return
        }

        guard let type = body["type"] as? String else {
            return
        }

        switch type {
        case "ready":
            handleReady()

        case "error":
            let errorMessage = body["message"] as? String ?? "Unknown viewer error"
            handleError(errorMessage)

        case "frameChanged":
            guard let time = body["time"] as? Double else {
                return
            }
            handleFrameChanged(time)

        case "playingChanged":
            guard let isPlaying = body["isPlaying"] as? Bool else {
                return
            }
            handlePlayingChanged(isPlaying)

        case "durationChanged":
            guard let duration = body["duration"] as? Double else {
                return
            }
            handleDurationChanged(duration)

        default:
            break
        }
    }
}

/// Encodes `value` as a JSON string literal (with surrounding quotes) so it can
/// be safely embedded inside an `evaluateJavaScript` script string.
private func jsStringLiteral(_ value: String) -> String {
    guard
        let data = try? JSONEncoder().encode(value),
        let encoded = String(data: data, encoding: .utf8)
    else {
        return "\"\""
    }

    return encoded
}
