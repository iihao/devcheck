import Foundation

// 必须是同步顶层代码：NSApplication 只能在主线程创建，
// 若在顶层写 `await`，后续代码可能被调度到后台线程，导致
// "NSWindow should only be instantiated on the main thread" 崩溃。
let exitCode = CLI.run(Array(CommandLine.arguments.dropFirst()))
exit(exitCode)