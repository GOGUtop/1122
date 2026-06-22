import SwiftUI
import UniformTypeIdentifiers
import UIKit
import WebKit

struct BrowserScreen: View {
    @EnvironmentObject private var appState: AppState
    let endpoint: TavernEndpoint

    @StateObject private var browser = BrowserModel()
    @State private var showControls = false
    @State private var showSettings = false
    @State private var showShare = false
    @State private var shareImage: UIImage?
    @State private var captureError: String?
    @State private var pipError: String?
    @State private var nativeInputText = ""
    @State private var nativeInputToast: String?
    @FocusState private var nativeInputFocused: Bool
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
                    reloadToken: appState.reloadToken,
                    pageZoom: appState.pageZoom,
                    bottomSafePadding: appState.webBottomPadding
                )

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

                if appState.nativeInputEnabled && !isSelectingRange {
                    NativeInputBar(
                        text: $nativeInputText,
                        focused: $nativeInputFocused,
                        isGenerating: browser.isGenerating,
                        onSend: sendNativeInput
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(8)
                }

                if let nativeInputToast {
                    LiquidToast(text: nativeInputToast)
                        .padding(.top, 62)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(11)
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
        .onAppear { updateScreenKeepAlive() }
        .onDisappear { BackgroundKeepAliveService.shared.stop(reason: "screen") }
        .onChange(of: appState.enhancedKeepAlive) { _ in updateScreenKeepAlive() }
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

    private func updateScreenKeepAlive() {
        if appState.enhancedKeepAlive {
            BackgroundKeepAliveService.shared.start(reason: "screen")
        } else {
            BackgroundKeepAliveService.shared.stop(reason: "screen")
        }
    }

    private func sendNativeInput() {
        let raw = nativeInputText
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        browser.sendNativeMessage(raw) { success, message in
            if success {
                nativeInputText = ""
                nativeInputFocused = false
                showNativeToast("已发送")
            } else {
                showNativeToast(message ?? "发送失败，请确认网页已加载完成")
            }
        }
    }

    private func showNativeToast(_ text: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            nativeInputToast = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.18)) {
                if nativeInputToast == text { nativeInputToast = nil }
            }
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


private struct NativeInputBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let isGenerating: Bool
    let onSend: () -> Void

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(isGenerating ? "AI 正在回复中…" : "输入消息，直接发送到酒馆")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 17)
                        .padding(.vertical, 15)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .focused(focused)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .tint(Color(red: 0.78, green: 0.90, blue: 1.0))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 42, maxHeight: 96)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .background(
                LinearGradient(
                    colors: [.white.opacity(0.18), .white.opacity(0.08), .white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )

            Button(action: onSend) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: canSend
                                    ? [Color(red: 0.48, green: 0.82, blue: 1.0), Color(red: 0.25, green: 0.48, blue: 1.0)]
                                    : [.white.opacity(0.18), .white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: isGenerating ? "hourglass" : "paperplane.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(canSend ? .white : .white.opacity(0.45))
                }
                .frame(width: 52, height: 52)
                .shadow(color: canSend ? Color.blue.opacity(0.38) : .clear, radius: 12, y: 5)
            }
            .disabled(!canSend)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.42), .white.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.24), radius: 20, y: 10)
    }
}

