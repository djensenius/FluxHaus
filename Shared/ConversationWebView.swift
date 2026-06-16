//
//  ConversationWebView.swift
//  FluxHaus
//
//  Created by Copilot on 2026-05-22.
//

import SwiftUI
import WebKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ConversationWebView: View {
    let convId: String
    @Bindable var chat: Chat
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var snapshot: ChatTranscriptSnapshot {
        ChatTranscriptSnapshot(
            conversationId: convId,
            messages: chat.messages(for: convId),
            isLoading: chat.isLoadingConversation(convId),
            playingMessageId: chat.playingMessageId
        )
    }

    var body: some View {
        ChatTranscriptWebRepresentable(
            snapshot: snapshot,
            appearance: ChatTranscriptAppearance(
                colorScheme: colorScheme,
                dynamicTypeSize: dynamicTypeSize
            ),
            onOpenURL: { openURL($0) },
            onPlayAudio: { messageId in
                guard let message = chat.messages(for: convId).first(where: {
                    $0.id.uuidString == messageId
                }) else { return }
                if chat.playingMessageId == message.id {
                    chat.stopPlayback()
                } else {
                    chat.playAudio(for: message)
                }
            }
        )
        .background(Theme.Colors.background)
        .accessibilityLabel("Chat transcript")
    }
}

private struct ChatTranscriptAppearance: Encodable, Equatable {
    let scheme: String
    let scale: Double
    private static let scaleValues: [(DynamicTypeSize, Double)] = [
        (.xSmall, 0.88),
        (.small, 0.94),
        (.medium, 1.0),
        (.large, 1.06),
        (.xLarge, 1.12),
        (.xxLarge, 1.18),
        (.xxxLarge, 1.26),
        (.accessibility1, 1.35),
        (.accessibility2, 1.48),
        (.accessibility3, 1.62),
        (.accessibility4, 1.78),
        (.accessibility5, 1.95)
    ]

    init(colorScheme: ColorScheme, dynamicTypeSize: DynamicTypeSize) {
        scheme = colorScheme == .dark ? "dark" : "light"
        scale = Self.dynamicTypeScale(for: dynamicTypeSize)
    }

    private static func dynamicTypeScale(for size: DynamicTypeSize) -> Double {
        Self.scaleValues.first { $0.0 == size }?.1 ?? 1.0
    }
}

@MainActor
private struct ChatTranscriptWebRepresentable {
    let snapshot: ChatTranscriptSnapshot
    let appearance: ChatTranscriptAppearance
    let onOpenURL: (URL) -> Void
    let onPlayAudio: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenURL: onOpenURL, onPlayAudio: onPlayAudio)
    }

    fileprivate func configure(_ webView: WKWebView) {
        webView.allowsBackForwardNavigationGestures = false
        #if canImport(UIKit)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        #elseif canImport(AppKit)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
    }

    fileprivate func loadRenderer(into webView: WKWebView, coordinator: Coordinator) {
        guard let url = Bundle.main.url(
            forResource: "ChatTranscriptRenderer", withExtension: "html"
        ) else {
            let message = "Chat transcript renderer is missing from the app bundle."
            webView.loadHTMLString("<!doctype html><p>\(message)</p>", baseURL: nil)
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}

#if canImport(UIKit)
extension ChatTranscriptWebRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let handler = WeakScriptHandler()
        let webView = WKWebView(frame: .zero, configuration: Self.configuration(handler: handler))
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.attach(webView: webView, handler: handler)
        configure(webView)
        loadRenderer(into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateCallbacks(onOpenURL: onOpenURL, onPlayAudio: onPlayAudio)
        context.coordinator.send(snapshot: snapshot, appearance: appearance, to: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.dismantle()
    }
}
#elseif canImport(AppKit)
extension ChatTranscriptWebRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let handler = WeakScriptHandler()
        let webView = WKWebView(frame: .zero, configuration: Self.configuration(handler: handler))
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.attach(webView: webView, handler: handler)
        configure(webView)
        loadRenderer(into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateCallbacks(onOpenURL: onOpenURL, onPlayAudio: onPlayAudio)
        context.coordinator.send(snapshot: snapshot, appearance: appearance, to: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.dismantle()
    }
}
#endif

@MainActor
private extension ChatTranscriptWebRepresentable {
    static func configuration(handler: WeakScriptHandler) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let controller = WKUserContentController()
        controller.add(handler, name: Coordinator.messageName)
        config.userContentController = controller
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        return config
    }
}

