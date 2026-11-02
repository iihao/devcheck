import Foundation

/// 版本号：打包时由脚本替换或在编译期注入，这里给出兜底值。
enum DevCheckVersion {
    static var current: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !version.isEmpty {
            return version
        }
        return "0.1.1"
    }
}