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
                self.setKeyboardPerformanceMode(false, webView: webView, delay: 0.16)
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
            self.browser.isKeyboardActive = active && enabled
            self.browser.pictureInPicture.setPerformanceMode(active && enabled)
            guard let webView else { return }
            webView.scrollView.layer.removeAllAnimations()
            webView.layer.removeAllAnimations()
            webView.evaluateJavaScript(WebView.performanceScript(active: active && enabled))
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            work()
        }
    }
}
