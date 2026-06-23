import Foundation
import WebKit
import UIKit

extension WebView.Coordinator: WKDownloadDelegate {
    func handleTavernDownload(_ payload: [String: Any]) {
        let type = payload["type"] as? String ?? ""
        if type == "error" {
            let message = payload["message"] as? String ?? "未知下载错误"
            Task { @MainActor in
                self.browser.downloadNotice = "下载接管失败：\(message)"
            }
            return
        }
        guard type == "file",
              let filename = payload["filename"] as? String,
              let base64 = payload["base64"] as? String,
              let data = Data(base64Encoded: base64) else {
            Task { @MainActor in
                self.browser.downloadNotice = "下载接管失败：文件数据无效"
            }
            return
        }
        let mime = payload["mime"] as? String ?? "application/octet-stream"
        let source = payload["source"] as? String ?? "网页导出"
        do {
            let url = try Self.saveDownloadData(data, suggestedFilename: filename)
            Task { @MainActor in
                let autoShare = UserDefaults.standard.object(forKey: "downloadAutoShare") as? Bool ?? true
                self.browser.registerDownload(filename: url.lastPathComponent, fileURL: url, mimeType: mime, source: source, autoShare: autoShare)
            }
        } catch {
            Task { @MainActor in
                self.browser.downloadNotice = "下载保存失败：\(error.localizedDescription)"
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
            return
        }
        decisionHandler(.allow, preferences)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        do {
            let directory = try Self.downloadDirectory()
            let destination = Self.uniqueFileURL(directory: directory, suggestedFilename: suggestedFilename)
            DownloadRegistry.shared.set(destination, for: download)
            completionHandler(destination)
        } catch {
            Task { @MainActor in
                self.browser.downloadNotice = "无法创建下载目录：\(error.localizedDescription)"
            }
            completionHandler(nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destination = DownloadRegistry.shared.take(for: download) else { return }
        Task { @MainActor in
            let autoShare = UserDefaults.standard.object(forKey: "downloadAutoShare") as? Bool ?? true
            self.browser.registerDownload(
                filename: destination.lastPathComponent,
                fileURL: destination,
                mimeType: "application/octet-stream",
                source: "普通下载",
                autoShare: autoShare
            )
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        _ = DownloadRegistry.shared.take(for: download)
        Task { @MainActor in
            self.browser.downloadNotice = "下载失败：\(error.localizedDescription)"
        }
    }

    private static func downloadDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("TavernDownloads", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func saveDownloadData(_ data: Data, suggestedFilename: String) throws -> URL {
        let directory = try downloadDirectory()
        let destination = Self.uniqueFileURL(directory: directory, suggestedFilename: suggestedFilename)
        try data.write(to: destination, options: [.atomic])
        return destination
    }

    private static func uniqueFileURL(directory: URL, suggestedFilename: String) -> URL {
        let cleaned = suggestedFilename
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let fallback = cleaned.isEmpty ? "tavern-export.bin" : cleaned
        var candidate = directory.appendingPathComponent(fallback)
        let ext = candidate.pathExtension
        let base = candidate.deletingPathExtension().lastPathComponent
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = directory.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }
}
