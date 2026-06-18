import SwiftUI
import WebKit

@MainActor
final class LongScreenshotService {
    enum CaptureError: LocalizedError {
        case invalidPage
        case tooLong
        case emptyImage
        case invalidRange

        var errorDescription: String? {
            switch self {
            case .invalidPage: return "没有找到可滚动的聊天区域。"
            case .tooLong: return "选择范围太长，请缩短开头和结尾后再试。"
            case .emptyImage: return "没有生成截图。"
            case .invalidRange: return "请先选择开头，再滑到结尾截图。"
            }
        }
    }

    private struct ScrollInfo: Decodable {
        let viewportX: CGFloat
        let viewportY: CGFloat
        let viewportWidth: CGFloat
        let viewportHeight: CGFloat
        let contentHeight: CGFloat
        let originalScrollTop: CGFloat
    }

    private struct CapturedTile {
        let image: UIImage
        let scrollTop: CGFloat
    }

    func currentScrollTop(webView: WKWebView, completion: @escaping (Result<CGFloat, Error>) -> Void) {
        let script = Self.targetScript + """
        (() => {
          const target = window.__tavernFindScrollTarget();
          if (!target) return null;
          return target.scrollTop || 0;
        })();
        """
        webView.evaluateJavaScript(script) { value, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let number = value as? NSNumber {
                completion(.success(CGFloat(truncating: number)))
            } else if let double = value as? Double {
                completion(.success(CGFloat(double)))
            } else {
                completion(.failure(CaptureError.invalidPage))
            }
        }
    }

