import Foundation

/// 极简 shell 执行器：只跑系统自带命令，不引入任何依赖。
enum Shell {
    struct Failure: Error, CustomStringConvertible {
        let executable: String
        let status: Int32
        var description: String { "\(executable) exited with \(status)" }
    }

    /// 同步执行并返回 stdout 文本。命令失败时抛出，但调用方通常用 `try?` 容忍。
    @discardableResult
    static func run(_ executable: String, _ arguments: [String] = []) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw Failure(executable: executable, status: -1)
        }

        // 先读完再 wait，避免管道写满导致子进程阻塞
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw Failure(executable: executable, status: process.terminationStatus)
        }
        return String(decoding: data, as: UTF8.self)
    }
}