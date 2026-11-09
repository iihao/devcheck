#!/usr/bin/env python3
"""把 metrics/*.csv 拼成一张「浏览 × star × 来源」的对齐表。

回答的问题：某一天涨的 star，最可能来自哪个渠道？

GitHub 不提供 star 的来源，只有：
  - star 的精确时间戳（metrics/stars.csv）
  - 最近 14 天的浏览/克隆（metrics/traffic.csv）
  - 最近 14 天的来源域名（metrics/referrers.csv，只有快照日期）

所以归因方法只能是「时间对齐」：star 集中在哪几个小时，就对到发布动作上；
再看过期前的 referrers 里有哪些站外域名。

用法：python3 scripts/star_report.py
"""
from __future__ import annotations

import csv
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path

METRICS = Path("metrics")


def read(name: str) -> list[dict]:
    path = METRICS / name
    if not path.exists():
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def main() -> None:
    traffic = {r["date"]: r for r in read("traffic.csv")}
    stars = read("stars.csv")
    referrers = read("referrers.csv")

    by_day: dict[str, list[dict]] = defaultdict(list)
    for row in stars:
        if row.get("starred_at"):
            by_day[row["starred_at"][:10]].append(row)

    days = sorted(set(traffic) | set(by_day))
    if not days:
        print("还没有数据，先跑一次 scripts/track_metrics.py")
        return

    print(f"{'日期':<12}{'浏览':>6}{'独立':>6}{'克隆':>6}{'新star':>8}   star 用户")
    print("-" * 74)
    for day in days:
        t = traffic.get(day, {})
        rows = sorted(by_day.get(day, []), key=lambda r: r["starred_at"])
        names = ", ".join(("(我)" if r["login"] == "iihao" else r["login"]) for r in rows)
        print(f"{day:<12}{t.get('views', '-'):>6}{t.get('views_unique', '-'):>6}"
              f"{t.get('clones', '-'):>6}{len(rows):>8}   {names}")

    real = [r for r in stars if r.get("login") != "iihao"]
    print(f"\n总 star {len(stars)}，其中自己 {len(stars) - len(real)}，外部 {len(real)}")

    # 按 6 小时间隔切分「star 波次」，每波大概率对应一次曝光
    stamps = sorted(datetime.fromisoformat(r["starred_at"].replace("Z", "+00:00"))
                    for r in real if r.get("starred_at"))
    bursts: list[list[datetime]] = []
    for ts in stamps:
        if bursts and ts - bursts[-1][-1] <= timedelta(hours=6):
            bursts[-1].append(ts)
        else:
            bursts.append([ts])
    print("\nstar 波次（间隔 > 6 小时算新的一次曝光）")
    for burst in bursts:
        start, end = burst[0], burst[-1]
        zh = start.astimezone().strftime("%m-%d %H:%M")
        print(f"  {zh}（北京时间）  {len(burst)} 个，跨度 {(end - start).total_seconds() / 3600:.1f} 小时")

    if referrers:
        latest = max(r["date"] for r in referrers)
        rows = [r for r in referrers if r["date"] == latest]
        print(f"\n最近一次来源快照（{latest}，仅覆盖此前 14 天）")
        for r in sorted(rows, key=lambda x: -int(x["uniques"])):
            print(f"  {r['referrer']:<16} {r['count']:>4} 次 / {r['uniques']} 人")

    # 转化率：只在 traffic 覆盖的窗口内算，避免把更早的浏览算进来
    window_days = set(traffic)
    win_stars = [r for r in real if r.get("starred_at", "")[:10] in window_days]
    views = sum(int(traffic[d].get("views", 0) or 0) for d in window_days)
    uniques = sum(int(traffic[d].get("views_unique", 0) or 0) for d in window_days)
    if uniques:
        print(f"\n近 {len(window_days)} 天：浏览 {views}（独立 {uniques}），"
              f"外部 star {len(win_stars)}，star/独立访客 ≈ {len(win_stars) / uniques:.0%}")

    if stars and traffic:
        first = min(traffic)
        print(f"\n注意：traffic 只保留最近 14 天（当前最早 {first}），更早的浏览已无法追溯。")


if __name__ == "__main__":
    main()
