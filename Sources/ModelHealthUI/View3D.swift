import SwiftUI
import WebKit

#if os(iOS)
/// Embeds a 3D replay view — a bundled, offline HTML/JS page — via `WKWebView`.
///
/// ```swift
/// @StateObject private var controller: View3DController
///
/// init(activity: Activity, service: ModelHealthService) {
///     _controller = StateObject(wrappedValue: View3DController(for: activity, using: service))
/// }
///
/// var body: some View {
///     View3D(controller: controller)
/// }
/// ```
public struct View3D: UIViewRepresentable {
    @ObservedObject var controller: View3DController

    public init(controller: View3DController) {
        self.controller = controller
    }

    public func makeUIView(context: Context) -> WKWebView {
        makeConfiguredWebView()
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
    }
}
#elseif os(macOS)
/// Embeds a 3D replay view — a bundled, offline HTML/JS page — via `WKWebView`.
///
/// ```swift
/// @StateObject private var controller: View3DController
///
/// init(activity: Activity, service: ModelHealthService) {
///     _controller = StateObject(wrappedValue: View3DController(for: activity, using: service))
/// }
///
/// var body: some View {
///     View3D(controller: controller)
/// }
/// ```
public struct View3D: NSViewRepresentable {
    @ObservedObject var controller: View3DController

    public init(controller: View3DController) {
        self.controller = controller
    }

    public func makeNSView(context: Context) -> WKWebView {
        makeConfiguredWebView()
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
    }
}
#endif

private extension View3D {
    func makeConfiguredWebView() -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(controller, name: "viewerBridge")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        controller.webView = webView

        guard let bundleRoot = Bundle.module.url(forResource: "WebBundle", withExtension: nil) else {
            controller.markLoadFailed(reason: "WebBundle resource not found in ModelHealthUI's resource bundle")
            return webView
        }

        let indexURL = bundleRoot.appendingPathComponent("index.html")
        webView.loadFileURL(indexURL, allowingReadAccessTo: bundleRoot)

        return webView
    }
}
