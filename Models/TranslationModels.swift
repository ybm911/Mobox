import Foundation

enum TranslationDirection: String, CaseIterable, Codable, Identifiable {
    case englishToChinese
    case chineseToEnglish

    var id: String { rawValue }

    var title: String {
        switch self {
        case .englishToChinese: "English → 中文"
        case .chineseToEnglish: "中文 → English"
        }
    }

    var sourceLabel: String { self == .englishToChinese ? "英语" : "中文" }
    var targetLabel: String { self == .englishToChinese ? "中文" : "英语" }
    var sourcePlaceholder: String { self == .englishToChinese ? "输入或粘贴英文…" : "输入或粘贴中文…" }
    var targetPlaceholder: String { self == .englishToChinese ? "中文翻译会显示在这里" : "English translation will appear here" }
    var instruction: String {
        switch self {
        case .englishToChinese:
            "You are a precise English-to-Simplified-Chinese translator. Translate the user's English into natural Simplified Chinese. Return only the translated text, preserving formatting."
        case .chineseToEnglish:
            "You are a precise Simplified-Chinese-to-English translator. Translate the user's Chinese into natural English. Return only the translated text, preserving formatting."
        }
    }
}

enum ServerExposure: String, CaseIterable, Codable, Identifiable {
    case disabled
    case thisMac
    case localNetwork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled: "关闭接口"
        case .thisMac: "仅本机提供"
        case .localNetwork: "对局域网提供"
        }
    }

    var description: String {
        switch self {
        case .disabled: "不启动翻译接口"
        case .thisMac: "只接受 127.0.0.1 的请求"
        case .localNetwork: "允许同一局域网的设备访问；请保管好令牌"
        }
    }
}

struct TranslationResult: Sendable {
    let text: String
}

enum TranslationError: LocalizedError {
    case emptyText
    case serverNotReady
    case invalidResponse
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .emptyText: "请输入需要翻译的英文。"
        case .serverNotReady: "MLX 模型服务尚未就绪。请先在设置中启动模型。"
        case .invalidResponse: "模型返回了无法识别的内容。"
        case .remote(let message): message
        }
    }
}
