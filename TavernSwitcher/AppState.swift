import Foundation
import WebKit

struct TavernEndpoint: Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String
    let icon: String

    var url: URL {
        URL(string: "http://aaa.xixisillytavern.top:\(id)")!
    }

    static let all: [TavernEndpoint] = [
        .init(id: 8000, title: "阿里云 1 号云洞", subtitle: "8000 入口", icon: "airplane"),
        .init(id: 8443, title: "阿里云 2 号云洞", subtitle: "8443 入口", icon: "cloud.fill"),
        .init(id: 8888, title: "西西画家云洞", subtitle: "8888 入口", icon: "paintpalette.fill")
    ]
}

@MainActor
final class AppState: ObservableObject {
    @Published var activeEndpoint: TavernEndpoint?
    @Published var showSwitcher = false
    @Published var reloadToken = UUID()
    @Published var resetToken = UUID()
    @Published var floatingOpacity = UserDefaults.standard.object(forKey: "floatingOpacity") as? Double ?? 0.88
    @Published var pageZoom = UserDefaults.standard.object(forKey: "pageZoom") as? Double ?? 0.94
    @Published var bottomSafePadding = UserDefaults.standard.object(forKey: "bottomSafePadding") as? Double ?? 26
    @Published var enhancedKeepAlive = UserDefaults.standard.object(forKey: "enhancedKeepAlive") as? Bool ?? true
    @Published var autoPreventSleep = UserDefaults.standard.object(forKey: "autoPreventSleep") as? Bool ?? true

    private let lastPortKey = "lastEndpointPort"

    var lastPort: Int {
        UserDefaults.standard.integer(forKey: lastPortKey)
    }

    func open(_ endpoint: TavernEndpoint) {
        UserDefaults.standard.set(endpoint.id, forKey: lastPortKey)
        activeEndpoint = endpoint
        showSwitcher = false
    }

    func resetWebData() {
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            store.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                for: records
            ) {
                Task { @MainActor in
                    self.resetToken = UUID()
                    self.reloadToken = UUID()
                }
            }
        }
    }

    func saveFloatingOpacity(_ value: Double) {
        floatingOpacity = value
        UserDefaults.standard.set(value, forKey: "floatingOpacity")
    }

    func savePageZoom(_ value: Double) {
        pageZoom = value
        UserDefaults.standard.set(value, forKey: "pageZoom")
    }

    func saveBottomSafePadding(_ value: Double) {
        bottomSafePadding = value
        UserDefaults.standard.set(value, forKey: "bottomSafePadding")
    }

    func saveEnhancedKeepAlive(_ value: Bool) {
        enhancedKeepAlive = value
        UserDefaults.standard.set(value, forKey: "enhancedKeepAlive")
    }

    func saveAutoPreventSleep(_ value: Bool) {
        autoPreventSleep = value
        UserDefaults.standard.set(value, forKey: "autoPreventSleep")
    }

    var webBottomPadding: Double {
        bottomSafePadding
    }

}
