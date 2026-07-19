import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class UpdateManager {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/ybm911/Mobox/releases/latest")!
    private let defaults = UserDefaults.standard

    var automaticallyChecks: Bool {
        didSet { defaults.set(automaticallyChecks, forKey: "automaticallyChecksForUpdates") }
    }
    private(set) var isChecking = false
    private(set) var isInstalling = false
    private(set) var statusMessage = "尚未检查"
    private(set) var latestRelease: Release?
    private(set) var hasCheckedThisLaunch = false
    var updateAvailable = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1"
    }

    init() {
        automaticallyChecks = defaults.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true
    }

    func checkAtLaunchIfNeeded() async {
        guard automaticallyChecks, !hasCheckedThisLaunch else { return }
        await checkForUpdates()
    }

    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        hasCheckedThisLaunch = true
        defer { isChecking = false }
        do {
            var request = URLRequest(url: Self.latestReleaseURL)
            request.timeoutInterval = 15
            request.setValue("Mobox macOS updater", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
            guard http.statusCode != 404 else {
                statusMessage = "尚未发布可下载版本"
                return
            }
            guard (200..<300).contains(http.statusCode) else { throw UpdateError.httpStatus(http.statusCode) }
            let release = try JSONDecoder().decode(Release.self, from: data)
            latestRelease = release
            guard !release.draft, !release.prerelease, let asset = release.assets.first(where: { $0.name == "Mobox-macOS-arm64.zip" }) else {
                statusMessage = "未找到适用于 Apple Silicon 的更新包"
                return
            }
            if Self.isNewer(release.tagName, than: currentVersion) {
                updateAvailable = true
                statusMessage = "发现新版本 \(release.tagName)"
                latestRelease = Release(tagName: release.tagName, htmlURL: release.htmlURL, draft: release.draft, prerelease: release.prerelease, assets: [asset])
            } else {
                updateAvailable = false
                statusMessage = "已是最新版本（\(currentVersion)）"
            }
        } catch {
            statusMessage = "检查更新失败：\(error.localizedDescription)"
        }
    }

    func dismissUpdate() {
        updateAvailable = false
    }

    func downloadAndInstall() async {
        guard let asset = latestRelease?.assets.first else { return }
        isInstalling = true
        statusMessage = "正在下载 \(latestRelease?.tagName ?? "更新")…"
        defer { isInstalling = false }
        do {
            let (archiveURL, _) = try await URLSession.shared.download(from: asset.browserDownloadURL)
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Mobox-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            try Self.unzip(archiveURL, into: staging)
            guard let appBundle = Self.findAppBundle(in: staging) else { throw UpdateError.missingAppBundle }
            let applications = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first!
            try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
            let destination = applications.appendingPathComponent("Mobox.app", isDirectory: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: appBundle, to: destination)
            statusMessage = "已安装到 ~/Applications/Mobox.app"
            NSWorkspace.shared.open(destination)
            NSApp.terminate(nil)
        } catch {
            statusMessage = "下载安装失败：\(error.localizedDescription)"
        }
    }

    private static func unzip(_ archive: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, directory.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.unzipFailed }
    }

    private static func findAppBundle(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for case let url as URL in enumerator where url.pathExtension == "app" { return url }
        return nil
    }

    private static func isNewer(_ candidate: String, than current: String) -> Bool {
        let parts: (String) -> [Int] = { value in
            value.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .split(separator: ".")
                .map { Int($0) ?? 0 }
        }
        let proposed = parts(candidate)
        let installed = parts(current)
        for index in 0..<max(proposed.count, installed.count) {
            let lhs = index < proposed.count ? proposed[index] : 0
            let rhs = index < installed.count ? installed[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            enum CodingKeys: String, CodingKey { case name; case browserDownloadURL = "browser_download_url" }
        }
        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", htmlURL = "html_url", draft, prerelease, assets
        }
    }

    enum UpdateError: LocalizedError {
        case invalidResponse, httpStatus(Int), missingAppBundle, unzipFailed
        var errorDescription: String? {
            switch self {
            case .invalidResponse: "GitHub 返回了无效响应"
            case .httpStatus(let status): "GitHub 返回 HTTP \(status)"
            case .missingAppBundle: "更新包中没有 Mobox.app"
            case .unzipFailed: "无法解压更新包"
            }
        }
    }
}
