# DevCheck 架构设计（工程机体检 + 端口地图）

> 一句话定位：**给 Mac mini / Mac 开发机做一次 3 秒体检，看清「谁在跑、占哪个端口、属于哪个项目、是不是僵尸」。**

## 1. 目标与非目标

### 目标（P0）
- 端口地图：列出所有正在监听的端口 → 进程 → PID → **所属项目目录** → 启动方式。
- 服务体检：端口是否可达、端口冲突、单进程高 CPU、其他用户/root 占用的不可管理进程。
- 系统体检：负载、运行时长、磁盘剩余、内存总量。
- 一键操作：打开 `http://localhost:port`、复制地址、Finder 定位项目、SIGTERM 结束进程。
- 常驻形态：菜单栏 App，5 秒自动刷新，内存 < 60MB，空闲 CPU ≈ 0。

### 非目标（至少 M0/M1 不做）
- 不做 root 级全局端口枚举（需特权 helper，M3 再谈）。
- 不做流量抓包、Docker 编排、IDE 插件。
- 不做 jailbreak 式 hack（不改系统配置、不注入进程）。

## 2. 分层架构

```
┌──────────────────────────────────────────────────────────┐
│ UI 层                                                     │
│  · 菜单栏（AppKit NSStatusItem + NSMenu）  ← 主入口        │
│  · CLI（devcheck ports --json / doctor）    ← 给脚本/CI 用  │
│  · 本地 Web 面板（127.0.0.1:7788，M2）       ← 手机/大屏看   │
├──────────────────────────────────────────────────────────┤
│ 聚合层                                                     │
│  SnapshotBuilder：一次刷新 = 一个不可变 Snapshot            │
│  RuleEngine：基于 Snapshot 产出 Issue 列表                  │
├──────────────────────────────────────────────────────────┤
│ 采集层（全部走系统自带命令行，零第三方依赖）                 │
│  PortCollector          lsof -iTCP -sTCP:LISTEN -FpcPnu    │
│  ProcessInfoCollector   lsof -d cwd / ps -o pid,ppid,cpu   │
│  SystemProbe            getloadavg / FileManager / NSNumber│
├──────────────────────────────────────────────────────────┤
│ 推断层                                                     │
│  ProjectResolver  cwd 向上找 .git / package.json / pom.xml │
│  TCProbe          BSD socket 非阻塞 connect + poll 超时    │
└──────────────────────────────────────────────────────────┘
```

依赖方向单向向下：UI 只吃 `Snapshot`，不直接调 shell。这条边界是整个设计的关键——CLI、菜单栏、Web 面板三种 UI 共享同一份数据，不重复写采集逻辑。

## 3. 数据模型

```swift
RawBinding        // 采集原始态：pid, command, uid, proto, address, port
   ↓ 补 cwd / ps 信息
ListeningPort     // 展示态：+ cwd, project, cpu, rss, elapsed, reachability
   ↓ 聚合
Snapshot          // 一帧：generatedAt, durationMs, ports[], issues[], system
```

`Issue` 独立于 `ListeningPort`，因为一条告警可能关联多个端口（端口冲突）。

## 4. 关键决策（含为什么）

| 决策点 | 方案 | 理由 |
|---|---|---|
| 端口枚举 | `lsof -nP -iTCP -sTCP:LISTEN -FpcPnu` | 一条命令同时拿到 pid/command/uid/监听地址，`-F` 机器可读格式比 `netstat` 好解析；`netstat -anv` 拿不到 PID |
| 项目归属 | `lsof -a -d cwd -p 1,2,3 -Fpn` 批量 + 路径向上探marker | 一次调用搞定全部 PID，避免 N 次 fork；向上 8 层防止遍历到 `/` |
| 可达性探测 | 自实现 non-blocking `connect()` + `poll()` | `curl`/`URLSession` 带 HTTP 语义，会把 MySQL/Redis 误判为"挂了"；TCP 握手才等价于"端口活着" |
| UI 基座 | AppKit `NSStatusItem`（不是 SwiftUI `MenuBarExtra`） | SwiftPM 直接 `swift run` 就能跑，不依赖 .app bundle 与 entitlements；后续加 SwiftUI 窗口用 `NSHostingController` 即可 |
| 工程形态 | Swift Package（可执行 target） | 单文件级编译反馈快；`scripts/bundle.sh` 再打成 .app，避免 M0 阶段被 Xcode 工程文件锁死 |
| 权限 | 默认无 root | 覆盖 90% 场景（开发者的 dev server 都是本用户进程）。root/system 端口标为「需 sudo」，不静默失败 |

### 权限边界（重要）
- 本用户进程：`lsof` 无需任何授权，包括 cwd。
- 其他用户 / root 进程：`lsof` 能列出监听端口但拿不到 cwd，需 `sudo`。
- 因此 UI 明确区分「我的服务」/「系统与其他用户」，后者只读展示，操作按钮禁用。
- 不需要「完全磁盘访问」，不需要屏幕录制权限 → 分发成本低。

## 5. 噪音治理（实测踩出来的问题）

Mac 上 `lsof` 一次能列出 20–30 个 LISTEN，但其中绝大多数与开发无关：
QQMusic、ControlCenter（AirPlay 5000/7000）、VS Code Helper、`rapportd`。全量展示 = 不可用。

所以引入 `PortSource` 分类（`ListeningPort.source` 计算属性）：

