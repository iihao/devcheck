# metrics · 访问量采样

GitHub 的 traffic API **只保留最近 14 天**，不每天抓就等于数据永久消失；而
`GITHUB_TOKEN` 读不到这个端点（需要仓库 push 权限，实测 `write-all` 也是 403），
所以这些数据统一在 devcheck 里用一个 PAT（`METRICS_TOKEN`）采样，各项目的
README 直接引用本目录生成的徽章文件。

## 结构

```
metrics/
├── repos.txt                 # 要统计的仓库清单，一行一个 owner/repo
├── repos/<name>.csv          # 每个仓库逐日 views / uniques / clones
├── badges/<name>-visitors.json   # 独立访客徽章（shields endpoint 格式）
├── badges/<name>-views.json      # 浏览量徽章
├── traffic.csv               # devcheck 自身的原始数据（旧的单仓库采样）
└── repo.csv / stars.csv / referrers.csv
```

## 口径（重要）

| 指标 | 含义 | 说明 |
|------|------|------|
| 访客（uniques） | GitHub 官方「按日去重」的独立访客 | 你自己刷新再多次，当天也只算 1，不会把数字刷高 |
| 浏览量（views） | 原始 page view | 含重复访问 |

这也是为什么用官方 traffic 而不是 hits.sh / visitorbadge 这类第三方计数器：
第三方是「图片被加载一次算一次」，自己多点几次就虚高，而且 GitHub 的图片缓存
让数字既偏高又滞后。

**已知局限**：官方只给 14 天窗口，所以「累计」是**已记录天数的每日去重值之和**，
跨天的回访会被重复计数。真实 UV 一定 ≤ 这个数。

## 想看数字

```bash
python3 scripts/sample_all_repos.py --report            # 只读，不联网不写文件
GH_TOKEN=$(gh auth token) python3 scripts/sample_all_repos.py   # 立刻抓一次并更新徽章
gh api repos/iihao/devcheck/traffic/popular/referrers   # 流量来源
```

## 加一个新仓库

1. 在 `metrics/repos.txt` 追加一行 `owner/repo`
2. `GH_TOKEN=$(gh auth token) python3 scripts/sample_all_repos.py` 本地先跑一次回填
3. README 里加提示词：

```html
<a href="https://github.com/OWNER/REPO/graphs/traffic"><img alt="visitors"
  src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fiihao%2Fdevcheck%2Fmain%2Fmetrics%2Fbadges%2FREPO-visitors.json"></a>
```

## 其它规则

- `.github/workflows/metrics.yml` 每天 UTC 01:17 跑一次，有变化才提交
- 徽章走 raw.githubusercontent（约 5 分钟缓存）+ shields 自己的缓存，**不是实时**
- 想换成本地统计 / 自建计数服务时，只要保持 `badges/*.json` 的
  `{"schemaVersion":1,"label":...,"message":...,"color":...}` 格式，README 不用改
