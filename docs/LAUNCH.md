# 发布作战手册（可直接执行）

> 现状：仓库 `iihao/devcheck`，v0.1.1 已发布，通用二进制 + cask + install.sh 可用，中英 README + GIF + social preview 就绪。
> **唯一的阻塞是：还没有任何一次对外曝光。**

## 0. 上线前最后 2 件事

| # | 事项 | 谁做 | 说明 |
|---|---|---|---|
| 1 | 上传 social preview | **你**（网页操作，30 秒） | Settings → Social preview → 上传 `docs/social-preview.png`。GitHub 没有 API，只能手动 |
| 2 | 发第一帖 | **你**（需要账号） | 文案在下面，逐条复制即可 |

---

## 1. 发布顺序（不要一次全发）

| 时间 | 动作 | 目的 |
|---|---|---|
| **D0 晚上** | 中文社区：V2EX + 小红书 | 低成本试水，收集"装不上/误判"类反馈 |
| **D1–D3** | 按反馈修 bug，发 v0.1.2 | 保证 HN 上去时是"已经有人用过"的状态 |
| **D4（周二/周三 美西 7–9am）** | **Show HN** | 单点最大曝光 |
| **D4 当天** | Reddit r/macapps + X | 蹭同一天的注意力 |
| **D7** | 技术长文（掘金/少数派/dev.to） | 二次传播，长期搜索流量 |

> 美西 7–9am = 北京 22:00–24:00。

---

## 2. Show HN（最重要，D4 发）

**标题**（三选一，A 最具体）：

```
A: Show HN: DevCheck – a macOS port map that tells you who owns :3000
B: Show HN: I got tired of "port 5000 is taken", so I built a port map for macOS
C: Show HN: devcheck why 5000 – a menu bar port map for macOS
```

**正文**：

```
I kept hitting two things on my Mac: `npm run dev` dying with EADDRINUSE, and
servers on 5000 silently failing because macOS AirPlay Receiver holds 5000.

`lsof -i :3000` gives you a PID but not the project it belongs to, and it happily
lists 25 GUI apps and system daemons that have nothing to do with your work.

DevCheck maps every listener to its owning project by walking up from the process
cwd to package.json / pom.xml / go.mod / .git, hides app/system noise by default,
probes listeners with a real TCP handshake (so a listener that never answers shows
up as fake-alive), and explains the known ones:

  $ devcheck why 5000
  Port 5000 is macOS AirPlay Receiver — turn it off in System Settings, or use 5001.

Zero dependencies, zero privileges (no sudo, no root helper), no network I/O.
~2k lines of Swift shelling out to lsof/ps and doing its own socket checks.

  brew install --cask iihao/tap/devcheck     # needs one xattr, see README

https://github.com/iihao/devcheck

Happy to hear which ports it misclassifies on your machine — the classifier was
the hard part (Homebrew's own .git, Xcode's python3 living inside Python.app).
```

**HN 注意**：发完前 2 小时守在评论区，回复决定排名。

---

## 3. V2EX（D0 晚上，`/go/programmer`）

**标题**：

```
写了个 Mac 菜单栏工具：devcheck why 3000 告诉我端口到底被谁占了
```

**正文**：

```
起因是我这台 Mac 上 `npm run dev` 一直起不来，报 EADDRINUSE（3000 被占）。
`lsof -i :3000` 能给个 PID，但不知道是哪个项目的；而且它会把二十多个桌面应用
和系统守护进程一起列出来，噪音太大。

后来发现更坑的：5000 端口被 macOS 自己的「隔空播放接收器」占着（ControlCenter），
服务起来后静默失败，排查了半天。

所以写了个小工具，只做三件事：
1. 端口 → 进程 → 所属项目（从 cwd 往上找 package.json / pom.xml / go.mod / .git）
2. 默认隐藏 GUI 应用/系统端口，只留跟我干活相关的
3. `devcheck why <端口>` 用人话解释：这是 AirPlay，去系统设置关掉，或者换 5001

还有几个体检规则：同一端口被多个进程监听、端口在监听但 TCP 握不上手（假活）、
单进程 CPU 飙高。规则是纯函数，可以单测。

技术上刻意「零依赖零特权」：不装任何第三方库，全部走系统自带 lsof/ps 和自己写的
非阻塞 connect + poll（不用 HTTP 探测，否则 MySQL/Redis 会被误判成挂了）。
所以不需要 sudo，也不需要「完全磁盘访问」。

菜单栏常驻，能直接开浏览器 / 复制地址 / Finder 定位 / 结束进程（二次确认）。

GitHub: https://github.com/iihao/devcheck
brew install --cask iihao/tap/devcheck

还没公证（差个 Apple Developer 账号），首次启动要跑一次：
xattr -dr com.apple.quarantine /Applications/DevCheck.app

分类器是最容易出错的，如果它把你这台机器上的某个端口认错了，欢迎直接开 issue。
```

---

## 4. Reddit `r/macapps`（D4）

**标题**：

```
Free menu bar port map for devs: see which project is holding :3000 (no sudo, no telemetry)
```

**正文**：

