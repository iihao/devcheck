#!/usr/bin/env python3
"""自建 GitHub 数据卡片（SVG），替掉 README 里的 github-readme-stats。

为什么要自建：
  github-readme-stats.vercel.app 是公共免费实例，高峰期直接 503（2026-11-16 实测
  /api 和 /api/top-langs 全部 503），README 里的图就裂开；加上 vercel.app 在国内
  基本不可达，GitHub 的 camo 代理拉不到就整块空白。个人主页上的图不该依赖一个会限流
  的免费服务，所以这里用和 metric 一样的数据自己画 SVG：文件进仓库，camo 拉的是
  raw.githubusercontent.com，不再经过第三方。

产出（metrics/badges/）：
  iihao-overview.svg        数字 + 常用语言（中文标签）
  iihao-overview-en.svg     同上，英文标签
  iihao-overview-dark.svg   暗色
  iihao-overview-en-dark.svg
  iihao-activity.svg        近一年提交热力图（中文）
  iihao-activity-en.svg
  iihao-activity-dark.svg
  iihao-activity-en-dark.svg

口径：只算自己名下、非 fork 的仓库（与 profile_stats.py 一致）。
用法：
  GH_TOKEN=$(gh auth token) python3 scripts/profile_card.py
"""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path

OWNER = "iihao"
BADGE_DIR = Path("metrics/badges")

GQL_REPOS = """
{ user(login: "%s") {
    followers { totalCount }
    repositories(first: 100, ownerAffiliations: OWNER, isFork: false) {
      totalCount
      nodes {
        stargazerCount
        forkCount
        languages(first: 10, orderBy: {field: SIZE, direction: DESC}) {
          edges { size node { name color } }
        }
      }
    } } }
""" % OWNER

GQL_ACTIVITY = """
{ user(login: "%s") {
    contributionsCollection {
      contributionCalendar {
        totalContributions
        weeks { contributionDays { date contributionCount } }
      }
    } } }
""" % OWNER

FONT = ("-apple-system,BlinkMacSystemFont,&#39;Segoe UI&#39;,Helvetica,Arial,"
        "&#39;Noto Sans&#39;,sans-serif")

THEMES = {
    "light": {
        "bg": "#ffffff",
        "title": "#1f2328",
        "text": "#57606a",
        "muted": "#8b949e",
        "track": "#eaeef2",
        "empty": "#ebedf0",
        "levels": ["#9be9a8", "#40c463", "#30a14e", "#216e39"],
    },
    "dark": {
        "bg": "#0d1117",
        "title": "#e6edf3",
        "text": "#8b949e",
        "muted": "#6e7681",
        "track": "#21262d",
        "empty": "#161b22",
        "levels": ["#0e4429", "#006d32", "#26a641", "#39d353"],
    },
}

LABELS = {
    "zh": {
        "repos": "公开仓库",
        "stars": "总 star",
        "forks": "fork",
        "followers": "followers",
        "commits": "近一年提交",
        "langs": "常用语言",
        "other": "其它",
        "activity": "近一年提交",
        "less": "少",
        "more": "多",
    },
    "en": {
        "repos": "Public repos",
        "stars": "Total stars",
        "forks": "Forks",
        "followers": "Followers",
        "commits": "Commits (1y)",
        "langs": "Top languages",
        "other": "Other",
        "activity": "Commits in the last year",
        "less": "Less",
        "more": "More",
    },
}

FALLBACK_COLORS = {
    "Vue": "#41b883",
    "TypeScript": "#3178c6",
    "JavaScript": "#f1e05a",
    "Python": "#3572a5",
    "GDScript": "#355570",
    "Swift": "#f05138",
    "Ruby": "#701516",
    "PLpgSQL": "#336790",
    "CSS": "#663399",
    "HTML": "#e34c26",
    "Shell": "#89e051",
    "TSQL": "#e38c00",
    "SQL": "#e38c00",
    "Java": "#b07219",
}


