import UIKit
import WebKit

extension WebView.Coordinator {
    func observeKeyboard(for webView: WKWebView) {
        guard notificationTokens.isEmpty else { return }
        let center = NotificationCenter.default
        let willShow = center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self, weak webView] _ in
            guard let self else { return }
            Task { @MainActor in
                self.setKeyboardPerformanceMode(true, webView: webView)
            }
        }
        let willHide = center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self, weak webView] _ in
            guard let self else { return }
            Task { @MainActor in
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
                self.setKeyboardPerformanceMode(false, webView: webView, delay: 0.26)
            }
        }
        notificationTokens = [willShow, willHide, didShow, didHide]
    }

    @MainActor
    private func setKeyboardPerformanceMode(_ active: Bool, webView: WKWebView?, delay: TimeInterval = 0) {
        let work = { [weak self, weak webView] in
            guard let self else { return }
            let enabled = UserDefaults.standard.object(forKey: "performanceMode") as? Bool ?? true
            let targetState = active && enabled

            // 键盘弹出/收回时最容易卡：不要在 willShow / didShow / willHide 连续重复注入 JS。
            // 只在状态真正变化时切换一次，避免输入框动画期间主线程被 evaluateJavaScript 抢占。
            if self.lastKeyboardPerformanceState == targetState {
                self.browser.isKeyboardActive = targetState
                return
            }
            self.lastKeyboardPerformanceState = targetState
            self.browser.isKeyboardActive = targetState
            self.browser.pictureInPicture.setPerformanceMode(targetState)
            guard let webView else { return }
            webView.scrollView.layer.removeAllAnimations()
            webView.layer.removeAllAnimations()
            webView.evaluateJavaScript(WebView.performanceScript(active: enabled))
            webView.evaluateJavaScript(WebView.roleCardBoostScript)
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            work()
        }
    }
}
