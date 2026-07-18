import Foundation

enum TranslationClient {
    static func translate(text: String, endpoint: URL, direction: TranslationDirection) async throws -> TranslationResult {
        guard !text.isEmpty else { throw TranslationError.emptyText }
        let url = endpoint.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "temperature": 0.7,
            "top_p": 0.6,
            "top_k": 20,
            "repetition_penalty": 1.05,
            "max_tokens": max(128, min(4096, text.count * 4)),
            "messages": [
                ["role": "user", "content": translationPrompt(for: text, direction: direction)]
            ]
        ])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw TranslationError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw TranslationError.remote("模型服务错误：\(message)")
            }
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
                throw TranslationError.invalidResponse
            }
            return TranslationResult(text: content)
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.remote("无法连接 MLX 服务：\(error.localizedDescription)")
        }
    }

    private static func translationPrompt(for text: String, direction: TranslationDirection) -> String {
        let targetLanguage = direction == .englishToChinese ? "Chinese" : "English"
        return "Translate the following text into \(targetLanguage). Note that you should only output the translated result without any additional explanation:\n\n\(text)"
    }

    static func waitUntilReady(endpoint: URL, timeout: TimeInterval = 90) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        let url = endpoint.appendingPathComponent("v1/models")
        while Date() < deadline {
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               http.statusCode < 500 {
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw TranslationError.remote("模型服务在 90 秒内未就绪。请确认已下载模型，并查看设置中的模型服务状态。")
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}
