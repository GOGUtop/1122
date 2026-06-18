import SwiftUI
import WebKit

struct BrowserScreen: View {
    @EnvironmentObject private var appState: AppState
    let endpoint: TavernEndpoint

    @StateObject private var browser = BrowserModel()
    @State private var showControls = true
    @State private var showSettings = false
    @State private var showShare = false
    @State private var shareImage: UIImage?
    @State private var captureError: String?
    @State private var isMiniMode = false
    @State private var dockPosition = CGPoint(
        x: UserDefaults.standard.double(forKey: "dockX"),
        y: UserDefaults.standard.double(forKey: "dockY")
    )

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                WebView(
                    url: endpoint.url,
                    browser: browser,
                    reloadToken: appState.reloadToken
                )
                .ignoresSafeArea(edges: .bottom)

                if browser.isLoading {
                    ProgressView(value: browser.progress)
                        .progressViewStyle(.linear)
                        .tint(Color(red: 1, green: 0.83, blue: 0.35))
                        .frame(maxHeight: .infinity, alignment: .top)
                }

                if let error = browser.errorMessage {
                    errorCard(error)
                }

                if browser.isCapturing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在拼接长截图…")
                            .font(.subheadline.bold())
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .shadow(radius: 12)
                    .zIndex(10)
                }

                if isMiniMode {
                    miniStatusCard
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 18)
                        .padding(.trailing, 16)
                }

                FloatingDock(
                    showControls: $showControls,
                    isMiniMode: $isMiniMode,
                    position: $dockPosition,
                    opacity: appState.floatingOpacity,
                    containerSize: proxy.size,
                    canGoBack: browser.canGoBack,
                    isGenerating: browser.isGenerating,
                    onBack: { browser.webView?.goBack() },
                    onReload: { browser.webView?.reload() },
                    onPortal: { appState.activeEndpoint = nil },
                    onSwitch: { appState.showSwitcher = true },
                    onScreenshot: captureLongScreenshot,
                    onSettings: { showSettings = true }
                )
            }
        }
        .background(Color(red: 0.025, green: 0.04, blue: 0.07))
        .sheet(isPresented: $showSettings) {
            FloatingSettingsView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showShare) {
            if let shareImage {
                ActivitySheet(items: [shareImage])
            }
        }
        .alert("长截图失败", isPresented: Binding(
            get: { captureError != nil },
            set: { if !$0 { captureError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(captureError ?? "")
        }
    }

    private var miniStatusCard: some View {
        Button {
            isMiniMode = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: browser.isGenerating ? "ellipsis.message.fill" : "checkmark.circle.fill")
                    .foregroundStyle(browser.isGenerating ? .yellow : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(browser.isGenerating ? "正在回复…" : "回复已完成")
                        .font(.subheadline.bold())
                    Text("点此展开酒馆")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 8)
        }
        .buttonStyle(.plain)
    }

    private func captureLongScreenshot() {
        guard let webView = browser.webView else { return }
        browser.isCapturing = true
        LongScreenshotService().capture(webView: webView) { result in
            browser.isCapturing = false
            switch result {
            case .success(let image):
                shareImage = image
                showShare = true
            case .failure(let error):
                captureError = error.localizedDescription
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
            Text("云洞连接失败")
                .font(.headline)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("重新加载") {
                browser.errorMessage = nil
                browser.webView?.reload()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FloatingDock: View {
    @Binding var showControls: Bool
    @Binding var isMiniMode: Bool
    @Binding var position: CGPoint
    @State private var dragStart: CGPoint?

    let opacity: Double
    let containerSize: CGSize
    let canGoBack: Bool
    let isGenerating: Bool
    let onBack: () -> Void
    let onReload: () -> Void
    let onPortal: () -> Void
    let onSwitch: () -> Void
    let onScreenshot: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 9) {
            if showControls {
                VStack(spacing: 7) {
                    HStack(spacing: 4) {
                        dockButton("chevron.backward", disabled: !canGoBack, action: onBack)
                        dockButton("arrow.clockwise", action: onReload)
                        dockButton("house.fill", action: onPortal)
                        dockButton("gearshape.fill", action: onSettings)
                    }
                    .padding(5)
                    .background(.ultraThinMaterial, in: Capsule())

                    Button(action: onScreenshot) {
                        Label("长截图", systemImage: "rectangle.and.text.magnifyingglass")
                            .dockLabelStyle()
                    }

                    Button(action: onSwitch) {
                        Label("切换云洞", systemImage: "arrow.triangle.2.circlepath")
                            .dockLabelStyle()
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.18, blue: 0.34),
                                Color.black.opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .stroke(isGenerating ? Color.green : .white.opacity(0.28), lineWidth: isGenerating ? 3 : 1)
                Image(systemName: isGenerating ? "ellipsis.message.fill" : (showControls ? "drop.fill" : "drop"))
                    .font(.title2.bold())
                    .foregroundStyle(isGenerating ? .green : Color(red: 1, green: 0.92, blue: 0.62))
            }
            .frame(width: 58, height: 58)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
            .contentShape(Circle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                    showControls.toggle()
                }
            }
            .onLongPressGesture(minimumDuration: 0.65) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    isMiniMode.toggle()
                    showControls = false
                }
            }
        }
        .opacity(opacity)
        .position(resolvedPosition)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if dragStart == nil {
                        dragStart = position
                    }
                    guard let dragStart else { return }
                    position = clamped(
                        CGPoint(
                            x: dragStart.x + value.translation.width,
                            y: dragStart.y + value.translation.height
                        )
                    )
                }
                .onEnded { value in
                    if let dragStart {
                        position = clamped(
                            CGPoint(
                                x: dragStart.x + value.translation.width,
                                y: dragStart.y + value.translation.height
                            )
                        )
                    }
                    dragStart = nil
                    UserDefaults.standard.set(position.x, forKey: "dockX")
                    UserDefaults.standard.set(position.y, forKey: "dockY")
                }
        )
        .onAppear {
            if position.x <= 1 || position.y <= 1 {
                position = CGPoint(
                    x: max(95, containerSize.width - 95),
                    y: max(150, containerSize.height - 150)
                )
            }
        }
    }

    private var resolvedPosition: CGPoint {
        clamped(position)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 95), max(95, containerSize.width - 95)),
            y: min(max(point.y, 85), max(85, containerSize.height - 85))
        )
    }

    private func dockButton(
        _ icon: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 35, height: 35)
        }
        .foregroundStyle(disabled ? .white.opacity(0.28) : .white)
        .disabled(disabled)
    }
}

