import Foundation
import Network
import Observation

@MainActor
@Observable
final class LocalTranslationServer {
    private(set) var isRunning = false
    private(set) var statusMessage = "接口未启动"
    private var listener: NWListener?
    private var apiKey = ""
    private var handler: (@Sendable (String) async throws -> String)?

    func start(exposure: ServerExposure, port: Int, apiKey: String, translationHandler: @escaping @Sendable (String) async throws -> String) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            statusMessage = "接口端口无效"
            return
        }
        let parameters = NWParameters.tcp
        if exposure == .thisMac { parameters.requiredInterfaceType = .loopback }
        do {
            let listener = try NWListener(using: parameters, on: nwPort)
            self.apiKey = apiKey
            handler = translationHandler
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self, state] in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.statusMessage = exposure == .thisMac ? "仅本机接口已启动" : "局域网接口已启动"
                    case .failed(let error):
                        self?.isRunning = false
                        self?.statusMessage = "接口失败：\(error.localizedDescription)"
                    case .cancelled:
                        self?.isRunning = false
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global(qos: .userInitiated))
                Task { @MainActor [weak self] in
                    self?.receiveRequest(on: connection)
                }
            }
            self.listener = listener
            listener.start(queue: .global(qos: .userInitiated))
        } catch {
            statusMessage = "接口无法启动：\(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        if statusMessage != "接口未启动" { statusMessage = "接口已停止" }
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, _, error in
            guard let data, error == nil else {
                connection.cancel()
                return
            }
            Task { @MainActor [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }
                let completeData = buffer + data
                guard self.hasCompleteRequest(completeData) else {
                    self.receiveRequest(on: connection, buffer: completeData)
                    return
                }
                let response = await self.response(for: completeData)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    private func hasCompleteRequest(_ data: Data) -> Bool {
        guard let request = String(data: data, encoding: .utf8),
              let divider = request.range(of: "\r\n\r\n") else { return false }
        let header = String(request[..<divider.lowerBound])
        let length = header.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        return data.count >= header.utf8.count + 4 + length
    }

    private func response(for data: Data) async -> Data {
        guard let request = String(data: data, encoding: .utf8),
              let divider = request.range(of: "\r\n\r\n") else {
            return Self.httpResponse(status: 400, body: ["error": "Malformed HTTP request"])
        }
        let headerText = String(request[..<divider.lowerBound])
        let bodyText = String(request[divider.upperBound...])
        let headerLines = headerText.components(separatedBy: "\r\n")
        guard let firstLine = headerLines.first else { return Self.httpResponse(status: 400, body: ["error": "Missing request line"]) }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "POST" else { return Self.httpResponse(status: 405, body: ["error": "Only POST is supported"]) }
        let headers = Dictionary(uniqueKeysWithValues: headerLines.dropFirst().compactMap { line -> (String, String)? in
            let fragments = line.split(separator: ":", maxSplits: 1)
            guard fragments.count == 2 else { return nil }
            return (fragments[0].lowercased(), fragments[1].trimmingCharacters(in: .whitespaces))
        })
        let suppliedKey = headers["x-api-key"] ?? headers["authorization"]?.replacingOccurrences(of: "Bearer ", with: "")
        guard suppliedKey == apiKey else { return Self.httpResponse(status: 401, body: ["error": "Invalid API key"]) }
        guard let body = bodyText.data(using: .utf8) else {
            return Self.httpResponse(status: 400, body: ["error": "Expected JSON request body"])
        }
        let path = String(parts[1])
        let text: String
        if path == "/v1/chat/completions" {
            text = (try? JSONDecoder().decode(OpenAIRequest.self, from: body))?.messages.last(where: { $0.role == "user" })?.content ?? ""
        } else {
            let payload = try? JSONDecoder().decode(TranslatePayload.self, from: body)
            text = payload?.text ?? payload?.q ?? ""
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Self.httpResponse(status: 400, body: ["error": "text (or a user message) is required"])
        }
        do {
            guard let handler else { throw TranslationError.serverNotReady }
            let translated = try await handler(text)
            if path == "/v1/chat/completions" {
                return Self.httpResponse(status: 200, body: ["choices": [["message": ["role": "assistant", "content": translated]]]])
            }
            return Self.httpResponse(status: 200, body: ["translation": translated, "translations": [translated], "data": ["translation": translated]])
        } catch {
            return Self.httpResponse(status: 503, body: ["error": error.localizedDescription])
        }
    }

    private static func httpResponse(status: Int, body: [String: Any]) -> Data {
        let bodyData = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        let reason = status == 200 ? "OK" : status == 401 ? "Unauthorized" : status == 405 ? "Method Not Allowed" : "Error"
        var response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(bodyData)
        return response
    }
}

private struct TranslatePayload: Decodable {
    let text: String?
    let q: String?
}

private struct OpenAIRequest: Decodable {
    struct Message: Decodable {
        let role: String
        let content: String
    }
    let messages: [Message]
}