private struct LiquidToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.26)))
            .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
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
        VStack(alignment: .trailing, spacing: 12) {
            if showControls {
                liquidPanel
                    .transition(.scale(scale: 0.88, anchor: .bottomTrailing).combined(with: .opacity))
            }

            liquidOrb
        }
        .opacity(opacity)
        .position(resolvedPosition)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if dragStart == nil { dragStart = position }
                    guard let dragStart else { return }
                    position = clamped(
                        CGPoint(x: dragStart.x + value.translation.width,
                                y: dragStart.y + value.translation.height)
                    )
                }
                .onEnded { value in
                    if let dragStart {
                        let raw = clamped(
                            CGPoint(x: dragStart.x + value.translation.width,
                                    y: dragStart.y + value.translation.height)
                        )
                        position = showControls ? openMenuPosition(from: raw) : snapToEdge(raw)
                    }
                    dragStart = nil
                    savePosition()
                }
        )
        .onAppear {
            if position.x <= 1 || position.y <= 1 {
                position = CGPoint(x: max(42, containerSize.width - 42), y: max(150, containerSize.height - 170))
            }
            if !showControls { position = snapToEdge(position) }
            savePosition()
        }
    }

    private var liquidPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(isGenerating ? Color.green.opacity(0.2) : Color.orange.opacity(0.20))
                        .frame(width: 36, height: 36)
                    Image(systemName: isGenerating ? "sparkles" : "pawprint.fill")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(isGenerating ? .green : Color(red: 1, green: 0.86, blue: 0.44))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("云洞工具")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                    Text(isGenerating ? "AI 正在回复中" : "液态快捷面板")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.76)) {
                        showControls = false
                        position = snapToEdge(position)
                    }
                    savePosition()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 31, height: 31)
                        .background(.white.opacity(0.13), in: Circle())
                }
                .foregroundStyle(.white.opacity(0.9))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                liquidTool("选区截图", "rectangle.and.text.magnifyingglass", action: onScreenshot)
                liquidTool("画中画", "pip.fill", action: onPictureInPicture)
                liquidTool("切换云洞", "arrow.triangle.2.circlepath", action: onSwitch)
                liquidTool("设置", "slider.horizontal.3", action: onSettings)
            }

            HStack(spacing: 8) {
                liquidMini("chevron.backward", disabled: !canGoBack, action: onBack)
                liquidMini("arrow.clockwise", action: onReload)
                liquidMini("house.fill", action: onPortal)
            }
        }
        .foregroundStyle(.white)
        .padding(15)
        .frame(width: 258)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .white.opacity(0.055), Color.blue.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.34), radius: 28, x: 0, y: 14)
    }

    private var liquidOrb: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.95),
                            Color(red: 0.58, green: 0.85, blue: 1.0).opacity(0.60),
                            Color(red: 0.11, green: 0.17, blue: 0.34).opacity(0.96),
                            .black.opacity(0.94)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 60
                    )
                )
            Circle()
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
            Circle()
                .trim(from: 0.08, to: isGenerating ? 0.94 : 0.64)
                .stroke(
                    isGenerating ? Color.green : Color(red: 1, green: 0.78, blue: 0.26),
                    style: StrokeStyle(lineWidth: 3.4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(4)
            Image(systemName: showControls ? "xmark" : (isGenerating ? "sparkles" : "drop.fill"))
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(isGenerating ? .green : Color(red: 1, green: 0.88, blue: 0.48))
        }
        .frame(width: 62, height: 62)
        .shadow(color: .black.opacity(0.38), radius: 15, y: 8)
        .contentShape(Circle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                showControls.toggle()
                position = showControls ? openMenuPosition(from: position) : snapToEdge(position)
            }
            savePosition()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in onPictureInPicture() }
        )
    }

    private func liquidTool(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .heavy))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.12), in: Circle())
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
            .background(
                LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.white.opacity(0.14)))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func liquidMini(_ icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .black))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(.white.opacity(disabled ? 0.05 : 0.13), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12)))
        }
        .disabled(disabled)
        .foregroundStyle(disabled ? .white.opacity(0.28) : .white)
        .buttonStyle(PressableButtonStyle())
    }

    private var resolvedPosition: CGPoint { clamped(position) }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 42), max(42, containerSize.width - 42)),
            y: min(max(point.y, 85), max(85, containerSize.height - 110))
        )
    }

    private func snapToEdge(_ point: CGPoint) -> CGPoint {
        let leftX: CGFloat = 42
        let rightX = max(42, containerSize.width - 42)
        return CGPoint(x: point.x < containerSize.width / 2 ? leftX : rightX, y: clamped(point).y)
    }

    private func openMenuPosition(from point: CGPoint) -> CGPoint {
        let inset: CGFloat = 136
        let x = point.x < containerSize.width / 2 ? inset : max(inset, containerSize.width - inset)
        return clamped(CGPoint(x: x, y: point.y))
    }

    private func savePosition() {
        UserDefaults.standard.set(position.x, forKey: "dockX")
        UserDefaults.standard.set(position.y, forKey: "dockY")
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
    @AppStorage("mirrorPiPAlertToBanner") private var mirrorPiPAlertToBanner = true

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.025, green: 0.055, blue: 0.10), Color(red: 0.06, green: 0.09, blue: 0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        settingsCard("原生输入栏", systemImage: "keyboard") {
                            Toggle("启用底部原生输入栏", isOn: Binding(
                                get: { appState.nativeInputEnabled },
                                set: { appState.saveNativeInputEnabled($0) }
                            ))
                            .tint(Color(red: 0.45, green: 0.78, blue: 1.0))
                            Text("开启后可以直接用 App 底部输入框发送消息，不再依赖网页右下角按钮。")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.62))
                        }

                        settingsCard("后台保活", systemImage: "bolt.heart.fill") {
                            Toggle("增强后台保活", isOn: Binding(
                                get: { appState.enhancedKeepAlive },
                                set: { appState.saveEnhancedKeepAlive($0) }
                            ))
                            .tint(Color(red: 0.45, green: 0.78, blue: 1.0))
                            Text("会维持静音音频心跳和短时后台任务。iOS 仍可能限制长时间后台，但比普通 WebView 更稳。")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.62))
                        }

                        settingsCard("页面舒适度", systemImage: "iphone.gen3") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("页面比例")
                                    Spacer()
                                    Text("\(Int(appState.pageZoom * 100))%")
                                        .foregroundStyle(.white.opacity(0.64))
                                }
                                Slider(
                                    value: Binding(get: { appState.pageZoom }, set: { appState.savePageZoom($0) }),
                                    in: 0.88...1.0
                                )
                                HStack {
                                    Text("底部安全距离")
                                    Spacer()
                                    Text("\(Int(appState.bottomSafePadding)) px")
                                        .foregroundStyle(.white.opacity(0.64))
                                }
                                Slider(
                                    value: Binding(get: { appState.bottomSafePadding }, set: { appState.saveBottomSafePadding($0) }),
                                    in: 10...52
                                )
                            }
                            .tint(Color(red: 0.50, green: 0.82, blue: 1.0))
                        }

                        settingsCard("悬浮球", systemImage: "drop.fill") {
                            HStack {
                                Text("透明度")
                                Spacer()
                                Text("\(Int(appState.floatingOpacity * 100))%")
                                    .foregroundStyle(.white.opacity(0.64))
                            }
                            Slider(
                                value: Binding(get: { appState.floatingOpacity }, set: { appState.saveFloatingOpacity($0) }),
                                in: 0.2...1
                            )
                            .tint(Color(red: 0.50, green: 0.82, blue: 1.0))
                        }

                        settingsCard("画中画完成提示", systemImage: "pip.fill") {
                            Toggle("画中画提示同步为系统横幅", isOn: $mirrorPiPAlertToBanner)
                                .tint(Color(red: 0.45, green: 0.78, blue: 1.0))
                            Button {
                                ReplyNotificationService.shared.sendBannerTest()
                            } label: {
                                Label("测试顶部横幅和震动", systemImage: "bell.badge.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            Text("系统横幅只由画中画完成状态条映射一次，避免三路检测重复弹。")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.62))
                        }

                        settingsCard("手势", systemImage: "hand.tap.fill") {
                            Label("拖动：移动悬浮球", systemImage: "hand.draw")
                            Label("轻点：展开液态工具面板", systemImage: "hand.tap")
                            Label("长按：启动系统画中画", systemImage: "pip")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("液态设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func settingsCard<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .black))
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.12), in: Circle())
                Text(title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                Spacer()
            }
            content()
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
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
    var serverGenerationId: String?
    var generationStartedAt: Date?
    var lastReplyText = ""
    var generationHadVisibleText = false
    let pictureInPicture = WebPictureInPictureController()
    let liveBridge = LiveReplyBridge()
    weak var webView: WKWebView?

    func sendNativeMessage(_ text: String, completion: @escaping (Bool, String?) -> Void) {
        guard let webView else {
            completion(false, "网页还没加载完成")
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else {
            completion(false, "文本编码失败")
            return
        }

        let script = """
        (async () => {
          const text = \(json);
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          const textarea = document.querySelector('#send_textarea, textarea[name="text"], textarea');
          if (!textarea) return { ok: false, error: '未找到酒馆输入框' };
          textarea.focus();
          const proto = window.HTMLTextAreaElement && Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
          if (proto && proto.set) proto.set.call(textarea, text); else textarea.value = text;
          try {
            textarea.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
          } catch (_) {
            textarea.dispatchEvent(new Event('input', { bubbles: true }));
          }
          textarea.dispatchEvent(new Event('change', { bubbles: true }));
          await sleep(90);
          const send = document.querySelector('#send_but, button[title*="发送"], button[aria-label*="发送"], button[title*="Send"], button[aria-label*="Send"]');
          if (!send) return { ok: false, error: '未找到发送按钮' };
          if (send.disabled) return { ok: false, error: '发送按钮暂不可用' };
          send.click();
          return { ok: true };
        })();
        """

        webView.evaluateJavaScript(script) { result, error in
            Task { @MainActor in
                if let error {
                    completion(false, error.localizedDescription)
                    return
                }
                if let dict = result as? [String: Any] {
                    let ok = dict["ok"] as? Bool ?? false
                    completion(ok, dict["error"] as? String)
                } else {
                    completion(false, "发送脚本没有返回结果")
                }
            }
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var browser: BrowserModel
    let reloadToken: UUID
    let pageZoom: Double
    let bottomSafePadding: Double

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
        configuration.userContentController.add(context.coordinator, name: "tavernTools")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: TavernToolsScript.source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.comfortScript(pageZoom: pageZoom, bottomSafePadding: bottomSafePadding),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.replyObserverScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        applyComfort(to: webView)
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
        applyComfort(to: webView)
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            webView.reload()
        }
    }

    private func applyComfort(to webView: WKWebView) {
        webView.pageZoom = CGFloat(pageZoom)
        let bottom = CGFloat(bottomSafePadding)
        var inset = webView.scrollView.contentInset
        inset.bottom = bottom
        webView.scrollView.contentInset = inset
        var indicatorInset = webView.scrollView.verticalScrollIndicatorInsets
        indicatorInset.bottom = bottom
        webView.scrollView.verticalScrollIndicatorInsets = indicatorInset
        let script = Self.comfortScript(pageZoom: pageZoom, bottomSafePadding: bottomSafePadding)
        webView.evaluateJavaScript(script)
    }

    private static func comfortScript(pageZoom: Double, bottomSafePadding: Double) -> String {
        let bottom = max(0, min(80, bottomSafePadding))
        return """
        (() => {
          const bottom = '\(Int(bottom))px';
          let style = document.getElementById('tavern-ios-comfort-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'tavern-ios-comfort-style';
            document.head.appendChild(style);
          }
          const nativeInput = \(bottom > 80 ? "true" : "false");
          document.body.classList.toggle('tavern-ios-native-input', nativeInput);
          style.textContent = `
            :root { --tavern-ios-bottom: ${bottom}; }
            body { padding-bottom: max(10px, var(--tavern-ios-bottom)) !important; }
            #send_form, #form_sheld, .send_form, form:has(#send_textarea) {
              bottom: max(10px, env(safe-area-inset-bottom)) !important;
              margin-bottom: max(var(--tavern-ios-bottom), env(safe-area-inset-bottom)) !important;
              padding-bottom: max(8px, env(safe-area-inset-bottom)) !important;
            }
            body.tavern-ios-native-input #send_form,
            body.tavern-ios-native-input #form_sheld,
            body.tavern-ios-native-input .send_form,
            body.tavern-ios-native-input form:has(#send_textarea) {
              opacity: 0.02 !important;
              pointer-events: none !important;
              transform: translateY(88px) !important;
            }
            #send_but, #mes_stop, button[title*="发送"], button[aria-label*="发送"], button[title*="Send"], button[aria-label*="Send"] {
              min-width: 46px !important;
              min-height: 46px !important;
            }
            #send_textarea, textarea {
              min-height: 44px !important;
            }
          `;
        })();
        """
    }

    static let currentReplyTextScript = """
    (() => {
      const messages = document.querySelectorAll('#chat .mes, .chat .mes');
      const last = messages[messages.length - 1];
      return last ? (last.innerText || last.textContent || '') : '';
    })();
    """

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
            }, 650));
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
            super.init()
            browser.liveBridge.onConnectionChange = { [weak browser] connected, text in
                guard let browser else { return }
                browser.pictureInPicture.updateBridgeStatus(text, connected: connected)
            }
            browser.liveBridge.onEvent = { [weak self] event in
                guard let self else { return }
                switch event.type {
                case "start":
                    self.beginGeneration(serverGenerationId: event.generationId, character: event.character)
                case "snapshot":
                    self.beginGeneration(serverGenerationId: event.generationId, character: event.character)
                    self.updateGenerationText(event.text ?? "", character: event.character)
                case "token":
                    self.updateGenerationText(event.text ?? "", character: event.character)
                case "end":
                    self.finishGenerationSafely(
                        text: event.text ?? "",
                        reason: event.reason,
                        serverGenerationId: event.generationId
                    )
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
            webView.evaluateJavaScript(TavernToolsScript.source)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "tavernTools",
               let payload = message.body as? [String: Any] {
                handleTavernTools(payload)
                return
            }
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
                if type == "started" {
                    let resolvedId = beginGeneration(serverGenerationId: nil, character: nil)
                    fallbackGenerationId = resolvedId
                    if let webView = browser.webView { startCompletionPolling(webView) }
                } else if type == "finished" {
                    finishGenerationSafely(
                        text: payload["text"] as? String ?? "",
                        reason: payload["reason"] as? String,
                        serverGenerationId: nil
                    )
                }
            }
        }


        @discardableResult
        private func beginGeneration(serverGenerationId: String?, character: String?) -> String {
            let isNewCycle = browser.currentGenerationId == nil
            let resolvedId = browser.currentGenerationId ?? "cycle-\(UUID().uuidString)"
            browser.currentGenerationId = resolvedId
            if let serverGenerationId {
                // 服务端桥接的 start/snapshot/end 必须属于同一个 generationId，避免旧历史 end 被当作新一轮空回。
                browser.serverGenerationId = serverGenerationId
            }
            browser.generationStartedAt = browser.generationStartedAt ?? Date()
            browser.isGenerating = true
            if isNewCycle {
                browser.lastReplyText = ""
                browser.generationHadVisibleText = false
                browser.pictureInPicture.generationStarted(character: character)
                ReplyNotificationService.shared.generationStarted(id: resolvedId)
            }
            return resolvedId
        }

        private func updateGenerationText(_ text: String, character: String?) {
            let resolvedId = beginGeneration(serverGenerationId: nil, character: character)
            _ = resolvedId
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                browser.lastReplyText = text
                browser.generationHadVisibleText = true
            }
            browser.pictureInPicture.updateReply(text: text.isEmpty ? browser.lastReplyText : text, character: character)
        }

        private func finishGenerationSafely(text: String, reason: String?, serverGenerationId: String?) {
            if let serverGenerationId {
                // 只接受本轮服务端 start/snapshot 对应的 end。这样可以过滤 App 重连时服务端 replay 的旧空回。
                guard browser.serverGenerationId == serverGenerationId else { return }
            }
            guard let resolvedId = browser.currentGenerationId,
                  let startedAt = browser.generationStartedAt else { return }

            let rawText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? browser.lastReplyText : text
            let rawOutcome = ReplyOutcome(rawValue: reason ?? "")
                ?? (rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .complete)

            if rawOutcome == .empty && rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // 空回最容易误判：先再读一次 DOM。只有本轮足够久且确实没有文字，才允许提示空回。
                guard Date().timeIntervalSince(startedAt) >= 3.0 else { return }
                if let webView = browser.webView {
                    webView.evaluateJavaScript(WebView.currentReplyTextScript) { [weak self] result, _ in
                        Task { @MainActor in
                            guard let self else { return }
                            let domText = result as? String ?? ""
                            self.completeFinish(
                                id: resolvedId,
                                text: domText,
                                requestedOutcome: domText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .complete
                            )
                        }
                    }
                } else {
                    completeFinish(id: resolvedId, text: rawText, requestedOutcome: .empty)
                }
                return
            }

            completeFinish(id: resolvedId, text: rawText, requestedOutcome: rawOutcome)
        }

        private func completeFinish(id: String, text: String, requestedOutcome: ReplyOutcome) {
            let visibleText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? browser.lastReplyText : text
            var outcome = requestedOutcome
            if outcome == .empty,
               browser.generationHadVisibleText || !visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                outcome = .complete
            }

            browser.isGenerating = false
            stopCompletionPolling()
            browser.pictureInPicture.generationFinished(text: visibleText, outcome: outcome, generationId: id)
            ReplyNotificationService.shared.generationFinished(id: id, outcome: outcome)
            browser.currentGenerationId = nil
            browser.serverGenerationId = nil
            browser.generationStartedAt = nil
            browser.lastReplyText = ""
            browser.generationHadVisibleText = false
            fallbackGenerationId = nil
        }


        private func handleTavernTools(_ payload: [String: Any]) {
            guard let action = payload["action"] as? String else { return }
            let requestId = payload["requestId"] as? String
            switch action {
            case "translate":
                let text = payload["text"] as? String ?? ""
                EdgeTranslatorService.shared.translate(text) { [weak self] result in
                    switch result {
                    case .success(let value):
                        self?.sendTavernToolsResult(requestId: requestId, ok: true, text: value, error: nil)
                    case .failure(let error):
                        self?.sendTavernToolsResult(requestId: requestId, ok: false, text: nil, error: error.localizedDescription)
                    }
                }
            case "makeCard":
                let text = payload["text"] as? String ?? ""
                let character = payload["character"] as? String
                let theme = payload["theme"] as? String
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    sendTavernToolsResult(requestId: requestId, ok: false, text: nil, error: "没有可用选区，请重新选中 AI 回复文字。")
                    return
                }
                let image = SelectionCardService.makeCard(text: text, character: character, theme: theme)
                if presentShare(items: [image]) {
                    sendTavernToolsResult(requestId: requestId, ok: true, text: "卡片已生成", error: nil)
                } else {
                    sendTavernToolsResult(requestId: requestId, ok: false, text: nil, error: "系统分享面板打开失败，请重新点一次卡片。")
                }
            default:
                break
            }
        }

        private func sendTavernToolsResult(requestId: String?, ok: Bool, text: String?, error: String?) {
            guard let requestId else { return }
            var payload: [String: Any] = [
                "requestId": requestId,
                "ok": ok
            ]
            if let text { payload["text"] = text }
            if let error { payload["error"] = error }
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
                  let json = String(data: data, encoding: .utf8) else { return }
            browser.webView?.evaluateJavaScript("window.__tavernLiteTools?.nativeResult?.(\(json))")
        }

        @discardableResult
        private func presentShare(items: [Any]) -> Bool {
            guard let webView = browser.webView else { return false }
            let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = webView
                popover.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.midY, width: 1, height: 1)
            }

            guard let root = webView.window?.rootViewController ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?
                .rootViewController else { return false }

            var top = root
            while let presented = top.presentedViewController, !presented.isBeingDismissed {
                top = presented
            }
            if top is UIActivityViewController { return false }
            top.present(activity, animated: true)
            return true
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
                                self.completeFinish(
                                    id: id,
                                    text: self.browser.lastReplyText,
                                    requestedOutcome: .complete
                                )
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
