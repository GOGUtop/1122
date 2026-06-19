import SwiftUI
import UniformTypeIdentifiers
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
    @State private var pipError: String?
    @State private var isSelectingRange = false
    @State private var rangeStart: CGFloat?
    @State private var rangeMessage = "请先滚到要截图的开头，然后点“设为开头”。"
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

                if isSelectingRange {
                    RangeCaptureBar(
                        message: rangeMessage,
                        hasStart: rangeStart != nil,
                        onStart: markRangeStart,
                        onFinish: captureSelectedRange,
                        onCancel: {
                            isSelectingRange = false
                            rangeStart = nil
                        }
                    )
                    .zIndex(9)
                }

                FloatingDock(
                    showControls: $showControls,
                    position: $dockPosition,
                    opacity: appState.floatingOpacity,
                    containerSize: proxy.size,
                    canGoBack: browser.canGoBack,
                    isGenerating: browser.isGenerating,
                    onBack: { browser.webView?.goBack() },
                    onReload: { browser.webView?.reload() },
                    onPortal: { appState.activeEndpoint = nil },
                    onSwitch: { appState.showSwitcher = true },
                    onScreenshot: beginRangeCapture,
                    onSettings: { showSettings = true },
                    onPictureInPicture: {
                        if browser.pictureInPicture.toggle() {
                            showControls = false
                        } else {
                            pipError = "画中画没有启动：请先等网页完全加载，再点工具里的“画中画”按钮；如果仍不行，请确认系统设置里没有关闭画中画。"
                        }
                    }
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
        .alert("画中画", isPresented: Binding(
            get: { pipError != nil },
            set: { if !$0 { pipError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(pipError ?? "")
        }
    }

    private func beginRangeCapture() {
        isSelectingRange = true
        rangeStart = nil
        rangeMessage = "请先滚到要截图的开头，然后点“设为开头”。"
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            showControls = false
        }
    }

    private func markRangeStart() {
        guard let webView = browser.webView else { return }
        LongScreenshotService().currentScrollTop(webView: webView) { result in
            switch result {
            case .success(let value):
                rangeStart = value
                rangeMessage = "开头已记录。现在滑到要结束的位置，点“截到当前位置”。"
            case .failure(let error):
                captureError = error.localizedDescription
            }
        }
    }

    private func captureSelectedRange() {
        guard let webView = browser.webView else { return }
        guard let start = rangeStart else {
            captureError = LongScreenshotService.CaptureError.invalidRange.localizedDescription
            return
        }
        LongScreenshotService().currentScrollTop(webView: webView) { result in
            switch result {
            case .success(let end):
                isSelectingRange = false
                browser.isCapturing = true
                LongScreenshotService().capture(webView: webView, startOffset: start, endOffset: end) { result in
                    browser.isCapturing = false
                    rangeStart = nil
                    switch result {
                    case .success(let image):
                        shareImage = image
                        showShare = true
                    case .failure(let error):
                        captureError = error.localizedDescription
                    }
                }
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


private struct RangeCaptureBar: View {
    let message: String
    let hasStart: Bool
    let onStart: () -> Void
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(.white.opacity(0.45))
                .frame(width: 38, height: 5)
            Text("选择长截图范围")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                Button(hasStart ? "重设开头" : "设为开头", action: onStart)
                    .buttonStyle(.borderedProminent)
                Button("截到当前位置", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasStart)
            }
            .font(.subheadline.bold())
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

private struct FloatingDock: View {
    @Binding var showControls: Bool
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
    let onPictureInPicture: () -> Void

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
                        Label("选区长截图", systemImage: "rectangle.and.text.magnifyingglass")
                            .dockLabelStyle()
                    }

                    Button(action: onPictureInPicture) {
                        Label("画中画", systemImage: "pip")
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
                    if showControls {
                        position = openMenuPosition(from: position)
                    } else {
                        position = snapToEdge(position)
                    }
                }
                UserDefaults.standard.set(position.x, forKey: "dockX")
                UserDefaults.standard.set(position.y, forKey: "dockY")
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .onEnded { _ in onPictureInPicture() }
            )
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
                        let raw = clamped(
                            CGPoint(
                                x: dragStart.x + value.translation.width,
                                y: dragStart.y + value.translation.height
                            )
                        )
                        position = showControls ? raw : snapToEdge(raw)
                    }
                    dragStart = nil
                    UserDefaults.standard.set(position.x, forKey: "dockX")
                    UserDefaults.standard.set(position.y, forKey: "dockY")
                }
        )
        .onAppear {
            if position.x <= 1 || position.y <= 1 {
                position = CGPoint(
                    x: max(42, containerSize.width - 42),
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
            x: min(max(point.x, 42), max(42, containerSize.width - 42)),
            y: min(max(point.y, 85), max(85, containerSize.height - 85))
        )
    }

    private func snapToEdge(_ point: CGPoint) -> CGPoint {
        let leftX: CGFloat = 42
        let rightX = max(42, containerSize.width - 42)
        return CGPoint(
            x: point.x < containerSize.width / 2 ? leftX : rightX,
            y: point.y
        )
    }

    private func openMenuPosition(from point: CGPoint) -> CGPoint {
        // 工具面板展开时不要吸边，否则按钮会顶到屏幕边缘不好点。
        let inset: CGFloat = 118
        let x = point.x < containerSize.width / 2 ? inset : max(inset, containerSize.width - inset)
        return clamped(CGPoint(x: x, y: point.y))
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
    @StateObject private var sounds = NotificationSoundSettings.shared
    @State private var importingOutcome: ReplyOutcome?
    @State private var soundError: String?

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

                Section("回复提示音") {
                    ForEach(ReplyOutcome.allCases) { outcome in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(outcome.title)
                                Text(sounds.displayName(for: outcome))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("试听") { sounds.preview(outcome: outcome) }
                            Button("导入") { importingOutcome = outcome }
                            Button("默认") { sounds.restoreBuiltInSound(for: outcome) }
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("支持 CAF、WAV、AIF、AIFF，单个音频不超过 30 秒。每次回复只响一次并震动一次。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("顶部横幅通知") {
                    Button {
                        ReplyNotificationService.shared.sendBannerTest()
                    } label: {
                        Label("测试顶部横幅", systemImage: "rectangle.topthird.inset.filled")
                    }
                    Text("若测试通知只出现在锁屏或通知中心，请到 iPhone 设置 → 通知 → 云洞酒馆，开启“横幅”，并将横幅样式设为临时或持续。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("操作说明") {
                    Label("拖动：移动悬浮球", systemImage: "hand.draw")
                    Label("轻点：展开或收起工具", systemImage: "hand.tap")
                    Label("长按：启动系统画中画小窗", systemImage: "pip")
                    Text("启动后滑回桌面或切换到其他 App，小窗会继续悬浮。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("悬浮球设置")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: Binding(
                    get: { importingOutcome != nil },
                    set: { if !$0 { importingOutcome = nil } }
                ),
                allowedContentTypes: [.audio]
            ) { result in
                guard let outcome = importingOutcome else { return }
                importingOutcome = nil
                do {
                    try sounds.importSound(from: result.get(), for: outcome)
                } catch {
                    soundError = error.localizedDescription
                }
            }
            .alert("提示音导入失败", isPresented: Binding(
                get: { soundError != nil },
                set: { if !$0 { soundError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(soundError ?? "")
            }
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
    var currentGenerationId: String?
    var generationStartedAt: Date?
    let pictureInPicture = WebPictureInPictureController()
    let liveBridge = LiveReplyBridge()
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
        configuration.userContentController.add(context.coordinator, name: "tavernBridgeConfig")
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
        browser.pictureInPicture.attach(to: webView)
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
      const channelKey = '__tavernLiveChannel';
      let liveChannel = localStorage.getItem(channelKey);
      if (!liveChannel) {
        liveChannel = (crypto.randomUUID?.() || `${Date.now()}-${Math.random()}`).replace(/[^a-zA-Z0-9-]/g, '');
        localStorage.setItem(channelKey, liveChannel);
      }
      try {
        window.webkit.messageHandlers.tavernBridgeConfig.postMessage({
          channel: liveChannel,
          origin: location.origin
        });
      } catch (_) {}

      const originalFetch = window.fetch.bind(window);
      window.fetch = async (input, init) => {
        const request = new Request(input, init);
        const url = new URL(request.url, location.href);
        const isGeneration = url.origin === location.origin
          && url.pathname.includes('/api/')
          && (
            url.pathname.includes('/generate')
            || url.pathname.includes('/chat-completions')
            || url.pathname.includes('/text-completions')
          )
          && !url.pathname.includes('/api/plugins/tavern-live-bridge/');
        if (!isGeneration) return originalFetch(input, init);

        const headers = new Headers(request.headers);
        headers.set('x-tavern-live-channel', liveChannel);
        headers.set('x-tavern-live-target', `${url.pathname}${url.search}`);
        const proxyURL = new URL('/api/plugins/tavern-live-bridge/proxy', location.origin);
        const options = {
          method: request.method,
          headers,
          credentials: 'include',
          cache: 'no-store',
          signal: request.signal
        };
        if (request.method !== 'GET' && request.method !== 'HEAD') {
          options.body = await request.clone().arrayBuffer();
        }
        return originalFetch(proxyURL, options);
      };

      var active = false;
      var lastText = '';
      var stableTicks = 0;
      var eventWired = false;
      var fallbackId = '';
      const post = payload => {
        try { window.webkit.messageHandlers.tavernReply.postMessage(payload); } catch (_) {}
      };
      const wireNativeEvents = () => {
        if (eventWired) return true;
        try {
          const context = window.SillyTavern?.getContext?.();
          const source = context?.eventSource;
          const types = context?.event_types;
          if (!source || !types) return false;
          if (types.GENERATION_STARTED) {
            source.on(types.GENERATION_STARTED, () => {
              fallbackId = `fallback-${Date.now()}`;
              post({ type: 'started', id: fallbackId });
            });
          }
          if (types.GENERATION_STOPPED) {
            source.on(types.GENERATION_STOPPED, () => {
              post({ type: 'finished', id: fallbackId, reason: 'truncated', text: text() });
            });
          }
          if (types.GENERATION_ENDED) {
            source.on(types.GENERATION_ENDED, () => setTimeout(() => {
              const value = text();
              post({
                type: 'finished',
                id: fallbackId,
                reason: value.trim() ? 'complete' : 'empty',
                text: value
              });
            }, 100));
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
          fallbackId = `fallback-${Date.now()}`;
          post({ type: 'started', id: fallbackId });
        }
        if (active) {
          stableTicks = currentText === lastText ? stableTicks + 1 : 0;
          lastText = currentText;
          if (!now && stableTicks >= 2) {
            active = false;
            stableTicks = 0;
            post({
              type: 'finished',
              id: fallbackId,
              reason: currentText.trim() ? 'complete' : 'empty',
              text: currentText
            });
          }
        }
      }, 700);
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let browser: BrowserModel
        var observations: [NSKeyValueObservation] = []
        var lastReloadToken: UUID?
        private var completionPollTimer: Timer?
        private var completionStableTicks = 0
        private var fallbackGenerationId: String?

        init(browser: BrowserModel) {
            self.browser = browser
            browser.liveBridge.onConnectionChange = { [weak browser] connected, text in
                guard let browser else { return }
                browser.pictureInPicture.updateBridgeStatus(text, connected: connected)
            }
            browser.liveBridge.onEvent = { [weak browser] event in
                guard let browser else { return }
                let id = event.generationId ?? "live-\(UUID().uuidString)"
                switch event.type {
                case "start":
                    let cycleId = browser.currentGenerationId ?? "cycle-\(UUID().uuidString)"
                    browser.currentGenerationId = cycleId
                    browser.generationStartedAt = browser.generationStartedAt ?? Date()
                    browser.isGenerating = true
                    browser.pictureInPicture.generationStarted(character: event.character)
                    ReplyNotificationService.shared.generationStarted(id: cycleId)
                case "snapshot":
                    let cycleId = browser.currentGenerationId ?? "cycle-\(UUID().uuidString)"
                    browser.currentGenerationId = cycleId
                    browser.generationStartedAt = browser.generationStartedAt ?? Date()
                    browser.isGenerating = true
                    browser.pictureInPicture.generationStarted(character: event.character)
                    ReplyNotificationService.shared.generationStarted(id: cycleId)
                    browser.pictureInPicture.updateReply(
                        text: event.text ?? "",
                        character: event.character
                    )
                case "token":
                    browser.isGenerating = true
                    browser.pictureInPicture.updateReply(
                        text: event.text ?? "",
                        character: event.character
                    )
                case "end":
                    // 页面启动时偶尔会冒出一个无对应 start 的 end，不能把它当空回。
                    guard let resolvedId = browser.currentGenerationId,
                          browser.generationStartedAt != nil else { return }
                    let outcome = ReplyOutcome(rawValue: event.reason ?? "") ?? ((event.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .complete)
                    browser.isGenerating = false
                    browser.pictureInPicture.generationFinished(text: event.text ?? "", outcome: outcome)
                    ReplyNotificationService.shared.generationFinished(id: resolvedId, outcome: outcome)
                    browser.currentGenerationId = nil
                    browser.generationStartedAt = nil
                default:
                    break
                }
            }
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
            if message.name == "tavernBridgeConfig",
               let body = message.body as? [String: Any],
               let channel = body["channel"] as? String,
               let origin = body["origin"] as? String,
               let baseURL = URL(string: origin),
               let webView = browser.webView {
                Task { @MainActor in
                    browser.liveBridge.connect(baseURL: baseURL, channel: channel, webView: webView)
                }
                return
            }
            guard message.name == "tavernReply",
                  let payload = message.body as? [String: Any],
                  let type = payload["type"] as? String else { return }
            Task { @MainActor in
                let id = payload["id"] as? String ?? "fallback-\(UUID().uuidString)"
                if type == "started" {
                    let resolvedId = browser.currentGenerationId ?? "cycle-\(UUID().uuidString)"
                    browser.currentGenerationId = resolvedId
                    browser.generationStartedAt = browser.generationStartedAt ?? Date()
                    fallbackGenerationId = resolvedId
                    browser.isGenerating = true
                    browser.pictureInPicture.generationStarted(character: nil)
                    ReplyNotificationService.shared.generationStarted(id: resolvedId)
                    if let webView = browser.webView { startCompletionPolling(webView) }
                } else if type == "finished" {
                    guard let resolvedId = browser.currentGenerationId,
                          browser.generationStartedAt != nil else { return }
                    let text = payload["text"] as? String ?? ""
                    let outcome = ReplyOutcome(rawValue: payload["reason"] as? String ?? "")
                        ?? (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .complete)
                    browser.isGenerating = false
                    stopCompletionPolling()
                    browser.pictureInPicture.generationFinished(text: text, outcome: outcome)
                    ReplyNotificationService.shared.generationFinished(id: resolvedId, outcome: outcome)
                    browser.currentGenerationId = nil
                    browser.generationStartedAt = nil
                    fallbackGenerationId = nil
                }
            }
        }


        private func startCompletionPolling(_ webView: WKWebView) {
            completionPollTimer?.invalidate()
            completionStableTicks = 0
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                let script = """
                (() => {
                  try {
                    const stop = document.querySelector('#mes_stop, .mes_stop');
                    if (stop && getComputedStyle(stop).display !== 'none' && !stop.hidden) return true;
                    const send = document.querySelector('#send_but');
                    if (send && (send.classList.contains('displayNone') || send.disabled)) return true;
                    if (document.body.classList.contains('generating')) return true;
                    return false;
                  } catch (_) { return true; }
                })();
                """
                webView.evaluateJavaScript(script) { result, _ in
                    Task { @MainActor in
                        guard self.browser.isGenerating else { return }
                        let stillGenerating = (result as? Bool) ?? true
                        if stillGenerating {
                            self.completionStableTicks = 0
                        } else {
                            self.completionStableTicks += 1
                            if self.completionStableTicks >= 3 {
                                guard let id = self.browser.currentGenerationId,
                                      self.browser.generationStartedAt != nil else {
                                    self.stopCompletionPolling()
                                    return
                                }
                                self.browser.isGenerating = false
                                self.stopCompletionPolling()
                                self.browser.currentGenerationId = nil
                                self.browser.generationStartedAt = nil
                                self.fallbackGenerationId = nil
                                ReplyNotificationService.shared.generationFinished(id: id, outcome: .complete)
                            }
                        }
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            completionPollTimer = timer
        }

        private func stopCompletionPolling() {
            completionPollTimer?.invalidate()
            completionPollTimer = nil
            completionStableTicks = 0
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
