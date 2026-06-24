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
                self.setKeyboardPerformanceMode(true, webView: webView)
            }
        }

        let willHide = center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self, weak webView] _ in
            guard let self else { return }
            Task { @MainActor in
                self.cancelKeyboardSettle()
                // 收键盘动画期间继续保持极速模式，避免下坠时网页和输入框一起重排。
                self.setKeyboardPerformanceMode(true, webView: webView, lightweightOnly: true)
            }
        }

        let didShow = center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self, weak webView] _ in
            guard let self else { return }
            Task { @MainActor in
                self.cancelKeyboardSettle()
                self.setKeyboardPerformanceMode(true, webView: webView, lightweightOnly: true)
            }
        }

        let didHide = center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self, weak webView] _ in
            guard let self else { return }
            Task { @MainActor in
                // 关键修复：键盘刚收完的 0.8 秒内，不恢复重任务。
                // 这段时间用户最常马上再次点输入框，旧版会在这里执行 JS / 图片优化，造成“点一下卡顿”。
                self.scheduleKeyboardSettle(webView: webView)
            }
        }

        notificationTokens = [willShow, willHide, didShow, didHide]
    }

    @MainActor
    private func cancelKeyboardSettle() {
        keyboardSettleWorkItem?.cancel()
        keyboardSettleWorkItem = nil
    }

    @MainActor
    private func scheduleKeyboardSettle(webView: WKWebView?) {
        cancelKeyboardSettle()

        // 键盘已下去，但先继续把输入区视为“键盘过渡中”，让悬浮球和液态面板不要立刻回来抢主线程。
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.82, execute: work)
    }

    @MainActor
    private func finishKeyboardSettle(webView: WKWebView?) {
        lastKeyboardPerformanceState = false
        browser.isKeyboardActive = false

        // 不在这里执行 roleCardBoost / 全页图片扫描。等待用户空闲后再轻量跑一次；
        // 如果用户马上又点输入框，willShow 会取消这次 idle 任务。
        guard UserDefaults.standard.object(forKey: "performanceMode") as? Bool ?? true, let webView else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self, weak webView] in
            guard let self, let webView else { return }
            if self.browser.isKeyboardActive { return }
            webView.evaluateJavaScript("""
            (() => {
              try {
                window.__tavernIOSRoleBoostRun?.();
                document.documentElement.classList.remove('tavern-ios-focus-warm');
              } catch (_) {}
            })();
            """)
        }
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

        // 只切换轻量样式，不在键盘动画期间跑角色卡/图片扫描，避免主线程峰值。
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
