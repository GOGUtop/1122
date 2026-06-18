import PDFKit
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
                         document.querySelector('#sheld') ||
                         document.querySelector('.chat') ||
                         document.scrollingElement ||
                         document.documentElement;
          if (!target) return null;

          window.__tavernCaptureRestore = {
            target: target,
            targetCss: target.style.cssText,
            targetScrollTop: target.scrollTop,
            bodyCss: document.body ? document.body.style.cssText : '',
            htmlCss: document.documentElement.style.cssText
          };

          const height = Math.max(
            target.scrollHeight,
            target.offsetHeight,
            document.documentElement.scrollHeight,
            document.body ? document.body.scrollHeight : 0
          );

          if (document.body) {
            document.body.style.setProperty('height', 'auto', 'important');
            document.body.style.setProperty('max-height', 'none', 'important');
            document.body.style.setProperty('overflow', 'visible', 'important');
          }
          document.documentElement.style.setProperty('height', 'auto', 'important');
          document.documentElement.style.setProperty('max-height', 'none', 'important');
          document.documentElement.style.setProperty('overflow', 'visible', 'important');
          target.style.setProperty('height', height + 'px', 'important');
          target.style.setProperty('max-height', 'none', 'important');
          target.style.setProperty('overflow', 'visible', 'important');
          target.scrollTop = 0;

          const rect = target.getBoundingClientRect();
          return {
            x: Math.max(0, rect.left + window.scrollX),
            y: Math.max(0, rect.top + window.scrollY),
            width: Math.max(320, rect.width),
            height: height
          };
        })();
        """

        webView.evaluateJavaScript(prepareScript) { value, error in
            guard error == nil,
                  let dictionary = value as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: dictionary),
                  let area = try? JSONDecoder().decode(CaptureArea.self, from: data),
                  area.height > 1 else {
                self.restore(webView)
                completion(.failure(error ?? CaptureError.invalidPage))
                return
            }

            guard area.height <= 30_000 else {
                self.restore(webView)
                completion(.failure(CaptureError.tooLong))
                return
            }

            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(
                x: area.x,
                y: area.y,
                width: min(area.width, max(webView.bounds.width, 430)),
                height: area.height
            )

            webView.createPDF(configuration: configuration) { result in
                self.restore(webView)
                switch result {
                case .success(let data):
                    guard let image = self.renderPDF(data) else {
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

    private func renderPDF(_ data: Data) -> UIImage? {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { return nil }
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }
        let bounds = pages.map { $0.bounds(for: .mediaBox) }
        guard let first = bounds.first else { return nil }

        let pointHeight = bounds.reduce(CGFloat.zero) { $0 + $1.height }
        let scale = min(CGFloat(2), max(CGFloat(1), 30_000 / pointHeight))
        let outputWidth = first.width * scale
        let outputHeight = bounds.reduce(CGFloat.zero) { $0 + $1.height * scale }
        guard outputWidth > 0, outputHeight > 0, outputHeight <= 60_000 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: outputWidth, height: outputHeight),
            format: format
        ).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

            var y: CGFloat = 0
            for (page, pageBounds) in zip(pages, bounds) {
                let pageHeight = pageBounds.height * scale
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: 0, y: y + pageHeight)
                context.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: context.cgContext)
                context.cgContext.restoreGState()
                y += pageHeight
            }
        }
    }

    private func restore(_ webView: WKWebView) {
        let script = """
        (() => {
          const saved = window.__tavernCaptureRestore;
          if (!saved) return;
          saved.target.style.cssText = saved.targetCss;
          saved.target.scrollTop = saved.targetScrollTop;
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
