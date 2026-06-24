import UIKit
import WebKit

extension WebView.Coordinator {
    func observeKeyboard(for webView: WKWebView) {
        guard notificationTokens.isEmpty else { return }
        let center = NotificationCenter.default

        let willShow = center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self, weak webView] _ in
            guard let self else { return }
            Task { @MainActor in
                self.cancelKeyboardSettle()
                self.cancelDeepSmoothRelease()
                self.setKeyboardPerformanceMode(true, webView: webView, lightweightOnly: true)
            }
        }

        let willHide = center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self, weak webView] _ in
            guard let self else { return }
            Task { @MainActor in
                self.cancelKeyboardSettle()
                self.cancelDeepSmoothRelease()
                self.setKeyboardPerformanceMode(true, webView: webView, lightweightOnly: true)
            }
        }

        let didShow = center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self, weak webView] _ in
            guard let self else { return }
            Task { @MainActor in
                self.cancelKeyboardSettle()
                self.cancelDeepSmoothRelease()
                self.setKeyboardPerformanceMode(true, webView: webView, lightweightOnly: true)
            }
        }

        let didHide = center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self, weak webView] _ in
            guard let self else { return }
            Task { @MainActor in
                self.scheduleKeyboardSettle(webView: webView)
            }
        }

        notificationTokens = [willShow, willHide, didShow, didHide]
    }

    @MainActor
    func prepareForFastInputFocus(webView: WKWebView?) {
        cancelKeyboardSettle()
        cancelDeepSmoothRelease()
        setKeyboardPerformanceMode(true, webView: webView, lightweightOnly: true)
        webView?.scrollView.layer.removeAllAnimations()
        webView?.layer.removeAllAnimations()
        webView?.evaluateJavaScript("""
        (() => {
          try {
            window.__tavernIOSInputBusy = true;
            document.documentElement.classList.add('tavern-ios-touch-input');
            clearTimeout(window.__tavernIOSNativeInputBusyTimer);
            window.__tavernIOSNativeInputBusyTimer = setTimeout(() => {
              window.__tavernIOSInputBusy = false;
              document.documentElement.classList.remove('tavern-ios-touch-input');
            }, 2600);
          } catch (_) {}
        })();
        """)
    }

    @MainActor
    func prepareForChatHistoryLoad(webView: WKWebView?) {
        cancelKeyboardSettle()
        cancelDeepSmoothRelease()
        browser.isKeyboardActive = false
        browser.pictureInPicture.setPerformanceMode(true)
        webView?.scrollView.layer.removeAllAnimations()
        webView?.layer.removeAllAnimations()
        webView?.evaluateJavaScript("""
        (() => {
          try {
            window.__tavernIOSChatLoadBusy = true;
            document.documentElement.classList.add('tavern-ios-chat-load');
            clearTimeout(window.__tavernIOSChatLoadTimer);
            window.__tavernIOSChatLoadTimer = setTimeout(() => {
              window.__tavernIOSChatLoadBusy = false;
              document.documentElement.classList.remove('tavern-ios-chat-load');
              window.__tavernIOSRoleBoostRun?.();
            }, 5600);
          } catch (_) {}
        })();
        """)
    }

    @MainActor
    func scheduleDeepSmoothRelease(webView: WKWebView?) {
        cancelDeepSmoothRelease()
        let work = DispatchWorkItem { [weak self, weak webView] in
            guard let self else { return }
            Task { @MainActor in
                guard !(self.deepSmoothReleaseWorkItem?.isCancelled ?? true) else { return }
                self.deepSmoothReleaseWorkItem = nil
                if self.browser.isKeyboardActive { return }
                webView?.evaluateJavaScript("""
                (() => {
                  try {
                    document.documentElement.classList.remove('tavern-ios-touch-input');
                    if (!window.__tavernIOSChatLoadBusy) document.documentElement.classList.remove('tavern-ios-chat-load');
                  } catch (_) {}
                })();
                """)
            }
        }
        deepSmoothReleaseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    @MainActor
    private func cancelKeyboardSettle() {
        keyboardSettleWorkItem?.cancel()
        keyboardSettleWorkItem = nil
    }

    @MainActor
    private func cancelDeepSmoothRelease() {
        deepSmoothReleaseWorkItem?.cancel()
        deepSmoothReleaseWorkItem = nil
    }

    @MainActor
    private func scheduleKeyboardSettle(webView: WKWebView?) {
        cancelKeyboardSettle()
        cancelDeepSmoothRelease()

        // 继续保持轻量状态，避免键盘刚收完时用户马上再次点击输入框产生主线程冲突。
        browser.isKeyboardActive = true
        browser.pictureInPicture.setPerformanceMode(true)

        let work = DispatchWorkItem { [weak self, weak webView] in
            guard let self else { return }
            Task { @MainActor in
                guard !(self.keyboardSettleWorkItem?.isCancelled ?? true) else { return }
                self.keyboardSettleWorkItem = nil
                self.finishKeyboardSettle(webView: webView)
            }
        }
        keyboardSettleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35, execute: work)
    }

    @MainActor
    private func finishKeyboardSettle(webView: WKWebView?) {
        lastKeyboardPerformanceState = false
        browser.isKeyboardActive = false

        // 这里不再跑 roleCardBoost / 图片扫描。旧版卡顿点就在键盘收回后立刻恢复重任务。
        // 角色卡和图片优化交给网页侧 requestIdleCallback，并且避开输入 busy 与聊天加载 busy。
        scheduleDeepSmoothRelease(webView: webView)
    }

    @MainActor
    private func setKeyboardPerformanceMode(_ active: Bool, webView: WKWebView?, lightweightOnly: Bool = false) {
        let enabled = UserDefaults.standard.object(forKey: "performanceMode") as? Bool ?? true
        let targetState = active && enabled

        if lastKeyboardPerformanceState == targetState {
            browser.isKeyboardActive = active
            browser.pictureInPicture.setPerformanceMode(active)
            return
        }

        lastKeyboardPerformanceState = targetState
        browser.isKeyboardActive = active
        browser.pictureInPicture.setPerformanceMode(active)

        guard enabled, let webView else { return }
        webView.scrollView.layer.removeAllAnimations()
        webView.layer.removeAllAnimations()
        webView.evaluateJavaScript(WebView.performanceScript(active: true))
        if !lightweightOnly {
            webView.evaluateJavaScript("""
            (() => {
              try { document.documentElement.classList.add('tavern-ios-focus-warm'); } catch (_) {}
            })();
            """)
        }
    }
}
