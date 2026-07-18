import Foundation
import Observation

struct TranslationModel: Identifiable, Hashable {
    let id: String

    var name: String { id.split(separator: "/").last.map(String.init) ?? id }

    var summary: String {
        let size = name.contains("1.8B") ? "1.8B · 更适合轻量本机" : name.contains("7B") ? "7B · 更高翻译质量" : "Hy-MT2"
        let precision = (name.contains("bf16") || name == "Hy-MT2-1.8B" || name == "Hy-MT2-7B") ? "bf16，最高精度、占用最大" : name.contains("8bit") ? "8-bit，平衡推荐" : name.contains("4bit") ? "4-bit，最省内存" : ""
        return [size, precision].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

@MainActor
@Observable
final class ModelCatalog {
    static let collectionURL = URL(string: "https://huggingface.co/collections/mlx-community/hy-mt2-6a15a173a4e2d27031541558")!
    static let defaultRepositoryID = "mlx-community/Hy-MT2-1.8B-8bit"

    private(set) var models = seededModels
    private(set) var isRefreshing = false

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let apiURL = URL(string: "https://huggingface.co/api/collections/mlx-community/hy-mt2-6a15a173a4e2d27031541558")!
        do {
            let (data, response) = try await URLSession.shared.data(from: apiURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            var identifiers = Set<String>()
            Self.collectModelIdentifiers(in: json, into: &identifiers)
            let remote = identifiers.map(TranslationModel.init(id:))
            if !remote.isEmpty { models = Self.sorted(Set(models).union(remote)) }
        } catch {
            // The bundled catalog remains available when the collection is offline.
        }
    }

    func model(for id: String) -> TranslationModel? { models.first { $0.id == id } }

    private static let seededModels = sorted([
        TranslationModel(id: "mlx-community/Hy-MT2-1.8B-4bit"),
        TranslationModel(id: "mlx-community/Hy-MT2-1.8B-8bit"),
        TranslationModel(id: "mlx-community/Hy-MT2-1.8B-bf16"),
        TranslationModel(id: "mlx-community/Hy-MT2-1.8B"),
        TranslationModel(id: "mlx-community/Hy-MT2-7B-4bit"),
        TranslationModel(id: "mlx-community/Hy-MT2-7B-8bit"),
        TranslationModel(id: "mlx-community/Hy-MT2-7B-bf16"),
        TranslationModel(id: "mlx-community/Hy-MT2-7B")
    ])

    private static func collectModelIdentifiers(in value: Any, into identifiers: inout Set<String>) {
        if let string = value as? String, string.hasPrefix("mlx-community/Hy-MT2-") {
            identifiers.insert(string)
        } else if let array = value as? [Any] {
            array.forEach { collectModelIdentifiers(in: $0, into: &identifiers) }
        } else if let dictionary = value as? [String: Any] {
            dictionary.values.forEach { collectModelIdentifiers(in: $0, into: &identifiers) }
        }
    }

    private static func sorted(_ models: Set<TranslationModel>) -> [TranslationModel] {
        models.sorted { left, right in
            let rank: (TranslationModel) -> (Int, Int, String) = { model in
                let size = model.id.contains("1.8B") ? 0 : model.id.contains("7B") ? 1 : model.id.contains("30B") ? 2 : 3
                let precision = (model.id.contains("bf16") || model.id.hasSuffix("Hy-MT2-1.8B") || model.id.hasSuffix("Hy-MT2-7B")) ? 0 : model.id.contains("8bit") ? 1 : model.id.contains("4bit") ? 2 : 3
                return (size, precision, model.id)
            }
            return rank(left) < rank(right)
        }
    }
}
