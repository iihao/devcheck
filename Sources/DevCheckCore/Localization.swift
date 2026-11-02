import Foundation

public enum Language: String, Sendable {
    case en
    case zh
}

/// 极简双语支持：默认跟随系统语言，可用 `DEVCHECK_LANG=en|zh` 强制。
///
/// 用法：`L("中文文案", "English text")`
public final class L10n: @unchecked Sendable {
    public static let shared = L10n()

    private let lock = NSLock()
    private var _language: Language = Language.detect()

    public var language: Language {
        lock.lock()
        defer { lock.unlock() }
        return _language
    }

    public func setLanguage(_ language: Language) {
        lock.lock()
        _language = language
        lock.unlock()
    }

    public func string(zh: String, en: String) -> String {
        language == .zh ? zh : en
    }
}

/// 短别名，避免在业务代码里写长串
@inlinable
public func L(_ zh: String, _ en: String) -> String {
    L10n.shared.string(zh: zh, en: en)
}

extension Language {
    /// 优先级：DEVCHECK_LANG > LANG/LC_* > macOS 的 AppleLanguages > 英文
    static func detect() -> Language {
        let environment = ProcessInfo.processInfo.environment

        if let forced = environment["DEVCHECK_LANG"]?.lowercased(), !forced.isEmpty {
            return forced.hasPrefix("zh") ? .zh : .en
        }

        for key in ["LC_ALL", "LC_MESSAGES", "LANG"] {
            if let value = environment[key]?.lowercased(), !value.isEmpty {
                return value.hasPrefix("zh") ? .zh : .en
            }
        }

        // 从 Finder 启动的 .app 没有 LANG，读系统首选语言
        if let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first?.lowercased() {
            return preferred.hasPrefix("zh") ? .zh : .en
        }

        return .en
    }
}