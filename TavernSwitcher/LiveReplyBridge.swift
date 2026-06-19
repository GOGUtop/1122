import Combine
import Foundation
import WebKit

struct LiveReplyEvent: Decodable {
    let type: String
    let generationId: String?
    let text: String?
    let reason: String?
    let character: String?
}

@MainActor
final class LiveReplyBridge: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var statusText = "等待酒馆实时桥接"

    var onEvent: ((LiveReplyEvent) -> Void)?
    var onConnectionChange: ((Bool, String) -> Void)?

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var delegate: EventStreamDelegate?
    private var reconnectWorkItem: DispatchWorkItem?
    private var configuration: Configuration?

    func connect(baseURL: URL, channel: String, webView: WKWebView) {
        guard !channel.isEmpty else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
            Task { @MainActor in
                self?.start(Configuration(baseURL: baseURL, channel: channel, cookieHeader: cookieHeader))
            }
        }
    }

    func disconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        delegate = nil
        configuration = nil
        isConnected = false
    }

    private func start(_ configuration: Configuration) {
        if self.configuration == configuration, task != nil { return }
        disconnect()
        self.configuration = configuration

        guard let eventURL = URL(
            string: "/api/plugins/tavern-live-bridge/events",
            relativeTo: configuration.baseURL
        )?.absoluteURL,
        var components = URLComponents(
            url: eventURL,
            resolvingAgainstBaseURL: false
        ) else { return }
        components.queryItems = [URLQueryItem(name: "channel", value: configuration.channel)]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60 * 60
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let cookieHeader = configuration.cookieHeader {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let streamDelegate = EventStreamDelegate()
        streamDelegate.onConnected = { [weak self] in
            Task { @MainActor in
                self?.isConnected = true
                self?.statusText = "实时桥接已连接"
                self?.onConnectionChange?(true, "实时桥接已连接")
            }
        }
        streamDelegate.onEvent = { [weak self] event in
            Task { @MainActor in self?.onEvent?(event) }
        }
        streamDelegate.onClosed = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.task = nil
                self.session = nil
                self.delegate = nil
                self.isConnected = false
                self.statusText = "实时桥接重连中…"
                self.onConnectionChange?(false, "实时桥接重连中…")
                self.scheduleReconnect()
            }
        }

        delegate = streamDelegate
        let session = URLSession(configuration: .default, delegate: streamDelegate, delegateQueue: nil)
        self.session = session
        task = session.dataTask(with: request)
        task?.resume()
    }

    private func scheduleReconnect() {
        guard let configuration else { return }
        reconnectWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.start(configuration) }
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    private struct Configuration: Equatable {
        let baseURL: URL
        let channel: String
        let cookieHeader: String?
    }
}

private final class EventStreamDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    var onConnected: (() -> Void)?
    var onEvent: ((LiveReplyEvent) -> Void)?
    var onClosed: (() -> Void)?

    private var buffer = ""

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              response.mimeType == "text/event-stream" else {
            completionHandler(.cancel)
            return
        }
        onConnected?()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        buffer += string
        while let range = buffer.range(of: "\n\n") {
            let block = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            let payload = block
                .split(separator: "\n")
                .filter { $0.hasPrefix("data:") }
                .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
            guard !payload.isEmpty,
                  let data = payload.data(using: .utf8),
                  let event = try? JSONDecoder().decode(LiveReplyEvent.self, from: data) else { continue }
            onEvent?(event)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        onClosed?()
    }
}
