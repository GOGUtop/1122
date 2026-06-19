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
            let matchingCookies = cookies.filter { cookie in
                guard let host = baseURL.host else { return false }
                return host == cookie.domain || host.hasSuffix(cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            }
            let cookieHeader = HTTPCookie.requestHeaderFields(with: matchingCookies)["Cookie"]
            Task { @MainActor in
                self?.start(Configuration(
                    baseURL: baseURL,
                    channel: channel,
                    cookies: matchingCookies,
                    cookieHeader: cookieHeader,
                    userAgent: webView.customUserAgent
                ))
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
        request.setValue(configuration.baseURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(configuration.baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(configuration.userAgent ?? "TavernSwitcher/1.8", forHTTPHeaderField: "User-Agent")
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
        streamDelegate.onClosed = { [weak self] reason in
            Task { @MainActor in
                guard let self else { return }
                self.task = nil
                self.session = nil
                self.delegate = nil
                self.isConnected = false
                self.statusText = reason
                self.onConnectionChange?(false, reason)
                self.scheduleReconnect()
            }
        }

        delegate = streamDelegate
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = 60 * 60
        sessionConfiguration.timeoutIntervalForResource = 60 * 60
        sessionConfiguration.httpShouldSetCookies = true
        sessionConfiguration.httpCookieAcceptPolicy = .always
        let cookieStorage = HTTPCookieStorage.shared
        for cookie in configuration.cookies {
            cookieStorage.setCookie(cookie)
        }
        sessionConfiguration.httpCookieStorage = cookieStorage
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: sessionConfiguration, delegate: streamDelegate, delegateQueue: nil)
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
        let cookies: [HTTPCookie]
        let cookieHeader: String?
        let userAgent: String?

        static func == (lhs: Configuration, rhs: Configuration) -> Bool {
            lhs.baseURL == rhs.baseURL
                && lhs.channel == rhs.channel
                && lhs.cookieHeader == rhs.cookieHeader
                && lhs.userAgent == rhs.userAgent
        }
    }
}

private final class EventStreamDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    var onConnected: (() -> Void)?
    var onEvent: ((LiveReplyEvent) -> Void)?
    var onClosed: ((String) -> Void)?

    private var buffer = ""
    private var rejectionReason = "实时桥接连接中断，正在重连…"

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            rejectionReason = "实时桥接：服务器没有返回 HTTP 响应"
            completionHandler(.cancel)
            return
        }
        guard http.statusCode == 200 else {
            rejectionReason = "实时桥接被拒绝：HTTP \(http.statusCode)"
            completionHandler(.cancel)
            return
        }
        guard response.mimeType == "text/event-stream" else {
            rejectionReason = "实时桥接响应格式错误：\(response.mimeType ?? "未知")"
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
        if let error = error as NSError? {
            onClosed?("实时桥接错误 \(error.code)：\(error.localizedDescription)")
        } else {
            onClosed?(rejectionReason)
        }
    }
}
