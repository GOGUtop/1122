import SwiftUI
import UIKit
import WebKit

struct TavernDownloadItem: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let fileURL: URL
    let mimeType: String
    let createdAt: Date
    let source: String

    var sizeText: String {
        let bytes = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func == (lhs: TavernDownloadItem, rhs: TavernDownloadItem) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class DownloadPresenter {
    static func present(items: [Any], from webView: WKWebView?) -> Bool {
        guard let root = webView?.window?.rootViewController ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController else { return false }

        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            let source = webView ?? root.view
            popover.sourceView = source
            popover.sourceRect = CGRect(x: source?.bounds.midX ?? 1, y: source?.bounds.midY ?? 1, width: 1, height: 1)
        }
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        guard !(top is UIActivityViewController) else { return false }
        top.present(activity, animated: true)
        return true
    }
}

struct DownloadCenterView: View {
    let items: [TavernDownloadItem]
    let clear: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: TavernDownloadItem?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.025, green: 0.05, blue: 0.10), Color(red: 0.07, green: 0.09, blue: 0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(.white.opacity(0.65))
                        Text("还没有下载文件")
                            .font(.headline)
                        Text("导出角色卡、世界书、正则、预设后，这里会显示文件，并自动弹出保存/分享。")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    .foregroundStyle(.white)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(items) { item in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 12) {
                                        Image(systemName: icon(for: item.filename))
                                            .font(.system(size: 18, weight: .heavy))
                                            .frame(width: 38, height: 38)
                                            .background(.white.opacity(0.12), in: Circle())
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.filename)
                                                .font(.system(size: 15, weight: .heavy))
                                                .lineLimit(2)
                                            Text("\(item.sizeText) · \(item.source)")
                                                .font(.caption)
                                                .foregroundStyle(.white.opacity(0.58))
                                        }
                                        Spacer()
                                    }
                                    HStack(spacing: 8) {
                                        Button {
                                            shareItem = item
                                        } label: {
                                            Label("保存/分享", systemImage: "square.and.arrow.down")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.borderedProminent)

                                        Button {
                                            UIPasteboard.general.url = item.fileURL
                                        } label: {
                                            Label("复制", systemImage: "doc.on.doc")
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    .font(.caption.bold())
                                }
                                .foregroundStyle(.white)
                                .padding(14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(.white.opacity(0.16))
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("下载中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("清空") { clear() }
                        .disabled(items.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $shareItem) { item in
            ActivitySheet(items: [item.fileURL])
        }
    }

    private func icon(for filename: String) -> String {
        let lower = filename.lowercased()
        if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".webp") { return "photo" }
        if lower.hasSuffix(".json") { return "curlybraces" }
        if lower.hasSuffix(".zip") { return "archivebox" }
        return "doc.fill"
    }
}

final class DownloadRegistry {
    static let shared = DownloadRegistry()
    private var destinations: [ObjectIdentifier: URL] = [:]

    func set(_ url: URL, for download: WKDownload) {
        destinations[ObjectIdentifier(download)] = url
    }

    func take(for download: WKDownload) -> URL? {
        destinations.removeValue(forKey: ObjectIdentifier(download))
    }
}

struct DownloadToast: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 15, weight: .black))
            Text(message)
                .font(.system(size: 13, weight: .heavy))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.20)))
        .padding(.horizontal, 16)
        .padding(.top, 54)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