def gql(query: str) -> dict:
    result = subprocess.run(
        ["gh", "api", "graphql", "-f", f"query={query}"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise SystemExit(f"GraphQL 失败：{result.stderr.strip()}")
    return json.loads(result.stdout)["data"]["user"]


def esc(text: str) -> str:
    return (text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def human_bytes(size: int) -> str:
    if size >= 1_000_000:
        return f"{size / 1_000_000:.1f} MB"
    if size >= 1_000:
        return f"{size / 1_000:.0f} kB"
    return f"{size} B"


def stack_languages(repos: list[dict]) -> list[tuple[str, str, int]]:
    totals: dict[str, dict] = {}
    for repo in repos:
        for edge in (repo.get("languages") or {}).get("edges", []):
            name = edge["node"]["name"]
            entry = totals.setdefault(
                name,
                {
                    "size": 0,
                    "color": edge["node"].get("color") or FALLBACK_COLORS.get(name, "#8b949e"),
                },
            )
            entry["size"] += int(edge["size"])
    ranked = sorted(totals.items(), key=lambda item: item[1]["size"], reverse=True)
    return [(name, data["color"], data["size"]) for name, data in ranked]


def overview_svg(stats: dict, langs: list[tuple[str, str, int]],
                 theme_name: str, lang_key: str) -> str:
    theme = THEMES[theme_name]
    label = LABELS[lang_key]
    width, height = 840, 240
    total = sum(size for _, _, size in langs) or 1

    rows = [
        (label["repos"], stats["repos"]),
        (label["stars"], stats["stars"]),
        (label["forks"], stats["forks"]),
        (label["followers"], stats["followers"]),
        (label["commits"], stats["commits"]),
    ]

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" role="img">',
        f'<rect width="{width}" height="{height}" rx="12" fill="{theme["bg"]}"/>',
        f'<text x="28" y="38" font-family="{FONT}" font-size="13" font-weight="600" '
        f'fill="{theme["muted"]}" letter-spacing="1.2">GITHUB</text>',
    ]

    # 左栏：五项数字
    for index, (name, value) in enumerate(rows):
        y = 74 + index * 30
        parts.append(
            f'<text x="28" y="{y}" font-family="{FONT}" font-size="13" '
            f'fill="{theme["text"]}">{esc(name)}</text>'
        )
        parts.append(
            f'<text x="196" y="{y}" font-family="{FONT}" font-size="15" '
            f'font-weight="600" text-anchor="end" fill="{theme["title"]}">{value}</text>'
        )

    # 右栏：语言条形图 —— 名字 | 体积 | 条 | 百分比，四段互不重叠
    name_x, size_x, bar_x, bar_w = 330, 462, 476, 244
    parts.append(
        f'<text x="{name_x}" y="38" font-family="{FONT}" font-size="13" font-weight="600" '
        f'fill="{theme["muted"]}" letter-spacing="1.2">{esc(label["langs"].upper())}</text>'
    )
    top = langs[:6]
    if len(langs) > 6:
        rest = sum(size for _, _, size in langs[6:])
        top = top + [(label["other"], "#8b949e", rest)]
    for index, (name, color, size) in enumerate(top):
        y = 66 + index * 26
        pct = size / total * 100
        parts.append(
            f'<text x="{name_x}" y="{y}" font-family="{FONT}" font-size="12.5" '
            f'fill="{theme["text"]}">{esc(name if len(name) <= 16 else name[:15] + "…")}</text>'
        )
        parts.append(
            f'<text x="{size_x}" y="{y}" font-family="{FONT}" font-size="11" '
            f'text-anchor="end" fill="{theme["muted"]}">{human_bytes(size)}</text>'
        )
        parts.append(
            f'<rect x="{bar_x}" y="{y - 8}" width="{bar_w}" height="8" rx="4" '
            f'fill="{theme["track"]}"/>'
        )
        filled = max(4.0, bar_w * pct / 100)
        parts.append(
            f'<rect x="{bar_x}" y="{y - 8}" width="{filled:.1f}" height="8" rx="4" '
            f'fill="{color}"/>'
        )
        parts.append(
            f'<text x="{bar_x + bar_w + 12}" y="{y}" font-family="{FONT}" font-size="12" '
            f'fill="{theme["muted"]}">{pct:.1f}%</text>'
        )

    parts.append("</svg>")
    return "".join(parts)


def activity_svg(calendar: dict, theme_name: str, lang_key: str) -> str:
    theme = THEMES[theme_name]
    label = LABELS[lang_key]
    days = [
        (day["date"], int(day["contributionCount"]))
        for week in calendar["weeks"]
        for day in week["contributionDays"]
    ]

    cell, gap = 10, 3
    top = 50
    weeks = calendar["weeks"]
    grid_w = len(weeks) * (cell + gap)
    width = 840
    left = max(46, round((width - grid_w) / 2))
    height = top + 7 * (cell + gap) + 30

    counts = [count for _, count in days if count > 0]
    top_count = max(counts) if counts else 1

    def level(count: int) -> str:
        if count == 0:
            return theme["empty"]
        ratio = count / top_count
        if ratio < 0.25:
            return theme["levels"][0]
        if ratio < 0.5:
            return theme["levels"][1]
        if ratio < 0.75:
            return theme["levels"][2]
        return theme["levels"][3]

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" role="img">',
        f'<rect width="{width}" height="{height}" rx="12" fill="{theme["bg"]}"/>',
        f'<text x="20" y="28" font-family="{FONT}" font-size="13" font-weight="600" '
        f'fill="{theme["muted"]}" letter-spacing="1.2">{esc(label["activity"].upper())}</text>',
        f'<text x="{width - 20}" y="28" font-family="{FONT}" font-size="13" '
        f'text-anchor="end" fill="{theme["title"]}">'
        f'{calendar["totalContributions"]}</text>',
    ]

    # 星期标签：只标周一 / 周三 / 周五，基线与格子垂直居中
    for row, text in ((1, "Mon"), (3, "Wed"), (5, "Fri")):
        y = top + row * (cell + gap) + cell - 2
        parts.append(
            f'<text x="{left - 8}" y="{y}" font-family="{FONT}" font-size="9.5" '
            f'text-anchor="end" fill="{theme["muted"]}">{text}</text>'
        )

    last_month_x = -999
    for week_index, week in enumerate(weeks):
        week_days = week["contributionDays"]
        if not week_days:
            continue
        month = week_days[0]["date"][:7]
        x = left + week_index * (cell + gap)
        if int(week_days[0]["date"][8:]) <= 7 and x - last_month_x >= 30:
            last_month_x = x
            parts.append(
                f'<text x="{x}" y="{top - 8}" font-family="{FONT}" font-size="9.5" '
                f'fill="{theme["muted"]}">{datetime.strptime(month, "%Y-%m").strftime("%b")}</text>'
            )
        for day_index, day in enumerate(week_days):
            y = top + day_index * (cell + gap)
            parts.append(
                f'<rect x="{x}" y="{y}" width="{cell}" height="{cell}" rx="2.5" '
                f'fill="{level(int(day["contributionCount"]))}">'
                f'<title>{day["date"]}: {day["contributionCount"]}</title></rect>'
            )

    # 图例：左下角「少 ▢▢▢▢ 多」
    legend_y = top + 7 * (cell + gap) + 12
    parts.append(
        f'<text x="{left}" y="{legend_y + 9}" font-family="{FONT}" font-size="9.5" '
        f'fill="{theme["muted"]}">{esc(label["less"])}</text>'
    )
    for index in range(4):
        x = left + 22 + index * (cell + 3)
        parts.append(
            f'<rect x="{x}" y="{legend_y}" width="{cell}" height="{cell}" rx="2.5" '
            f'fill="{theme["levels"][index]}"/>'
        )
    parts.append(
        f'<text x="{left + 22 + 4 * (cell + 3) + 2}" y="{legend_y + 9}" '
        f'font-family="{FONT}" font-size="9.5" fill="{theme["muted"]}">{esc(label["more"])}</text>'
    )
    parts.append("</svg>")
    return "".join(parts)


def main() -> int:
    user = gql(GQL_REPOS)
    repos = user["repositories"]["nodes"]
    langs = stack_languages(repos)
    calendar = gql(GQL_ACTIVITY)["contributionsCollection"]["contributionCalendar"]

    stats = {
        "repos": int(user["repositories"]["totalCount"]),
        "stars": sum(int(r["stargazerCount"]) for r in repos),
        "forks": sum(int(r["forkCount"]) for r in repos),
        "followers": int(user["followers"]["totalCount"]),
        "commits": int(calendar["totalContributions"]),
    }

    BADGE_DIR.mkdir(parents=True, exist_ok=True)
    written = []
    for lang_key in ("zh", "en"):
        suffix = "" if lang_key == "zh" else f"-{lang_key}"
        for theme_name in ("light", "dark"):
            theme_suffix = "" if theme_name == "light" else f"-{theme_name}"
            for kind, svg in (
                ("overview", overview_svg(stats, langs, theme_name, lang_key)),
                ("activity", activity_svg(calendar, theme_name, lang_key)),
            ):
                path = BADGE_DIR / f"{OWNER}-{kind}{suffix}{theme_suffix}.svg"
                path.write_text(svg + "\n")
                written.append(path.name)

    print(f"stars={stats['stars']} repos={stats['repos']} commits={stats['commits']} "
          f"langs={', '.join(name for name, _, _ in langs[:6])}")
    print(f"{len(written)} 个 SVG → {BADGE_DIR}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
