import Foundation
import Observation

@MainActor
@Observable
final class MLXServerManager {
    private(set) var isRunning = false
    private(set) var statusMessage = "尚未启动"
    private var process: Process?
    private var outputHandle: FileHandle?

    func start(pythonCommand: String, modelIdentifier: String, port: Int) {
        stop()
        let process = Process()
        let output = Pipe()
        let resolvedPython = (pythonCommand as NSString).expandingTildeInPath
        let serverArguments = ["-m", "mlx_lm.server", "--model", modelIdentifier, "--host", "127.0.0.1", "--port", "\(port)"]
        if resolvedPython.contains("/") {
            process.executableURL = URL(fileURLWithPath: resolvedPython)
            process.arguments = serverArguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [resolvedPython] + serverArguments
        }
        process.standardOutput = output
        process.standardError = output
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HOME"] = ModelDownloader.cacheRoot.path
        process.environment = environment
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let line = String(data: data, encoding: .utf8), !line.isEmpty else { return }
            Task { @MainActor [weak self, line] in
                self?.statusMessage = line.trimmingCharacters(in: .whitespacesAndNewlines).suffix(180).description
            }
        }
        process.terminationHandler = { [weak self] process in
            let exitStatus = process.terminationStatus
            Task { @MainActor [weak self, exitStatus] in
                self?.isRunning = false
                self?.statusMessage = "模型服务已退出（状态 \(exitStatus)）"
            }
        }
        do {
            try process.run()
            self.process = process
            outputHandle = output.fileHandleForReading
            isRunning = true
            statusMessage = "正在启动 MLX 模型服务…"
        } catch {
            statusMessage = "无法启动：\(error.localizedDescription)"
        }
    }

    func stop() {
        outputHandle?.readabilityHandler = nil
        outputHandle = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        isRunning = false
        if statusMessage != "尚未启动" { statusMessage = "已停止" }
    }
}
