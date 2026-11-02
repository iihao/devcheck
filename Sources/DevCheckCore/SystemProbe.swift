import Foundation
import Darwin

/// 机器级状态：负载 / 运行时长 / 磁盘 / 内存。
public enum SystemProbe {
    public static func current() -> SystemStatus {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)

        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/")
        let free = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let total = (attributes?[.systemSize] as? NSNumber)?.int64Value ?? 0

        let info = ProcessInfo.processInfo
        let uptime = info.systemUptime

        return SystemStatus(
            load1: loads[0],
            load5: loads[1],
            load15: loads[2],
            uptimeSeconds: uptime,
            bootTime: Date(timeIntervalSinceNow: -uptime),
            diskFreeBytes: free,
            diskTotalBytes: total,
            physicalMemoryBytes: info.physicalMemory,
            cpuCount: info.processorCount
        )
    }
}