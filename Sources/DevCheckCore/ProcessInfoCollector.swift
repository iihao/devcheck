import Foundation

/// 进程侧信息：工作目录 + 资源占用。
///
/// 两次调用即可覆盖全部 PID，不做 N 次 fork：
/// - `lsof -a -d cwd -p 1,2,3 -Fpn`
/// - `ps -o pid=,ppid=,pcpu=,rss=,etime= -p 1,2,3`
public enum ProcessInfoCollector {
    /// 批量取 PID → 工作目录
    public static func workingDirectories(for pids: [Int32]) -> [Int32: String] {
        let unique = Array(Set(pids))
        guard !unique.isEmpty else { return [:] }

        let list = unique.map(String.init).joined(separator: ",")
        guard let output = try? Shell.run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", list, "-Fpn"]) else {
            return [:]
        }

        var result: [Int32: String] = [:]
        var currentPID: Int32?
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                currentPID = Int32(value)
            case "n":
                if let pid = currentPID {
                    result[pid] = value
                }
            default:
                continue
            }
        }
        return result
    }

    /// 批量取 PID → CPU / 内存 / 运行时长
    public static func stats(for pids: [Int32]) -> [Int32: ProcessStat] {
        let unique = Array(Set(pids))
        guard !unique.isEmpty else { return [:] }

        let list = unique.map(String.init).joined(separator: ",")
        guard let output = try? Shell.run(
            "/bin/ps",
            ["-o", "pid=,ppid=,pcpu=,rss=,etime=,comm=", "-p", list]
        ) else { return [:] }

        var result: [Int32: ProcessStat] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 5,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]),
                  let cpu = Double(parts[2]),
                  let rss = Int(parts[3])
            else { continue }

            // comm 是最后一列，且可能含空格（如 "Code Helper"），直接取剩余部分
            let executable = parts.count > 5
                ? parts[5...].joined(separator: " ")
                : ""

            result[pid] = ProcessStat(
                pid: pid,
                ppid: ppid,
                cpuPercent: cpu,
                rssKB: rss,
                elapsed: String(parts[4]),
                executable: executable
            )
        }
        return result
    }

    public static func parentPID(of pid: Int32) -> Int32? {
        stats(for: [pid])[pid]?.ppid
    }
}