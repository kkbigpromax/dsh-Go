#!/usr/bin/env python3
"""The report scripts/stats.sh prints, from the rows it fetched.

    python3 scripts/stats-report.py <dir with downloads.json, checks.json> <days> [today]

Rows are Analytics Engine SQL API answers ({"data": [...]}, numbers maybe as
strings). Days are UTC+8 dates; [today] defaults to today there.
"""

import datetime
import json
import os
import sys
import unicodedata
from collections import Counter, defaultdict

ROUTES = [("cn", "国内"), ("global", "海外"), ("github", "GitHub")]


def load(folder, name):
    try:
        with open(os.path.join(folder, f"{name}.json"), encoding="utf-8") as f:
            return json.load(f).get("data") or []
    except FileNotFoundError:
        return []


def num(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def shift(day, n):
    return (datetime.date.fromisoformat(day) + datetime.timedelta(days=n)).isoformat()


def width(text):
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in text)


def table(headers, rows):
    """Left-aligned first column, the rest right-aligned; CJK counts double."""
    cells = [[str(c) for c in r] for r in [headers, *rows]]
    widths = [max(width(r[i]) for r in cells) for i in range(len(headers))]
    out = []
    for r in cells:
        parts = []
        for i, c in enumerate(r):
            gap = " " * (widths[i] - width(c))
            parts.append(c + gap if i == 0 or i == len(r) - 1 and not c.replace(",", "").isdigit() else gap + c)
        out.append("  ".join(parts).rstrip())
    return "\n".join(out)




def spread(counter, top=6, unknown="未上报"):
    total = sum(counter.values())
    if not total:
        return "—"
    items = counter.most_common()
    shown = items[:top]
    rest = sum(n for _, n in items[top:])
    parts = [f"{k or unknown} {round(100 * n / total)}%" for k, n in shown]
    if rest:
        parts.append(f"其他 {round(100 * rest / total)}%")
    return " · ".join(parts)


def fmt(n):
    return f"{int(round(n)):,}"


def main():
    folder, days = sys.argv[1], int(sys.argv[2])
    today = (sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else
             (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=8)).date().isoformat())
    window = [shift(today, -i) for i in range(days - 1, -1, -1)]
    inside = set(window)
    print(f"DSH Go 统计 · {window[0]} – {window[-1]}（UTC+8）")

    # ── Downloads ──
    clicks = defaultdict(float)
    by_route = defaultdict(float)
    by_version = defaultdict(Counter)
    people = defaultdict(set)
    countries = Counter()
    for r in load(folder, "downloads"):
        day = r.get("day")
        if day not in inside:
            continue
        n = num(r.get("n"))
        clicks[day] += n
        by_route[(day, r.get("route"))] += n
        by_version[day][r.get("version") or "?"] += n
        countries[r.get("country") or "XX"] += n
        if r.get("device"):
            people[day].add(r["device"])
    print("\n下载（点下载按钮的次数；人 = 当天去重的设备码）")
    rows = []
    for day in window:
        if not clicks[day]:
            continue
        versions = " ".join(f"{v}×{fmt(n)}" for v, n in by_version[day].most_common(3))
        rows.append([day, fmt(clicks[day]), fmt(len(people[day])), *[fmt(by_route[(day, k)]) for k, _ in ROUTES], versions])
    if rows:
        rows.append(["合计", fmt(sum(clicks.values())), "", *[fmt(sum(v for (d, k2), v in by_route.items() if k2 == k)) for k, _ in ROUTES], ""])
        print(table(["日期", "次数", "人", *[label for _, label in ROUTES], "版本"], rows))
        print(f"国家/地区：{spread(countries, top=8, unknown='XX')}")
    else:
        print("（没有数据）")

    # ── Update checks: near-daily-active ──
    devices = defaultdict(set)
    checks = defaultdict(float)
    app_of = defaultdict(dict)
    for r in load(folder, "checks"):
        day = r.get("day")
        if day not in inside:
            continue
        checks[day] += num(r.get("n"))
        if r.get("device"):
            devices[day].add(r["device"])
            app_of[day][r["device"]] = r.get("app") or ""
    print("\n近似日活（App 检查更新，只含带通道令牌的包；同一 IP 与 UA 算一台，NAT 下会低估）")
    rows = []
    for day in window:
        if not checks[day]:
            continue
        rows.append([day, fmt(len(devices[day])), fmt(checks[day]), spread(Counter(app_of[day].values()), top=3)])
    print(table(["日期", "设备", "检查次数", "版本（按设备）"], rows) if rows else "（没有数据）")


if __name__ == "__main__":
    main()