| 来源 | 判据 | 默认展示 |
|---|---|---|
| `project` | cwd 命中项目 marker | ✅ |
| `brew` | 可执行文件在 `/opt/homebrew`、`/usr/local/Cellar` | ✅ |
| `other` | 裸脚本，端口 < 49152 | ✅ |
| `app` | 路径含 `.app/Contents/`，或 `~/.*` 下的工具进程 | ❌ `--all` |
| `system` | `/System`、`/usr/libexec`、`/Library` 等 | ❌ `--all` |
| `ephemeral` | 无法归属且端口 ≥ 49152 | ❌ `--all` |

配套两个坑：
- `/opt/homebrew/.git` 存在 → 若不做保护，postgres 会被错误地归属为「项目 homebrew」。
  解法：`ProjectResolver.isSharedRoot` 阻止向上遍历到共享根（家目录、`/opt/homebrew`、`/usr/local`、`/tmp`…）。
- 端口冲突判定仍包含噪音端口——因为 **AirPlay 占着 5000 导致 dev server 起不来** 是真实高频事故，这类冲突必须报。

实测又踩到两个回归，已补单测锁死（`PortSourceRegressionTests`）：
1. `Xcode.app` 自带的 `python3` 实际路径是 `.../Python.framework/.../Python.app/Contents/MacOS/Python`，
   按「路径含 `.app/Contents/` 即 GUI 应用」会被隐藏。→ 分类顺序改为「项目归属 > .app」，
   并在 `ProjectResolver` 里显式禁止把 `~/Library`、`~/.<tool>`、`/Applications`、`/System` 当作项目根。
2. `ControlCenter` 这类 `CoreServices/*.app` 仍应归为系统噪音，靠同一顺序保证。

## 6. 体检规则（RuleEngine）

| 规则 | 判定 | 级别 | 说明 |
|---|---|---|---|
| `duplicatePort` | 同一 TCP 端口被 ≥2 个不同 PID 监听 | warning | 常见于旧进程没退干净，`SO_REUSEPORT` 下会出现 |
| `unreachable` | 端口在 LISTEN，但 TCP 握不上 | warning | 典型的"进程僵住/只监不服务" |
| `highCPU` | 端口持有进程 CPU > 80% | warning | 编译残留进程、死循环 dev server |
| `noProject` | cwd 找不到任何项目 marker | info | 裸起的脚本/临时服务 |

规则表保持纯函数：输入 `[ListeningPort]`，输出 `[Issue]`，可单测，UI 无关。

## 7. 刷新与性能（实测数据，M0 本机）

- 刷新周期 5s；菜单展开时暂停定时刷新（避免菜单中途重建），打开菜单时立即刷新一次。
- 实测单帧采集：**78–150ms**（27 个监听端口，M 系列 12 核）。
  - `lsof -F` ≈ 60–120ms
  - `ps` ≈ 10ms
  - cwd 批量 ≈ 30ms
  - TCP 探测并发 ≈ 20ms（只探非噪音端口）
- 优化路线：M2 用 `libproc`（`proc_pidinfo` + `PROC_PIDVNODEPATHINFO`）替掉 cwd 的 lsof 调用，可降到 < 5ms。
- `ProjectResolver` 内部对 cwd 做字典缓存，避免重复遍历。

## 8. 目录结构

```
devcheck/
├── Package.swift
├── docs/ARCHITECTURE.md          # 本文
├── scripts/bundle.sh             # 打包 .app（LSUIElement）
├── Sources/
│   ├── DevCheckCore/             # 纯逻辑，无 AppKit，可单测
│   │   ├── Models.swift
│   │   ├── Shell.swift
│   │   ├── PortCollector.swift
│   │   ├── ProcessInfoCollector.swift
│   │   ├── ProjectResolver.swift
│   │   ├── TCProbe.swift
│   │   ├── HealthChecker.swift
│   │   ├── RuleEngine.swift
│   │   ├── SystemProbe.swift
│   │   └── SnapshotBuilder.swift
│   └── DevCheckApp/
│       ├── main.swift            # 入口分发：app / ports / doctor
│       ├── CLI.swift
│       └── StatusBarController.swift
└── Tests/DevCheckCoreTests/
```

## 9. 里程碑

- **M0（本次已落地）**：采集 + 推断 + 规则 + 菜单栏 + CLI(`ports --json` / `doctor`)。
- **M1**：历史快照对比（"上周还开着、今天没了"）、端口备注/别名持久化、开机自启（`SMAppService`）、`libproc` 替换 cwd 采集。
- **M2**：本地 Web 面板（手机同局域网扫码看）、磁盘/缓存可回收项扫描、brew services / launchd / Docker 三源服务对齐（"声明了但没跑"和"跑着但没人声明"）。
- **M3**：特权 helper（`SMAppService.daemon`）拿 root 端口、告警通知（`UNUserNotificationCenter`）、`devcheck.json` 规则自定义。

## 10. 风险清单

| 风险 | 影响 | 应对 |
|---|---|---|
| `lsof` 被系统更新改输出格式 | 解析失败 | 单测覆盖 `-F` 输出；解析失败降级为「端口-only 视图」 |
| 端口数过多（Docker/浏览器会开一堆） | 菜单过长 | 默认只展示「我的服务」+ 端口 < 10000，其余折叠到子菜单 |
| 探测误报（IPv6-only 监听） | 显示"不可达"但实际活着 | `*` 地址同时探 `127.0.0.1` 与 `::1` |
| 结束进程手滑 | 丢数据 | 必须 `NSAlert` 二次确认 + 只允许本用户进程 |
| macOS 版本差异（14/15/26/27） | API 变动 | 只用 `lsof`/`ps`/BSD socket 这类十年不变的接口 |