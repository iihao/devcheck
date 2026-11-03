# 开源发布作战手册（以 star 最大化为目标）

> 先说结论：**star ≈ 痛点强度 × 可分享性 ÷ 上手摩擦**，再乘以一次性的曝光量。
> 这个项目痛点是"中等偏高频"（EADDRINUSE、端口被 AirPlay 占、旧进程没退），
> 可分享性强（一句话能讲完、有画面感），摩擦可以做到很低（brew 一条命令）。
> 所以它的**现实区间是 300–2,000 star**；要突破 5k，必须靠一个"人传人"的故事 + 二次传播，
> 而不是靠功能更多。

## 1. 发布前必须补的（按 ROI 排序）

| # | 事项 | 为什么 | 状态 |
|---|---|---|---|
| 1 | **CLI / 菜单英文输出（i18n）** | 国际用户看不懂中文输出，直接劝退。跟随 `LANG`，中文用户仍然看中文 | ✅ 已完成（`DEVCHECK_LANG` 可强制） |
| 2 | **真实 GIF（10 秒内）** | README 有 3 秒看懂的画面，star 转化率提升最明显 | ✅ 已完成 `docs/demo-cli.gif`（7s，中英各一） |
| 3 | **一条命令安装 + Gatekeeper 不拦** | `curl \| bash` 或 cask；未公证的包会让 80% 的人卡在"已损坏" | ⚠️ cask + install.sh 已可用（带 xattr 提示），仍缺 Developer ID 公证 |
| 4 | 仓库设置（description / topics / social preview） | 决定搜索和 Twitter 卡片的观感 | ⚠️ description + 10 topics 已设，social preview 仍待上传 |
| 5 | 首个 Release + CHANGELOG | 有版本号才像"能用"，也才写得进 cask | ✅ v0.1.0 / v0.1.1 已发布（通用二进制） |

## 2. 命名

`devcheck` 的问题是"不可搜索、不具体"，且可能与既有产品重名。名字里带 **port** 更容易被搜到、被记住：

| 候选 | 优点 | 风险 |
|---|---|---|
| `portmap` | 直白、可搜索 | 已有同名小项目 |
| `ports` | 极短 | 与付费 App "Ports" 冲突 |
| `whoport` | 有画面感、易读 | 稍口语 |
| `portress` / `portly` | 有品牌感 | 需要解释 |

建议：**仓库名保留 `devcheck`，但 GitHub description 里必须出现 "port map"、"lsof" 关键词**；如果要在 HN 上传播，标题用 `devcheck` 也够，因为标题里会写清 "port map"。

## 3. 仓库设置清单

- **Description**（160 字符内，含关键词）：
  > Menu bar port map for macOS — see who holds :3000, which project it belongs to, and why your server won't start. No sudo, no telemetry.
- **Topics**：`macos` `swift` `menu-bar` `ports` `port-scanner` `developer-tools` `devtools` `lsof` `homebrew` `macos-app` `swiftui` `productivity`
- **Social preview**：1280×640，用 `docs/demo.svg` 渲染成 PNG，左上角一句 "Who's holding :3000?"
- **About → Website**：指向 README 或 GitHub Pages
- **Discussions** 打开；**Issues** 用模板；打 3 个 `good first issue` 标签
- 首个 Release：`v0.1.0` + 通用二进制 + checksums + 安装说明（cask / zip / 右键打开）

## 4. README 首屏规则（决定 80% 的 star）

从上到下只允许出现：

1. 项目名
2. **一句话**：给谁解决什么问题（不是特性列表）
3. 安装命令（一行）
4. GIF（≤10 秒，展示"卡住的端口 → 一条命令 → 解释 + 建议"）
5. 徽章行

不要在第一屏放：架构图、roadmap、致谢、contributing。这些往下放。

## 5. 渠道与文案（同一周内发完，形成叠加曝光）

### Hacker News — Show HN（最重要的单点）

标题（选一个，A 更具体）：
- `Show HN: DevCheck – a macOS menu bar port map that tells you who owns :3000`
- `Show HN: I got tired of "port 5000 is taken", so I built a port map for macOS`

正文（短，讲事故，不讲功能）：

