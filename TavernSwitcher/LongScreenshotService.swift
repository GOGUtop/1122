import SwiftUI
import WebKit

@MainActor
final class LongScreenshotService {
    enum CaptureError: LocalizedError {
        case noWebView
        case invalidPage
        case tooLong
        case emptyImage

        var errorDescription: String? {
            switch self {
            case .noWebView: return "没有可截图的网页。"
            case .invalidPage: return "无法读取聊天页面尺寸。"
            case .tooLong: return "聊天内容过长，请先折叠部分消息后再截图。"
            case .emptyImage: return "没有生成截图。"
            }
        }
    }

    private struct CaptureArea: Decodable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    func capture(webView: WKWebView, completion: @escaping (Result<UIImage, Error>) -> Void) {
        let prepareScript = """
        (() => {
          const target = document.querySelector('#chat') ||
                         document.querySelector('.chat') ||
                         document.scrollingElement ||
                         document.documentElement;
          if (!target) return null;
          window.__tavernCaptureRestore = {
            target,
            cssText: target.style.cssText,
            scrollTop: target.scrollTop,
            bodyCss: document.body ? document.body.style.cssText : '',
            htmlCss: document.documentElement.style.cssText
          };
          if (document.body) document.body.style.overflow = 'visible';
          document.documentElement.style.overflow = 'visible';
          target.style.setProperty('height', target.scrollHeight + 'px', 'important');
          target.style.setProperty('max-height', 'none', 'important');
          target.style.setProperty('overflow', 'visible', 'important');
          const rect = target.getBoundingClientRect();
          return {
            x: Math.max(0, rect.left + window.scrollX),
            y: Math.max(0, rect.top + window.scrollY),
            width: Math.max(document.documentElement.clientWidth, rect.width),
            height: Math.max(target.scrollHeight, rect.height)
          };
        })();
        """

        webView.evaluateJavaScript(prepareScript) { [weak self, weak webView] value, error in
            guard let self, let webView else {
                completion(.failure(CaptureError.noWebView))
                return
            }
            guard error == nil,
                  let dictionary = value as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dictionary),
                  let area = try? JSONDecoder().decode(CaptureArea.self, from: data),
                  area.height > 1 else {
                self.restore(webView)
                completion(.failure(error ?? CaptureError.invalidPage))
                return
            }

            let captureWidth = max(webView.bounds.width, min(area.width, webView.bounds.width))
            let captureHeight = min(area.height, 24_000)
            guard area.height <= 24_000 else {
                self.restore(webView)
                completion(.failure(CaptureError.tooLong))
                return
            }

            let tileHeight: CGFloat = 1_400
            var rects: [CGRect] = []
            var offset: CGFloat = 0
            while offset < captureHeight {
                let height = min(tileHeight, captureHeight - offset)
                rects.append(CGRect(x: 0, y: area.y + offset, width: captureWidth, height: height))
                offset += height
            }

            self.captureTiles(webView: webView, rects: rects, index: 0, images: []) { result in
                self.restore(webView)
                switch result {
                case .success(let images):
                    guard let image = self.stitch(images) else {
                        completion(.failure(CaptureError.emptyImage))
                        return
                    }
                    completion(.success(image))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    private func captureTiles(
        webView: WKWebView,
        rects: [CGRect],
        index: Int,
        images: [UIImage],
        completion: @escaping (Result<[UIImage], Error>) -> Void
    ) {
        guard index < rects.count else {
            completion(.success(images))
            return
        }

        let configuration = WKSnapshotConfiguration()
        configuration.rect = rects[index]
        configuration.afterScreenUpdates = true

        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            guard let self else { return }
            if let error {
                completion(.failure(error))
                return
            }
            guard let image else {
                completion(.failure(CaptureError.emptyImage))
                return
            }
            self.captureTiles(
                webView: webView,
                rects: rects,
                index: index + 1,
                images: images + [image],
                completion: completion
            )
        }
    }

    private func stitch(_ images: [UIImage]) -> UIImage? {
        guard let first = images.first else { return nil }
        let width = first.size.width
        let height = images.reduce(CGFloat.zero) { $0 + $1.size.height }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { _ in
            var y: CGFloat = 0
            for image in images {
                image.draw(at: CGPoint(x: 0, y: y))
                y += image.size.height
            }
        }
    }

    private func restore(_ webView: WKWebView) {
        let script = """
        (() => {
          const saved = window.__tavernCaptureRestore;
          if (!saved) return;
          saved.target.style.cssText = saved.cssText;
          saved.target.scrollTop = saved.scrollTop;
          if (document.body) document.body.style.cssText = saved.bodyCss;
          document.documentElement.style.cssText = saved.htmlCss;
          delete window.__tavernCaptureRestore;
        })();
        """
        webView.evaluateJavaScript(script)
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
