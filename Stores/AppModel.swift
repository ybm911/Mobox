import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var sourceText = ""
    var translatedText = ""
    var isTranslating = false
    var errorMessage: String?
    var activityMessage: String?

    var modelIdentifier: String
    var pythonCommand: String
    var modelPort: Int
    var apiPort: Int
    var exposure: ServerExposure
    var apiKey: String
    var direction: TranslationDirection

    let mlxServer = MLXServerManager()
    let modelDownloader = ModelDownloader()
    let modelCatalog = ModelCatalog()
    let apiServer = LocalTranslationServer()

    private let defaults = UserDefaults.standard
    private var terminationObserver: NSObjectProtocol?

    init() {
        modelIdentifier = defaults.string(forKey: "modelIdentifier") ?? "mlx-community/Hy-MT2-1.8B-8bit"
        pythonCommand = defaults.string(forKey: "pythonCommand") ?? "python3"
        modelPort = defaults.object(forKey: "modelPort") as? Int ?? 8080
        apiPort = defaults.object(forKey: "apiPort") as? Int ?? 8787
        exposure = ServerExposure(rawValue: defaults.string(forKey: "exposure") ?? "disabled") ?? .disabled
        apiKey = defaults.string(forKey: "apiKey") ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
        direction = TranslationDirection(rawValue: defaults.string(forKey: "direction") ?? "englishToChinese") ?? .englishToChinese
        modelDownloader.selectModel(modelIdentifier)
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.shutdown() }
        }
    }

    var modelEndpoint: URL { URL(string: "http://127.0.0.1:\(modelPort)")! }
    var localAPIURL: String { "http://127.0.0.1:\(apiPort)/v1/chat/completions" }
    var networkAPIURL: String { "http://<本机局域网IP>:\(apiPort)/v1/chat/completions" }

    func savePreferences() {
        defaults.set(modelIdentifier, forKey: "modelIdentifier")
        defaults.set(pythonCommand, forKey: "pythonCommand")
        defaults.set(modelPort, forKey: "modelPort")
        defaults.set(apiPort, forKey: "apiPort")
        defaults.set(exposure.rawValue, forKey: "exposure")
        defaults.set(apiKey, forKey: "apiKey")
        defaults.set(direction.rawValue, forKey: "direction")
    }

    func startModel() {
        savePreferences()
        modelDownloader.selectModel(modelIdentifier)
        modelDownloader.refreshLocalModelStatus()
        let modelSource = modelDownloader.localModelURL?.path ?? modelIdentifier
        mlxServer.start(pythonCommand: pythonCommand, modelIdentifier: modelSource, port: modelPort)
    }

    func stopModel() {
        mlxServer.stop()
    }

    func selectModel(_ repositoryID: String) {
        modelIdentifier = repositoryID
        modelDownloader.selectModel(repositoryID)
        savePreferences()
    }

    func downloadSelectedModel() {
        savePreferences()
        modelDownloader.download(pythonCommand: pythonCommand, repositoryID: modelIdentifier)
    }

    func redownloadSelectedModel() {
        savePreferences()
        modelDownloader.download(pythonCommand: pythonCommand, repositoryID: modelIdentifier, force: true)
    }

    func toggleDirection() {
        direction = direction == .englishToChinese ? .chineseToEnglish : .englishToChinese
        let previousSource = sourceText
        sourceText = translatedText
        translatedText = previousSource
        errorMessage = nil
        savePreferences()
    }

    func translate() async {
        let input = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            errorMessage = TranslationError.emptyText.localizedDescription
            return
        }
        isTranslating = true
        errorMessage = nil
        activityMessage = "正在等待本机模型就绪…"
        defer {
            isTranslating = false
            activityMessage = nil
        }
        do {
            guard mlxServer.isRunning else { throw TranslationError.serverNotReady }
            try await TranslationClient.waitUntilReady(endpoint: modelEndpoint)
            activityMessage = "正在翻译…"
            translatedText = try await TranslationClient.translate(
                text: input,
                endpoint: modelEndpoint,
                direction: direction
            ).text
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyExposure(_ newExposure: ServerExposure) {
        exposure = newExposure
        savePreferences()
        apiServer.stop()
        guard newExposure != .disabled else { return }

        let endpoint = modelEndpoint
        let direction = direction
        apiServer.start(
            exposure: newExposure,
            port: apiPort,
            apiKey: apiKey,
            translationHandler: { text in
                try await TranslationClient.translate(text: text, endpoint: endpoint, direction: direction).text
            }
        )
    }

    func restoreSavedService() {
        guard exposure != .disabled, !apiServer.isRunning else { return }
        applyExposure(exposure)
    }

    func shutdown() {
        apiServer.stop()
        mlxServer.stop()
        modelDownloader.cancel()
    }
}
