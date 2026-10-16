import Foundation
import SwiftUI
import WebKit
import FocusTubeCore

/// ADR-0007: thin WebKit adapter around the official YouTube IFrame Player.
/// All decisions live in `IFramePlayerController` (core, unit-tested); this
/// class only evaluates rendered commands and forwards bridge messages.
/// Not wired into PlayerCoordinator yet (phase 2 switch-over).
@MainActor
final class WKWebViewPlayerEngine: NSObject, PlayerEngine {
    let webView: WKWebView
    private var controller = IFramePlayerController()
    private let origin: URL
    var onStateChange: (@MainActor (IFramePlayerState) -> Void)?
    var state: IFramePlayerState { controller.state }

    init(origin: URL = IFrameEmbedPage.defaultOrigin) {
        self.origin = origin
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let content = WKUserContentController()
        config.userContentController = content
        webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        super.init()
        content.add(WeakScriptHandler(self), name: IFrameEmbedPage.messageHandlerName)
        webView.loadHTMLString(IFrameEmbedPage.html(origin: origin), baseURL: origin)
    }

    func load(_ videoID: YouTubeVideoID, startSeconds: Double, autoplay: Bool) {
        send(.load(videoID, startSeconds: startSeconds, autoplay: autoplay))
    }
    func play() { send(.play) }
    func pause() { send(.pause) }
    func seek(to seconds: Double) { send(.seek(seconds)) }
    func setPlaybackRate(_ rate: Double) { send(.setRate(rate)) }
    func stop() { send(.stop) }

    private func send(_ intent: IFramePlayerController.Intent) {
        run(controller.handle(intent))
    }

    private func run(_ commands: [IFramePlayerCommand]) {
        for command in commands {
            webView.evaluateJavaScript(command.javaScript, completionHandler: nil)
        }
        onStateChange?(controller.state)
    }

    fileprivate func receive(_ body: Any) {
        guard let message = try? IFrameBridgeMessage.parse(body) else { return }
        run(controller.apply(message))
    }
}

/// Breaks the WKUserContentController → handler retain cycle.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var engine: WKWebViewPlayerEngine?
    init(_ engine: WKWebViewPlayerEngine) { self.engine = engine }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated { engine?.receive(body) }
    }
}

/// SwiftUI host for the engine's web view.
struct IFramePlayerView: UIViewRepresentable {
    let engine: WKWebViewPlayerEngine
    func makeUIView(context: Context) -> WKWebView { engine.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