    func capture(
        webView: WKWebView,
        startOffset: CGFloat? = nil,
        endOffset: CGFloat? = nil,
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) {
        let startLiteral = startOffset.map { String(format: "%.2f", Double($0)) } ?? "0"
        let setupScript = Self.targetScript + """
        (() => {
          const target = window.__tavernFindScrollTarget();
          if (!target || target.scrollHeight <= 1) return null;

          window.__tavernScrollCapture = {
            target: target,
            originalScrollTop: target.scrollTop || 0,
            scrollBehavior: target.style.scrollBehavior
          };
          target.style.setProperty('scroll-behavior', 'auto', 'important');
          target.scrollTop = Math.max(0, Math.min(
            target.scrollHeight - target.clientHeight,
            \(startLiteral)
          ));

          const rect = target.getBoundingClientRect();
          const top = Math.max(0, rect.top);
          const left = Math.max(0, rect.left);
          const width = Math.min(window.innerWidth - left, rect.width);
          const height = Math.min(window.innerHeight - top, rect.height);
          return {
            viewportX: left,
            viewportY: top,
            viewportWidth: width,
            viewportHeight: height,
            contentHeight: target.scrollHeight,
            originalScrollTop: window.__tavernScrollCapture.originalScrollTop
          };
        })();
        """

        webView.evaluateJavaScript(setupScript) { value, error in
            guard error == nil,
                  let dictionary = value as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dictionary),
                  let info = try? JSONDecoder().decode(ScrollInfo.self, from: data),
                  info.viewportWidth > 20,
                  info.viewportHeight > 20 else {
                completion(.failure(error ?? CaptureError.invalidPage))
                return
            }

            let maxScroll = max(0, info.contentHeight - info.viewportHeight)
            let rawStart = min(max(0, startOffset ?? 0), maxScroll)
            let rawEnd = min(max(0, endOffset ?? maxScroll), maxScroll)
            let start = min(rawStart, rawEnd)
            let end = max(rawStart, rawEnd)

            guard end >= start else {
                self.restore(webView)
                completion(.failure(CaptureError.invalidRange))
                return
            }
            guard end - start + info.viewportHeight <= 45_000 else {
                self.restore(webView)
                completion(.failure(CaptureError.tooLong))
                return
            }

            let step = max(100, info.viewportHeight * 0.76)
            var offsets: [CGFloat] = [start]
            var next = start + step
            while next < end {
                offsets.append(next)
                next += step
            }
            if offsets.last != end {
                offsets.append(end)
            }

            self.captureTile(
                webView: webView,
                info: info,
                offsets: offsets,
                index: 0,
                tiles: []
            ) { result in
                self.restore(webView)
                switch result {
                case .success(let tiles):
                    guard let image = self.stitch(tiles, viewportHeight: info.viewportHeight) else {
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

    private func captureTile(
        webView: WKWebView,
        info: ScrollInfo,
        offsets: [CGFloat],
        index: Int,
        tiles: [CapturedTile],
        completion: @escaping (Result<[CapturedTile], Error>) -> Void
    ) {
        guard index < offsets.count else {
            completion(.success(tiles))
            return
        }

        let offset = offsets[index]
        let scrollScript = """
        (() => {
          const saved = window.__tavernScrollCapture;
          if (!saved || !saved.target) return false;
          saved.target.scrollTop = \(String(format: "%.2f", Double(offset)));
          saved.target.dispatchEvent(new Event('scroll', { bubbles: true }));
          window.dispatchEvent(new Event('scroll'));
          return true;
        })();
        """

        webView.evaluateJavaScript(scrollScript) { _, error in
            if let error {
                completion(.failure(error))
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                let configuration = WKSnapshotConfiguration()
                configuration.rect = CGRect(
                    x: info.viewportX,
                    y: info.viewportY,
                    width: min(info.viewportWidth, webView.bounds.width - info.viewportX),
                    height: min(info.viewportHeight, webView.bounds.height - info.viewportY)
                )
                configuration.afterScreenUpdates = true

                webView.takeSnapshot(with: configuration) { image, error in
                    if let error {
                        completion(.failure(error))
                        return
                    }
                    guard let image else {
                        completion(.failure(CaptureError.emptyImage))
                        return
                    }
                    self.captureTile(
                        webView: webView,
                        info: info,
                        offsets: offsets,
                        index: index + 1,
                        tiles: tiles + [CapturedTile(image: image, scrollTop: offset)],
                        completion: completion
                    )
                }
            }
        }
    }

    private func stitch(_ tiles: [CapturedTile], viewportHeight: CGFloat) -> UIImage? {
        guard let first = tiles.first else { return nil }
        let pointScale = first.image.size.height / viewportHeight
        let pieces: [UIImage] = tiles.enumerated().compactMap { index, tile in
            guard let cgImage = tile.image.cgImage else { return nil }
            guard index > 0 else { return tile.image }
            let delta = tile.scrollTop - tiles[index - 1].scrollTop
            let duplicatePoints = max(0, viewportHeight - delta) * pointScale
            let pixelScale = CGFloat(cgImage.height) / tile.image.size.height
            let cropPixels = min(duplicatePoints * pixelScale, CGFloat(cgImage.height - 1))
            let cropRect = CGRect(
                x: 0,
                y: cropPixels,
                width: CGFloat(cgImage.width),
                height: CGFloat(cgImage.height) - cropPixels
            )
            guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
            return UIImage(cgImage: cropped, scale: tile.image.scale, orientation: .up)
        }

        let outputWidth = first.image.size.width
        let outputHeight = pieces.reduce(CGFloat.zero) { $0 + $1.size.height }
        guard outputHeight > 1, outputHeight <= 60_000 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: outputWidth, height: outputHeight),
            format: format
        ).image { context in
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

            var y: CGFloat = 0
            for image in pieces {
                image.draw(at: CGPoint(x: 0, y: y))
                y += image.size.height
            }
        }
    }

    private func restore(_ webView: WKWebView) {
        let script = """
        (() => {
          const saved = window.__tavernScrollCapture;
          if (!saved || !saved.target) return;
          saved.target.scrollTop = saved.originalScrollTop;
          saved.target.style.scrollBehavior = saved.scrollBehavior;
          delete window.__tavernScrollCapture;
        })();
        """
        webView.evaluateJavaScript(script)
    }

    private static let targetScript = """
    window.__tavernFindScrollTarget = function() {
      const selectors = [
        '#chat',
        '.chat',
        '#chat_container',
        '.chat-container',
        '#sheld',
        'main',
        'body'
      ];
      const candidates = selectors
        .map(s => document.querySelector(s))
        .filter(Boolean)
        .concat(Array.from(document.querySelectorAll('div, main, section')).filter(el => {
          const style = getComputedStyle(el);
          return /(auto|scroll)/.test(style.overflowY) && el.scrollHeight > el.clientHeight + 80;
        }));
      let best = null;
      for (const el of candidates) {
        if (!el) continue;
        const h = el.scrollHeight || 0;
        const c = el.clientHeight || 0;
        if (h > c + 20 && (!best || h > best.scrollHeight)) best = el;
      }
      return best || document.scrollingElement || document.documentElement;
    };
    """
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
