#!/usr/bin/env python3
"""汇总整个账号的 star / 访客，生成个人主页（iihao/iihao）用的 shields 徽章。

为什么算在这里：
  个人主页仓库自己带不了 PAT，而 traffic API 需要仓库 push 权限。
  devcheck 的 metrics workflow 已经有 METRICS_TOKEN，就顺手把账号级数字也算出来，
  主页 README 只引用下面这些文件。

产出：
  metrics/profile.csv                  账号级逐日快照（stars / forks / repos / followers）
  metrics/badges/iihao-stars.json       所有自有仓库的 star 之和
  metrics/badges/iihao-forks.json
  metrics/badges/iihao-repos.json       公开仓库数
  metrics/badges/iihao-followers.json
  metrics/badges/iihao-visitors.json    已记录天数里的独立访客之和
  metrics/badges/iihao-views.json       同上，浏览量

口径：
  - star / fork / 仓库数来自 GraphQL，只算自己名下、非 fork 的仓库
  - 访客 / 浏览是 metrics/repos/*.csv 的累加。GitHub 只给 14 天窗口，
    所以这是「已记录天数之和」：跨天的回访会重复计数，真实 UV 一定更小。

用法：
  GH_TOKEN=$(gh auth token) python3 scripts/profile_stats.py
  python3 scripts/profile_stats.py --report    # 只读，不联网不写文件
"""

from __future__ import annotations

import csv
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import track_metrics as tm

OWNER = "iihao"
CSV_DIR = Path("metrics/repos")
BADGE_DIR = Path("metrics/badges")
PROFILE_CSV = Path("metrics/profile.csv")
PROFILE_FIELDS = ["date", "stars", "forks", "repos", "followers"]

GQL = """
{ user(login: "%s") {
    followers { totalCount }
    repositories(first: 100, ownerAffiliations: OWNER, isFork: false) {
      totalCount
      nodes { stargazerCount forkCount }
    } } }
""" % OWNER

# 和 metrics/README.md 里其它徽章保持一套配色（朱红 / 赭金 / 墨灰）
COLORS = {
    "stars": "8c1f28",
    "forks": "a8823c",
    "repos": "6b7280",
    "followers": "5b6b73",
    "visitors": "8c1f28",
    "views": "a8823c",
}


def badge(key: str, label: str, message: int | str) -> None:
    BADGE_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "schemaVersion": 1,
        "label": label,
        "message": str(message),
        "color": COLORS[key],
    }
    (BADGE_DIR / f"{OWNER}-{key}.json").write_text(
        json.dumps(payload, ensure_ascii=False) + "\n"
    )


def account_totals() -> dict[str, int]:
    # tm.gh_api 只处理 REST 路径，GraphQL 这里直接调 gh
    result = subprocess.run(
        ["gh", "api", "graphql", "-f", f"query={GQL}"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise SystemExit(f"GraphQL 失败：{result.stderr.strip()}")
    user = json.loads(result.stdout)["data"]["user"]
    nodes = user["repositories"]["nodes"]
    return {
        "stars": sum(int(n["stargazerCount"]) for n in nodes),
        "forks": sum(int(n["forkCount"]) for n in nodes),
        "repos": int(user["repositories"]["totalCount"]),
        "followers": int(user["followers"]["totalCount"]),
    }


def traffic_totals() -> tuple[int, int, int]:
    """返回 (独立访客, 浏览量, 已记录仓库数)。"""
    uniques = views = repos = 0
    for path in sorted(CSV_DIR.glob("*.csv")):
        repos += 1
        with path.open(newline="") as handle:
            for row in csv.DictReader(handle):
                views += int(row.get("views") or 0)
                uniques += int(row.get("views_unique") or 0)
    return uniques, views, repos


def read_profile_csv() -> dict[str, dict]:
    if not PROFILE_CSV.exists():
        return {}
    with PROFILE_CSV.open(newline="") as handle:
        return {row["date"]: row for row in csv.DictReader(handle)}


def report() -> int:
    """只读：不联网、不写文件。"""
    hist = read_profile_csv()
    if hist:
        last = hist[max(hist)]
        print(f"{'账号快照':12} {last['date']}  stars={last['stars']} forks={last['forks']} "
              f"repos={last['repos']} followers={last['followers']}（{len(hist)} 天记录）")
    else:
        print("账号快照：还没有 metrics/profile.csv")
    uniques, views, repos = traffic_totals()
    print(f"{'仓库流量':12} 访客={uniques} 浏览={views}（{repos} 个仓库的已记录数据）")
    return 0


def main() -> int:
    if "--report" in sys.argv[1:]:
        return report()

    totals = account_totals()
    uniques, views, repos_tracked = traffic_totals()

    row = {
        "date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        **{key: totals[key] for key in ("stars", "forks", "repos", "followers")},
    }
    days = tm.merge_csv(PROFILE_CSV, PROFILE_FIELDS, ["date"], [row])

    badge("stars", "总 star", totals["stars"])
    badge("forks", "fork", totals["forks"])
    badge("repos", "仓库", totals["repos"])
    badge("followers", "followers", totals["followers"])
    badge("visitors", "访客", uniques)
    badge("views", "浏览量", views)

    print(f"stars={totals['stars']} forks={totals['forks']} repos={totals['repos']} "
          f"followers={totals['followers']} → {PROFILE_CSV}（{days} 天记录）")
    print(f"访客={uniques} 浏览={views}（{repos_tracked} 个仓库的已记录数据）→ {BADGE_DIR}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