```
I kept hitting two failures on my Mac: `npm run dev` dying with EADDRINUSE on 3000,
and servers on 5000 silently failing because macOS AirPlay Receiver holds 5000.

`lsof -i :3000` tells you a PID, but not which project it belongs to, and it happily
lists 25 GUI apps and system daemons that have nothing to do with your work.

DevCheck is a menu bar app + CLI. It maps every listener to its owning project by
walking up from the process cwd to package.json / pom.xml / go.mod / .git, hides
app/system noise by default, probes listeners with a real TCP handshake (so a
listener that never answers shows up as fake-alive), and explains known ones:

  $ devcheck why 5000
  5000 is macOS AirPlay Receiver (ControlCenter).
  Turn it off in System Settings → General → AirDrop & Handoff, or use 5001.

No sudo, no privileged helper, no telemetry, no third-party deps — it's ~2k lines
of Swift shelling out to lsof/ps and doing its own socket checks.

Install: brew install --cask ...
Source: https://github.com/...

Happy to hear which ports it misclassifies on your machine — that classifier was
the hardest part (Homebrew's own .git, Xcode's python3 living inside Python.app).
```

> HN 的关键：**先讲事故，再讲实现上的取舍，最后邀请反馈**。不要写"我做了个很酷的工具"。

### Reddit

- `r/macapps`：标题 `A free menu bar port map for devs: see which project is holding :3000`，首图用 GIF，正文 3 段以内。
- `r/webdev` / `r/node`：偏"解决 EADDRINUSE"角度，标题带 `:3000`。
- `r/swift`：偏"零依赖 + 不用 sudo 的实现"角度，讲 `lsof -F` 解析与 `connect`+`poll`。

### X / Twitter

一条主推 + 一张 GIF：

```
你的 Mac 上现在有 27 个进程开着端口，你只知道其中 3 个。

devcheck why 5000  →
  5000 是 AirPlay 接收器，去系统设置关掉，或者换 5001

菜单栏工具，不需要 sudo，不联网，MIT。
开源了 👉 github.com/...
```

### 中文社区

- **V2EX**（`/go/create` 或 `/go/programmer`）：标题带痛点，如「写了个 Mac 菜单栏工具：`devcheck why 3000` 告诉我端口被谁占了」
- **掘金 / 少数派**：长文更吃香，标题用「我把 Mac 上 27 个偷偷占端口的进程摊平了」，正文放架构取舍（IDEA：为什么不用 HTTP 探测、为什么不用 netstat、为什么不做 root）
- **小红书**：只发截图 + 一句话，配「Mac 效率」标签

### 其他长期线索

- `awesome-mac`、`awesome-macos`、`awesome-devtools` 类 awesome 列表提 PR（长期稳定的 star 来源）
- Homebrew 官方 cask（需公证 + 一定知名度后再提）
- Product Hunt（可选，对开发者工具收益一般）

## 6. 节奏

| 时间 | 动作 |
|---|---|
| T-7 天 | 补齐 i18n、录 GIF、发布 v0.1.0、建 3 个 good first issue |
| T-3 天 | 在 X / 小红书发一条"预告 + 一张图"，收集第一批反馈 |
| T-0（周二~周四，美西 8–10 点） | Show HN + Reddit 同日发；中文社区同步 |
| T-0 当晚 | **回复每一条评论**（HN 前 2 小时的回复决定排序） |
| T+3 天 | 把高频反馈修掉，发 v0.1.1，在 HN 帖里补一条 "updated: fixed X" |
| T+7 天 | 写一篇「端口地图背后的 7 个坑」技术长文，投掘金/少数派/HN 二次曝光 |

## 7. 转化细节（很多人忽略）

- **Issue 24 小时内必有回应**，哪怕是 "reproduced, thanks"。活跃度直接影响路人 star 意愿。
- Release notes 写人话 + 截图，别只写 commit 列表。
- README 末尾的 star 请求要克制（现在这句"如果省了你十分钟"就够了），过度求 star 会掉好感。
- 分类器误判是这个项目最容易招黑的地方：**开一个 "wrong classification" 的 issue 模板**，让用户一键上报，避免他们在评论区吐槽。

## 8. 诚实的预期

- 只发一次 HN：约 50–300 star。
- HN 首页 + 中文社区同步 + 二次技术文：600–1,500 star。
- 要达到 5k+：需要正好命中一波"Mac 端口/AirPlay 5000"的公共讨论，或者被某个大 V 转发。功能多少不是决定因素，**故事和画面才是**。
- 反例警示：这类"壳层工具"在 HN 上容易被评论 "why not just use lsof" —— 所以 README 里的对比表、以及"TCP 握手 vs HTTP 探测"这种实现取舍必须写好，这是唯一的防御。

## 9. 追踪

- Star 增长曲线（star-history.com 挂进 README 底部）
- Release 下载量 vs star 比值（< 10% 说明 star 是"友情 star"，产品没被真用）
- Issue 里 `wrong classification` 的数量 → 直接反映分类器质量