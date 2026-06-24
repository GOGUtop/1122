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
                self.setKeyboardPerformanceMode(true, webView: webView)
            }
        }

        let didShow = center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self, weak webView] _ in
            guard let self else { return }
            Task { @MainActor in
                self.setKeyboardPerformanceMode(true, webView: webView)
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
        setKeyboardPerformanceMode(true, webView: webView)
        webView?.scrollView.layer.removeAllAnimations()
        webView?.layer.removeAllAnimations()
    }

    @MainActor
    func prepareForChatHistoryLoad(webView: WKWebView?) {
        cancelKeyboardSettle()
        setKeyboardPerformanceMode(true, webView: webView)
        webView?.scrollView.layer.removeAllAnimations()
        webView?.layer.removeAllAnimations()
    }

    @MainActor
    func scheduleDeepSmoothRelease(webView: WKWebView?) {
        // v4.1 不再恢复网页侧重任务。之前的恢复过程会和二次点击输入框冲突。
        scheduleKeyboardSettle(webView: webView)
    }

    @MainActor
    private func cancelKeyboardSettle() {
        keyboardSettleWorkItem?.cancel()
        keyboardSettleWorkItem = nil
        deepSmoothReleaseWorkItem?.cancel()
        deepSmoothReleaseWorkItem = nil
    }

    @MainActor
    private func scheduleKeyboardSettle(webView: WKWebView?) {
        cancelKeyboardSettle()
        browser.isKeyboardActive = true
        browser.pictureInPicture.setPerformanceMode(true)

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard !(self.keyboardSettleWorkItem?.isCancelled ?? true) else { return }
                self.keyboardSettleWorkItem = nil
                self.lastKeyboardPerformanceState = false
                self.browser.isKeyboardActive = false
                self.browser.pictureInPicture.setPerformanceMode(false)
            }
        }
        keyboardSettleWorkItem = work
        // 缩短冷却：不做 JS 恢复，所以这里只等系统键盘动画真正结束。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48, execute: work)
    }

    @MainActor
    private func setKeyboardPerformanceMode(_ active: Bool, webView: WKWebView?) {
        let enabled = UserDefaults.standard.object(forKey: "performanceMode") as? Bool ?? true
        let targetState = active && enabled
        browser.isKeyboardActive = active
        browser.pictureInPicture.setPerformanceMode(active)

        guard lastKeyboardPerformanceState != targetState else { return }
        lastKeyboardPerformanceState = targetState
        webView?.scrollView.layer.removeAllAnimations()
        webView?.layer.removeAllAnimations()
        // 不再在键盘动画期间 evaluateJavaScript。旧版卡顿主要来自这里触发整页样式重算。
    }
}