@MainActor
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

extension ChatTranscriptWebRepresentable {
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        static let messageName = "fluxHausChat"

        weak var webView: WKWebView?
        var isReady = false
        private var weakHandler: WeakScriptHandler?
        private var pendingJSON: String?
        private var lastJSON: String?
        private var lastAppearanceJSON: String?
        private var onOpenURL: (URL) -> Void
        private var onPlayAudio: (String) -> Void

        init(onOpenURL: @escaping (URL) -> Void, onPlayAudio: @escaping (String) -> Void) {
            self.onOpenURL = onOpenURL
            self.onPlayAudio = onPlayAudio
            super.init()
        }

        func attach(webView: WKWebView, handler: WeakScriptHandler) {
            self.webView = webView
            weakHandler = handler
            handler.delegate = self
        }

        func updateCallbacks(
            onOpenURL: @escaping (URL) -> Void,
            onPlayAudio: @escaping (String) -> Void
        ) {
            self.onOpenURL = onOpenURL
            self.onPlayAudio = onPlayAudio
        }

        func send(
            snapshot: ChatTranscriptSnapshot,
            appearance: ChatTranscriptAppearance,
            to webView: WKWebView
        ) {
            guard let json = encode(snapshot),
                  let appearanceJSON = encode(appearance) else { return }
            guard isReady else {
                pendingJSON = json
                lastAppearanceJSON = appearanceJSON
                return
            }
            if appearanceJSON != lastAppearanceJSON {
                evaluate("window.FluxHausChat.setAppearance(\(appearanceJSON));", in: webView)
                lastAppearanceJSON = appearanceJSON
            }
            guard json != lastJSON else { return }
            evaluate("window.FluxHausChat.render(\(json));", in: webView)
            lastJSON = json
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                isReady = true
                if let webView, let pendingJSON {
                    if let appearanceJSON = lastAppearanceJSON {
                        evaluate("window.FluxHausChat.setAppearance(\(appearanceJSON));", in: webView)
                    }
                    evaluate("window.FluxHausChat.render(\(pendingJSON));", in: webView)
                    lastJSON = pendingJSON
                    self.pendingJSON = nil
                }
            case "openLink":
                if let value = body["url"] as? String,
                   let url = URL(string: value),
                   allowedExternalURL(url) {
                    onOpenURL(url)
                }
            case "toggleAudio":
                if let id = body["messageId"] as? String {
                    onPlayAudio(id)
                }
            default:
                break
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType != .other else {
                decisionHandler(.allow)
                return
            }
            if let url = navigationAction.request.url, allowedExternalURL(url) {
                onOpenURL(url)
            }
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url, allowedExternalURL(url) {
                onOpenURL(url)
            }
            return nil
        }

        func dismantle() {
            webView?.navigationDelegate = nil
            webView?.uiDelegate = nil
            webView?.configuration.userContentController.removeScriptMessageHandler(
                forName: Self.messageName
            )
            webView = nil
            weakHandler?.delegate = nil
        }

        private func encode<T: Encodable>(_ value: T) -> String? {
            guard let data = try? JSONEncoder().encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        private func evaluate(_ script: String, in webView: WKWebView) {
            webView.evaluateJavaScript(script)
        }

        private func allowedExternalURL(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            return ["http", "https", "mailto"].contains(scheme)
        }
    }
}
