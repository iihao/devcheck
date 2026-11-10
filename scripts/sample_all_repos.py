#!/usr/bin/env python3
"""给多个仓库采样 traffic，生成 shields.io endpoint 徽章。

为什么不是每个仓库各跑一份 workflow：
  traffic API 需要仓库 push 权限，Actions 自带的 GITHUB_TOKEN 会被 403
  （本地试过 write-all 也不行）。于是每加一个项目就要配一遍 PAT secret，
  迟早会漏。这里改成「一个仓库用一个 PAT 采样所有项目」：
    - metrics/repos.txt      要统计的仓库清单
    - metrics/repos/<name>.csv  每个仓库的逐日原始数据（GitHub 只留 14 天，所以必须自己存）
    - metrics/badges/<name>-visitors.json  独立访客徽章
    - metrics/badges/<name>-views.json     浏览量徽章
  README 里直接引 badges 下的文件即可。

用法：
  REPO=... 不需要，脚本自己读 metrics/repos.txt
  GH_TOKEN 需要带 repo 权限（traffic 端点要求 push 权限）
"""

from __future__ import annotations

import csv
import json
import sys
import time
from pathlib import Path

import track_metrics as tm

REPOS_FILE = Path("metrics/repos.txt")
CSV_DIR = Path("metrics/repos")
BADGE_DIR = Path("metrics/badges")


def read_repos() -> list[str]:
    if not REPOS_FILE.exists():
        raise SystemExit(f"缺少 {REPOS_FILE}（一行一个 owner/repo）")
    repos = []
    for line in REPOS_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        repos.append(line)
    return repos


def summarize(csv_path: Path) -> tuple[int, int, int]:
    """返回 (独立访客, 浏览量, 记录天数)。"""
    views = uniques = days = 0
    if not csv_path.exists():
        return 0, 0, 0
    with csv_path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            days += 1
            views += int(row.get("views") or 0)
            uniques += int(row.get("views_unique") or 0)
    return uniques, views, days


def sample_with_retry(repo: str, tries: int = 3):
    """网络抖动很常见（EOF / timeout），单个仓库失败不该让整轮采样挂掉。"""
    for attempt in range(1, tries + 1):
        try:
            return tm.sample_traffic(repo)
        except SystemExit as err:
            if attempt == tries:
                print(f"ERROR: {repo} 连续 {tries} 次失败：{err}", file=sys.stderr)
                return None
            time.sleep(3 * attempt)
    return None


def main() -> int:
    repos = read_repos()
    if not repos:
        raise SystemExit("metrics/repos.txt 里没有仓库")

    CSV_DIR.mkdir(parents=True, exist_ok=True)
    BADGE_DIR.mkdir(parents=True, exist_ok=True)

    rows = []
    for repo in repos:
        name = repo.split("/")[-1]
        traffic = sample_with_retry(repo)
        if traffic is None:
            print(f"WARN: {repo} 采样失败，本次跳过（已存的历史数据不受影响）", file=sys.stderr)
            uniques, views, days = summarize(CSV_DIR / f"{name}.csv")
            rows.append((repo, uniques, views, days))
            continue
        if not traffic:
            print(f"WARN: {repo} 没有 traffic 数据（token 权限不足？）", file=sys.stderr)

        csv_path = CSV_DIR / f"{name}.csv"
        total_days = tm.merge_csv(csv_path, tm.TRAFFIC_FIELDS, ["date"], traffic)
        uniques, views, days = summarize(csv_path)

        (BADGE_DIR / f"{name}-visitors.json").write_text(json.dumps(
            {"schemaVersion": 1, "label": "访客", "message": str(uniques),
             "color": "8c1f28"}, ensure_ascii=False) + "\n")
        (BADGE_DIR / f"{name}-views.json").write_text(json.dumps(
            {"schemaVersion": 1, "label": "浏览量", "message": str(views),
             "color": "a8823c"}, ensure_ascii=False) + "\n")

        rows.append((repo, uniques, views, total_days))
        print(f"{repo:32} 访客={uniques:5} 浏览={views:5} ({total_days} 天)")

    print(f"\n共 {len(rows)} 个仓库 → {BADGE_DIR}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
