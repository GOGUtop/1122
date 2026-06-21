import Foundation

final class EdgeTranslatorService {
    static let shared = EdgeTranslatorService()
    private init() {}

    private var cachedToken: String?
    private var tokenTime: Date?

    func translate(_ text: String, to language: String = "zh-Hans", completion: @escaping (Result<String, Error>) -> Void) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            completion(.success(""))
            return
        }
        Task {
            do {
                let translated = try await translateAsync(value, to: language)
                await MainActor.run { completion(.success(translated)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
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
        request.timeoutInterval = 18
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
           Date().timeIntervalSince(tokenTime) < 7 * 60 {
            return cachedToken
        }
        var request = URLRequest(url: URL(string: "https://edge.microsoft.com/translate/auth")!)
        request.timeoutInterval = 12
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
