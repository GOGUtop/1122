import Foundation

final class EdgeTranslatorService {
    static let shared = EdgeTranslatorService()
    private init() {
        translationCache.countLimit = 160
    }

    private var cachedToken: String?
    private var tokenTime: Date?
    private let translationCache = NSCache<NSString, NSString>()

    func translate(_ text: String, to language: String = "zh-Hans", completion: @escaping (Result<String, Error>) -> Void) {
        let value = sanitize(text)
        guard !value.isEmpty else {
            completion(.success(""))
            return
        }

        // 选中文字本身已经是中文时，不再走网络请求，避免等待和失败。
        if language.lowercased().hasPrefix("zh"), looksLikeChinese(value) {
            completion(.success(value))
            return
        }

        let key = cacheKey(value, language: language) as NSString
        if let cached = translationCache.object(forKey: key) {
            completion(.success(cached as String))
            return
        }

        Task {
            do {
                let translated = try await translateAsync(value, to: language)
                translationCache.setObject(translated as NSString, forKey: key)
                await MainActor.run { completion(.success(translated)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    private func sanitize(_ text: String) -> String {
        let trimmed = text
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 4800 { return trimmed }
        return String(trimmed.prefix(4800))
    }

    private func looksLikeChinese(_ text: String) -> Bool {
        var chinese = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) {
                chinese += 1
            } else if (65...90).contains(value) || (97...122).contains(value) {
                latin += 1
            }
        }
        return chinese >= 4 && chinese >= latin
    }

    private func cacheKey(_ text: String, language: String) -> String {
        "edge:\(language):\(text.hashValue):\(text.count)"
    }

    private func translateAsync(_ text: String, to language: String) async throws -> String {
        let token = try await edgeAuthToken()
        var components = URLComponents(string: "https://api-edge.cognitive.microsofttranslator.com/translate")!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "to", value: language),
            URLQueryItem(name: "textType", value: "plain")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 14
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://edge.microsoft.com", forHTTPHeaderField: "Origin")
        request.setValue("https://edge.microsoft.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1 Edg/126.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [["Text": text]], options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslatorError.http(status, body)
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let translations = object?.first?["translations"] as? [[String: Any]]
        if let text = translations?.first?["text"] as? String, !text.isEmpty {
            return text
        }
        throw TranslatorError.emptyResult
    }

    private func edgeAuthToken() async throws -> String {
        if let cachedToken,
           let tokenTime,
           Date().timeIntervalSince(tokenTime) < 9 * 60 {
            return cachedToken
        }
        var request = URLRequest(url: URL(string: "https://edge.microsoft.com/translate/auth")!)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1 Edg/126.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw TranslatorError.auth(status)
        }
        let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else { throw TranslatorError.emptyToken }
        cachedToken = token
        tokenTime = Date()
        return token
    }
}

enum TranslatorError: LocalizedError {
    case auth(Int)
    case http(Int, String)
    case emptyToken
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .auth(let status):
            return "Edge 翻译授权失败（HTTP \(status)）"
        case .http(let status, let body):
            let tail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return tail.isEmpty ? "Edge 翻译失败（HTTP \(status)）" : "Edge 翻译失败（HTTP \(status)：\(tail.prefix(120))）"
        case .emptyToken:
            return "Edge 翻译授权为空"
        case .emptyResult:
            return "Edge 翻译结果为空"
        }
    }
}
