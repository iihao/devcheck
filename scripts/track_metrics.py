#!/usr/bin/env python3
"""采样仓库指标，追加到 metrics/*.csv（幂等：同一天重复跑不会重复写）。

为什么需要这个脚本：
  GitHub 的 traffic API 只保留最近 14 天，且 referrers 只给域名级数据，
  没有历史累积。不每天采样，数据就永久消失。

用法：
  python3 scripts/track_metrics.py            # 自动读 git remote 猜仓库
  REPO=owner/repo python3 scripts/track_metrics.py

需要：gh CLI 已登录（或 GH_TOKEN 环境变量带 repo 权限）。
"""

from __future__ import annotations

import csv
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

METRICS_DIR = Path("metrics")

TRAFFIC_FIELDS = ["date", "views", "views_unique", "clones", "clones_unique"]
REPO_FIELDS = ["date", "stars", "forks", "watchers", "downloads_zip", "downloads_total"]
REFERRER_FIELDS = ["date", "referrer", "count", "uniques"]


def gh_api(path: str, allow_missing: bool = False):
    """调用 gh api。

    allow_missing=True 时，404（该端点还没有数据，例如 referrers）返回 None。
    403 永远打印警告并返回 None —— 静默吞掉权限问题会导致采样永远为 0，
    而 traffic 只有 14 天窗口，发现时数据已经丢了。
    """
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if result.returncode == 0:
        return json.loads(result.stdout)

    message = result.stderr.strip()
    if "HTTP 403" in message:
        print(f"WARN: 403 on {path} — token 缺少该仓库的 push 权限，数据不可用",
              file=sys.stderr)
        return None
    if allow_missing and ("HTTP 404" in message or "Not Found" in message):
        return None
    raise SystemExit(f"gh api {path} failed: {message}")


def detect_repo() -> str:
    if os.environ.get("REPO"):
        return os.environ["REPO"]
    try:
        out = subprocess.run(
            ["gh", "repo", "view", "--json", "nameWithOwner"],
            capture_output=True, text=True, check=True,
        ).stdout
        return json.loads(out)["nameWithOwner"]
    except subprocess.CalledProcessError:
        raise SystemExit("无法确定仓库，请设置 REPO=owner/repo")


def merge_csv(path: Path, fieldnames: list[str], keys: list[str], rows: list[dict]) -> int:
    """按 keys 去重合并。返回写入的总行数。"""
    existing: dict[tuple, dict] = {}
    if path.exists():
        with path.open(newline="") as handle:
            for row in csv.DictReader(handle):
                existing[tuple(row.get(k, "") for k in keys)] = row

    for row in rows:
        existing[tuple(str(row[k]) for k in keys)] = {k: str(row.get(k, "")) for k in fieldnames}

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for key in sorted(existing):
            writer.writerow(existing[key])
    return len(existing)


def sample_traffic(repo: str) -> list[dict]:
    views = gh_api(f"repos/{repo}/traffic/views", allow_missing=True) or {"views": []}
    clones = gh_api(f"repos/{repo}/traffic/clones", allow_missing=True) or {"clones": []}

    by_date: dict[str, dict] = {}
    for entry in views.get("views", []):
        day = entry["timestamp"][:10]
        by_date.setdefault(day, {})["views"] = entry["count"]
        by_date[day]["views_unique"] = entry["uniques"]
    for entry in clones.get("clones", []):
        day = entry["timestamp"][:10]
        by_date.setdefault(day, {})["clones"] = entry["count"]
        by_date[day]["clones_unique"] = entry["uniques"]

    return [
        {
            "date": day,
            "views": values.get("views", 0),
            "views_unique": values.get("views_unique", 0),
            "clones": values.get("clones", 0),
            "clones_unique": values.get("clones_unique", 0),
        }
        for day, values in by_date.items()
    ]


def sample_repo(repo: str) -> dict:
    info = gh_api(f"repos/{repo}")
    releases = gh_api(f"repos/{repo}/releases", allow_missing=True) or []

    zip_downloads = 0
    total_downloads = 0
    for release in releases:
        for asset in release.get("assets", []):
            count = asset.get("download_count", 0)
            total_downloads += count
            if asset.get("name", "").endswith(".zip"):
                zip_downloads += count

    return {
        "date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "stars": info.get("stargazers_count", 0),
        "forks": info.get("forks_count", 0),
        "watchers": info.get("subscribers_count", 0),
        "downloads_zip": zip_downloads,
        "downloads_total": total_downloads,
    }


def sample_referrers(repo: str) -> list[dict]:
    # 没有任何外部来源时 GitHub 返回 404，不是错误
    data = gh_api(f"repos/{repo}/traffic/referrers", allow_missing=True) or []
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    return [
        {
            "date": today,
            "referrer": entry["referrer"],
            "count": entry["count"],
            "uniques": entry["uniques"],
        }
        for entry in data
    ]


def main() -> int:
    repo = detect_repo()
    traffic = sample_traffic(repo)
    repo_row = sample_repo(repo)
    referrers = sample_referrers(repo)

    traffic_file = METRICS_DIR / "traffic.csv"
    repo_file = METRICS_DIR / "repo.csv"
    referrer_file = METRICS_DIR / "referrers.csv"

    days = merge_csv(traffic_file, TRAFFIC_FIELDS, ["date"], traffic)
    merge_csv(repo_file, REPO_FIELDS, ["date"], [repo_row])
    refs = merge_csv(referrer_file, REFERRER_FIELDS, ["date", "referrer"], referrers)

    print(f"repo: {repo}")
    print(f"traffic: {days} 天已记录 → {traffic_file}")
    print(f"stars={repo_row['stars']} forks={repo_row['forks']} "
          f"downloads(zip)={repo_row['downloads_zip']} → {repo_file}")
    print(f"referrers: {refs} 行 → {referrer_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())