private extension View {
    func dockLabelStyle() -> some View {
        self
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .frame(height: 42)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.22)))
    }
}

private struct FloatingSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("悬浮球透明度") {
                    Slider(
                        value: Binding(
                            get: { appState.floatingOpacity },
                            set: { appState.saveFloatingOpacity($0) }
                        ),
                        in: 0.2...1
                    )
                    Text("当前：\(Int(appState.floatingOpacity * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("操作说明") {
                    Label("拖动：移动悬浮球", systemImage: "hand.draw")
                    Label("轻点：展开或收起工具", systemImage: "hand.tap")
                    Label("长按：切换 App 内小窗状态", systemImage: "rectangle.inset.filled")
                }
            }
            .navigationTitle("悬浮球设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

@MainActor
final class BrowserModel: ObservableObject {
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var errorMessage: String?
    @Published var isGenerating = false
    @Published var isCapturing = false
    weak var webView: WKWebView?
}

struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var browser: BrowserModel
    let reloadToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(browser: browser)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "tavernReply")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.replyObserverScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1 TavernSwitcher/1.0"
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        context.coordinator.observe(webView)
        browser.webView = webView
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            webView.reload()
        }
    }

    static let replyObserverScript = """
    (() => {
      if (window.__tavernReplyObserverInstalled) return;
      window.__tavernReplyObserverInstalled = true;
      var active = false;
      var lastText = '';
      var stableTicks = 0;
      var eventWired = false;
      const post = state => {
        try { window.webkit.messageHandlers.tavernReply.postMessage(state); } catch (_) {}
      };
      const wireNativeEvents = () => {
        if (eventWired) return true;
        try {
          const context = window.SillyTavern?.getContext?.();
          const source = context?.eventSource;
          const types = context?.event_types;
          if (!source || !types) return false;
          if (types.GENERATION_STARTED) {
            source.on(types.GENERATION_STARTED, () => post('started'));
          }
          if (types.GENERATION_ENDED) {
            source.on(types.GENERATION_ENDED, () => post('finished'));
          }
          eventWired = Boolean(types.GENERATION_STARTED && types.GENERATION_ENDED);
          return eventWired;
        } catch (_) {
          return false;
        }
      };
      wireNativeEvents();
      const wireTimer = setInterval(() => {
        if (wireNativeEvents()) clearInterval(wireTimer);
      }, 1000);
      const text = () => {
        const messages = document.querySelectorAll('#chat .mes, .chat .mes');
        const last = messages[messages.length - 1];
        return last ? (last.innerText || last.textContent || '') : '';
      };
      const generating = () => {
        const stop = document.querySelector('#mes_stop, .mes_stop');
        if (stop && getComputedStyle(stop).display !== 'none' && !stop.hidden) return true;
        const send = document.querySelector('#send_but');
        if (send && (send.classList.contains('displayNone') || send.disabled)) return true;
        return document.body.classList.contains('generating');
      };
      setInterval(() => {
        if (eventWired) return;
        const now = generating();
        const currentText = text();
        if (now && !active) {
          active = true;
          stableTicks = 0;
          post('started');
        }
        if (active) {
          stableTicks = currentText === lastText ? stableTicks + 1 : 0;
          lastText = currentText;
          if (!now && stableTicks >= 2) {
            active = false;
            stableTicks = 0;
            post('finished');
          }
        }
      }, 700);
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let browser: BrowserModel
        var observations: [NSKeyValueObservation] = []
        var lastReloadToken: UUID?

        init(browser: BrowserModel) {
            self.browser = browser
        }

        func observe(_ webView: WKWebView) {
            observations = [
                webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                    Task { @MainActor in self?.browser.progress = view.estimatedProgress }
                },
                webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                    Task { @MainActor in self?.browser.canGoBack = view.canGoBack }
                }
            ]
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                browser.isLoading = true
                browser.errorMessage = nil
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                browser.isLoading = false
                browser.canGoBack = webView.canGoBack
            }
            webView.evaluateJavaScript(WebView.replyObserverScript)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "tavernReply", let state = message.body as? String else { return }
            Task { @MainActor in
                if state == "started" {
                    browser.isGenerating = true
                    ReplyNotificationService.shared.generationStarted()
                } else if state == "finished" {
                    browser.isGenerating = false
                    ReplyNotificationService.shared.generationFinished()
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            show(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            show(error)
        }

        private func show(_ error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            Task { @MainActor in
                browser.isLoading = false
                browser.errorMessage = nsError.localizedDescription
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let requestURL = navigationAction.request.url {
                webView.load(URLRequest(url: requestURL))
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            guard let controller = webView.window?.rootViewController else {
                completionHandler()
                return
            }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            controller.present(alert, animated: true)
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            guard let controller = webView.window?.rootViewController else {
                completionHandler(false)
                return
            }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
            controller.present(alert, animated: true)
        }
    }
}
