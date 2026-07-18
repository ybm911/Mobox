import Foundation
import Observation

@MainActor
@Observable
final class ModelDownloader {
    static let repositoryID = ModelCatalog.defaultRepositoryID

    private(set) var isDownloading = false
    private(set) var isDownloaded = false
    private(set) var localModelURL: URL?
    private(set) var progress: Double?
    private(set) var downloadedBytes: Int64 = 0
    private(set) var totalBytes: Int64?
    private(set) var statusMessage = "尚未下载"

    private var process: Process?
    private var outputHandle: FileHandle?
    private var pollingTimer: Timer?
    private var selectedRepositoryID = ModelCatalog.defaultRepositoryID

    var repositoryURL: URL? { URL(string: "https://huggingface.co/\(selectedRepositoryID)") }

    static var cacheRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LingyiTranslate/HuggingFace", isDirectory: true)
    }

    private static var cacheRoots: [URL] {
        [
            cacheRoot,
            URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(".cache/huggingface", isDirectory: true)
        ]
    }

    init() {
        refreshLocalModelStatus()
    }

    func selectModel(_ repositoryID: String) {
        guard !isDownloading else { return }
        selectedRepositoryID = repositoryID
        refreshLocalModelStatus()
    }

    func refreshLocalModelStatus() {
        localModelURL = Self.detectedModelURL(for: selectedRepositoryID)
        isDownloaded = localModelURL != nil
        if isDownloaded && !isDownloading {
            downloadedBytes = localModelURL.map { Self.directorySize(at: $0) } ?? 0
            progress = 1
            statusMessage = "模型已下载，可直接启动"
        } else if !isDownloading {
            progress = nil
            statusMessage = "尚未下载"
        }
    }

    func download(pythonCommand: String, repositoryID: String, force: Bool = false) {
        cancel()
        selectedRepositoryID = repositoryID
        do {
            try FileManager.default.createDirectory(at: Self.cacheRoot, withIntermediateDirectories: true)
        } catch {
            statusMessage = "无法创建模型缓存目录：\(error.localizedDescription)"
            return
        }

        let process = Process()
        let output = Pipe()
        let resolvedPython = (pythonCommand as NSString).expandingTildeInPath
        let script = Self.downloadScript
        if resolvedPython.contains("/") {
            process.executableURL = URL(fileURLWithPath: resolvedPython)
            process.arguments = ["-u", "-c", script, selectedRepositoryID, force ? "1" : "0"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [resolvedPython, "-u", "-c", script, selectedRepositoryID, force ? "1" : "0"]
        }
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HOME"] = Self.cacheRoot.path
        environment["HF_HUB_DISABLE_PROGRESS_BARS"] = "0"
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            Task { @MainActor [weak self, text] in self?.consume(text) }
        }
        process.terminationHandler = { [weak self] task in
            let status = task.terminationStatus
            Task { @MainActor [weak self, status] in
                guard let self else { return }
                self.finish(exitStatus: status)
            }
        }

        do {
            try process.run()
            self.process = process
            outputHandle = output.fileHandleForReading
            isDownloading = true
            progress = 0
            downloadedBytes = 0
            totalBytes = nil
            statusMessage = "正在读取模型文件列表…"
            pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateByteProgress() }
            }
        } catch {
            statusMessage = "无法启动下载器：\(error.localizedDescription)"
        }
    }

    func cancel() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        outputHandle?.readabilityHandler = nil
        outputHandle = nil
        process?.terminate()
        process = nil
        if isDownloading { statusMessage = "下载已取消" }
        isDownloading = false
    }

    var progressLabel: String {
        if let totalBytes, totalBytes > 0 {
            return "\(Self.byteFormatter.string(fromByteCount: downloadedBytes)) / \(Self.byteFormatter.string(fromByteCount: totalBytes))"
        }
        return progress == nil ? "正在准备下载…" : "正在下载…"
    }

    private func consume(_ text: String) {
        for line in text.components(separatedBy: CharacterSet.newlines.union(.controlCharacters)) where !line.isEmpty {
            if line.hasPrefix("LINGYI_TOTAL=") {
                totalBytes = Int64(line.dropFirst("LINGYI_TOTAL=".count))
                updateByteProgress()
            } else if line.contains("LINGYI_COMPLETE") {
                progress = 1
                statusMessage = "模型下载完成"
            } else {
                statusMessage = line.trimmingCharacters(in: .whitespacesAndNewlines).suffix(180).description
            }
        }
    }

    private func updateByteProgress() {
        let bytes = Self.directorySize(at: Self.cacheRoot)
        downloadedBytes = bytes
        if let totalBytes, totalBytes > 0 {
            progress = min(1, Double(bytes) / Double(totalBytes))
        }
    }

    private func finish(exitStatus: Int32) {
        pollingTimer?.invalidate()
        pollingTimer = nil
        outputHandle?.readabilityHandler = nil
        outputHandle = nil
        process = nil
        updateByteProgress()
        isDownloading = false
        if exitStatus == 0 {
            refreshLocalModelStatus()
        } else if !statusMessage.contains("取消") {
            statusMessage = "下载失败（状态 \(exitStatus)）：\(statusMessage)"
        }
    }

    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true else { continue }
            size += Int64(values.fileSize ?? 0)
        }
        return size
    }

    private static func detectedModelURL(for repositoryID: String) -> URL? {
        let cacheDirectoryName = "models--" + repositoryID.replacingOccurrences(of: "/", with: "--")
        for root in cacheRoots {
            let snapshots = root.appendingPathComponent("hub/\(cacheDirectoryName)/snapshots", isDirectory: true)
            guard let candidates = try? FileManager.default.contentsOfDirectory(
                at: snapshots,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            if let snapshot = candidates
                .filter({ (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
                .sorted(by: {
                    let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return left > right
                })
                .first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("config.json").path) }) {
                return snapshot
            }
        }
        return nil
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static let downloadScript = """
import json
import sys
from huggingface_hub import HfApi, snapshot_download

repo = sys.argv[1]
force_download = sys.argv[2] == "1"
try:
    info = HfApi().model_info(repo, files_metadata=True)
    total = sum((item.size or 0) for item in info.siblings)
    print(f"LINGYI_TOTAL={total}", flush=True)
except Exception as error:
    print(f"LINGYI_INFO_ERROR={error}", flush=True)

snapshot_download(repo_id=repo, force_download=force_download)
print("LINGYI_COMPLETE", flush=True)
"""
}
