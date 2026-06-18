import SwiftUI
import WebKit

@MainActor
final class LongScreenshotService {
    enum CaptureError: LocalizedError {
        case invalidPage
        case tooLong
        case emptyImage

        var errorDescription: String? {
            switch self {
            case .invalidPage: return "没有找到可滚动的聊天区域。"
            case .tooLong: return "聊天内容过长，请减少消息数量后再试。"
            case .emptyImage: return "没有生成截图。"
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

    func capture(webView: WKWebView, completion: @escaping (Result<UIImage, Error>) -> Void) {
        let setupScript = """
        (() => {
          const candidates = [
            document.querySelector('#chat'),
            document.querySelector('.chat'),
            document.querySelector('#sheld')
          ].filter(Boolean);
          let target = candidates.find(el => el.scrollHeight > el.clientHeight + 20);
          if (!target) target = document.scrollingElement || document.documentElement;
          if (!target || target.scrollHeight <= 1) return null;

          window.__tavernScrollCapture = {
            target: target,
            originalScrollTop: target.scrollTop,
            scrollBehavior: target.style.scrollBehavior
          };
          target.style.setProperty('scroll-behavior', 'auto', 'important');
          target.scrollTop = 0;

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

            guard info.contentHeight <= 45_000 else {
                self.restore(webView)
                completion(.failure(CaptureError.tooLong))
                return
            }

            let maxScroll = max(0, info.contentHeight - info.viewportHeight)
            let step = max(100, info.viewportHeight * 0.76)
            var offsets: [CGFloat] = [0]
            var next = step
            while next < maxScroll {
                offsets.append(next)
                next += step
            }
            if maxScroll > 0, offsets.last != maxScroll {
                offsets.append(maxScroll)
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
          saved.target.scrollTop = \(offset);
          saved.target.dispatchEvent(new Event('scroll', { bubbles: true }));
          return true;
        })();
        """

        webView.evaluateJavaScript(scrollScript) { _, error in
            if let error {
                completion(.failure(error))
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
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
        let pieces: [(UIImage, CGFloat)] = tiles.enumerated().compactMap { index, tile in
            guard let cgImage = tile.image.cgImage else { return nil }
            guard index > 0 else { return (tile.image, 0) }
            let delta = tile.scrollTop - tiles[index - 1].scrollTop
            let duplicatePoints = max(0, viewportHeight - delta) * pointScale
            let pixelScale = CGFloat(cgImage.height) / tile.image.size.height
            let cropPixels = min(
                duplicatePoints * pixelScale,
                CGFloat(cgImage.height - 1)
            )
            let cropRect = CGRect(
                x: 0,
                y: cropPixels,
                width: CGFloat(cgImage.width),
                height: CGFloat(cgImage.height) - cropPixels
            )
            guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
            return (
                UIImage(cgImage: cropped, scale: tile.image.scale, orientation: .up),
                duplicatePoints
            )
        }

        let outputWidth = first.image.size.width
        let outputHeight = pieces.reduce(CGFloat.zero) { result, piece in
            result + piece.0.size.height
        }
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
            for (image, _) in pieces {
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
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