```
Tired of `lsof -i :3000` telling me a PID and nothing else, so I built this.

It's a menu bar app + CLI that maps every listening port to the project that owns
it (walks up from the process cwd to package.json / pom.xml / go.mod / .git),
hides the 20+ GUI apps and system daemons that clutter `lsof`, and explains the
well-known ones — e.g. `devcheck why 5000` tells you it's macOS AirPlay Receiver
and how to turn it off.

No sudo, no privileged helper, no network calls, zero third-party dependencies.
MIT, universal binary, macOS 14+.

https://github.com/iihao/devcheck
```

---

## 5. X / Twitter（D4，配 `docs/demo-cli.gif`）

**主帖**：

```
你的 Mac 上现在有 27 个进程开着端口，你只知道其中 3 个。

$ devcheck why 5000
  5000 是 macOS 的 AirPlay 接收器 —— 去系统设置关掉，或者换 5001

菜单栏工具，不需要 sudo，不联网，MIT，零依赖。
开源了 👉 github.com/iihao/devcheck
```

**英文版（同一条线程置顶）**：

```
27 processes on your Mac are holding ports. You know about 3 of them.

$ devcheck why 5000
→ that's macOS AirPlay Receiver. Turn it off, or use 5001.

Menu bar port map. No sudo, no telemetry, zero deps, MIT.
github.com/iihao/devcheck
```

---

## 6. 评论区高频质疑的标准回答

| 质疑 | 回答（照这个方向，别硬怼） |
|---|---|
| "why not just use `lsof`?" | lsof 给 PID，不给项目归属；而且它会把 GUI 应用和系统守护进程一起列出来。README 里有对比表。我每天都在用 lsof，这工具是它的补充，不是替代。 |
| "yet another port app" | 现有的（Sloth / Ports / kill-port）解决"谁占了"，没解决"这是哪个项目"和"这是什么服务"。`why 5000` 那个是差异点。 |
| "why not `kill-port`?" | kill-port 只杀进程，不告诉你杀的是什么。这个先告诉你这是 AirPlay，再给你"换端口"的建议。 |
| "needs sudo?" | 不需要。默认只覆盖当前用户进程；root 端口只读展示。 |
| "why macOS 14+?" | 用了 `NSStatusItem` + 新 API；再往前兼容需要额外测试，暂时不做。 |
| "is it sending telemetry?" | 不联网。唯一的 socket 是回环 TCP 握手，探自己机器上的端口。源码可查。 |

---

## 7. 发布后 24 小时检查清单

- [ ] 每一条评论 30 分钟内回复（HN 排序机制）
- [ ] issue 当天回应，哪怕是 "reproduced, thanks"
- [ ] 有人报分类错误 → 当天修，发 v0.1.2，在原帖补一条 "updated: fixed X"
- [ ] 看 `gh api repos/iihao/devcheck/traffic/views` 确认流量来源
- [ ] 记录下载量 / star 比值（< 10% 说明 star 是友情 star）

---

## 8. 诚实的预期

- 单发 V2EX：**20–80 star**
- HN 上首页：**+150–600**
- 加上 Reddit + X 同日：**+100–300**
- 被 awesome list 收录：长期 **1–3/天**

**5k+ 需要运气**：要么正好命中"AirPlay 占 5000"的公共讨论，要么被大 V 转发。功能多少不是决定因素。
---

## 9. 分发渠道状态（2026-11-03 提交）

| 渠道 | 规模 | 形式 | 状态 | 备注 |
|---|---|---|---|---|
| [jaywcjlove/awesome-mac](https://github.com/jaywcjlove/awesome-mac/issues/4184) | 112k | issue | 🟡 待审 | 该列表用 issue 收录，不用 PR |
| [HelloGitHub](https://github.com/521xueweihan/HelloGitHub/issues/4227) | 186k | issue | 🟡 待审 | 月刊，可能下期收录 |
| [阮一峰周刊](https://github.com/ruanyf/weekly/issues/13035) | 107k | issue | 🟡 待审 | 每周五发刊，作者挑选 |
| [open-source-mac-os-apps](https://github.com/serhii-londar/open-source-mac-os-apps/pull/1947) | 51k | PR | 🟡 待审 | 改了 `applications.json`，CI 会跑链接检查 |
| [iCHAIT/awesome-macOS](https://github.com/iCHAIT/awesome-macOS/issues/1341) | 19k | issue | 🟡 待审 | 仓库设了 `collaborators_only`，外人不允许 PR |
| [awesome-cli-apps](https://github.com/agarrharr/awesome-cli-apps) | 20k | PR | ⏳ 2027-02 再提 | 硬门槛：**>20 star 且项目满 3 个月** |
| [chinese-independent-developer](https://github.com/1c7/chinese-independent-developer) | 62k | PR | ❌ 不适合 | 规则明确写「不能是开发者工具」 |
| [awesome-macos-command-line](https://github.com/herrbischoff/awesome-macos-command-line) | 31k | — | ❌ 不收 | 仓库已于 2026-03 归档 |

**跟进节奏**：列表审核通常 1–4 周，被合并/收录前不要重复提交。awesome-cli-apps 到 2027-02 且 star > 20 后再提一次。
