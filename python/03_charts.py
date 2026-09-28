#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
03_charts.py
============
从 MySQL 读取分析结果并生成六张图表（PNG）。

出图原则：
  1. 标题写「结论句」，不写「XX趋势图」
  2. 坐标轴必须带单位
  3. 颜色不超过 5 种，主色 + 灰阶
  4. 结构化图形（漏斗/帕累托）把数字标在图上

★ 中文字体：不设置会全部显示为方框。脚本会自动挑选系统里可用的中文字体。

用法：
    # 设置连接串（避免把密码写进代码）
    #   Windows:  set MYSQL_URL=mysql+pymysql://root:密码@localhost:3306/user_behavior?charset=utf8mb4
    python 03_charts.py --outdir images
"""

import argparse
import os
import sys

import matplotlib

matplotlib.use("Agg")

import matplotlib.font_manager as fm
import matplotlib.pyplot as plt
import pandas as pd
from sqlalchemy import create_engine

DEFAULT_URL = "mysql+pymysql://root:password@localhost:3307/user_behavior?charset=utf8mb4"

C_MAIN = "#0b6bcb"      # 主色
C_SECOND = "#3f8fdd"    # 次色
C_LIGHT = "#a9c7e8"     # 浅色
C_GREY = "#8b949e"      # 灰
C_ACCENT = "#d97706"    # 强调色（只用于最想让人看到的那一根）

FONT_CANDIDATES = [
    "Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "Source Han Sans SC",
    "PingFang SC", "Hiragino Sans GB", "WenQuanYi Zen Hei", "Arial Unicode MS",
]


def setup_font():
    available = {f.name for f in fm.fontManager.ttflist}
    for name in FONT_CANDIDATES:
        if name in available:
            plt.rcParams["font.sans-serif"] = [name]
            print(f"[FONT] 使用中文字体：{name}")
            break
    else:
        print("[WARN] 未找到中文字体，图中中文可能显示为方框。")
        print("       解决办法：安装 Microsoft YaHei / SimHei，或删除 matplotlib 字体缓存后重试。")
    plt.rcParams["axes.unicode_minus"] = False
    plt.rcParams["figure.dpi"] = 130
    plt.rcParams["axes.edgecolor"] = "#d0d7de"
    plt.rcParams["axes.labelcolor"] = "#24292f"
    plt.rcParams["text.color"] = "#24292f"
    plt.rcParams["xtick.color"] = "#57606a"
    plt.rcParams["ytick.color"] = "#57606a"


def save(fig, outdir, name):
    path = os.path.join(outdir, name)
    fig.savefig(path, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print(f"[OK] {path}")


def clean_axes(ax):
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.grid(axis="y", color="#eef1f4", linewidth=0.8)
    ax.set_axisbelow(True)


# ---------------------------------------------------------------- 图1
def chart_daily(engine, outdir):
    sql = """
    SELECT dt,
           SUM(behavior_type = 'pv') AS pv,
           COUNT(DISTINCT CASE WHEN behavior_type = 'pv' THEN user_id END) AS uv
    FROM ub GROUP BY dt ORDER BY dt
    """
    df = pd.read_sql(sql, engine)
    if df.empty:
        return
    df["pv"] = df["pv"].astype(float)
    df["uv"] = df["uv"].astype(float)

    fig, ax1 = plt.subplots(figsize=(9.5, 4.2))
    ax1.bar(df["dt"], df["pv"] / 10000, color=C_LIGHT, label="PV（万次）")
    ax1.set_ylabel("PV（万次）")
    ax1.set_xlabel("日期")
    ax1.tick_params(axis="x", rotation=45)
    clean_axes(ax1)

    ax2 = ax1.twinx()
    ax2.plot(df["dt"], df["uv"] / 10000, color=C_MAIN, marker="o",
             markersize=5, linewidth=2, label="UV（万人）")
    ax2.set_ylabel("UV（万人）")
    ax2.spines["top"].set_visible(False)

    peak = df.loc[df["pv"].idxmax()]
    ax1.set_title(f"日流量与活跃用户：PV 在 {peak['dt']} 达到峰值 {peak['pv'] / 10000:.0f} 万次",
                  fontsize=12, pad=12, loc="left")

    h1, l1 = ax1.get_legend_handles_labels()
    h2, l2 = ax2.get_legend_handles_labels()
    ax1.legend(h1 + h2, l1 + l2, frameon=False, loc="upper left")
    save(fig, outdir, "01_daily_pv_uv.png")


# ---------------------------------------------------------------- 图2
def chart_hourly(engine, outdir):
    sql = """
    SELECT hh,
           COUNT(*) AS action_cnt,
           SUM(behavior_type = 'pv') AS pv,
           SUM(behavior_type = 'buy') AS buy,
           ROUND(100 * SUM(behavior_type = 'buy')
                 / NULLIF(SUM(behavior_type = 'pv'), 0), 4) AS buy_per_pv_pct
    FROM ub GROUP BY hh ORDER BY hh
    """
    df = pd.read_sql(sql, engine)
    if df.empty:
        return
    df["pv"] = df["pv"].astype(float)
    df["buy_per_pv_pct"] = df["buy_per_pv_pct"].astype(float)

    fig, ax1 = plt.subplots(figsize=(9.5, 4.2))
    colors = [C_ACCENT if v == df["pv"].max() else C_LIGHT for v in df["pv"]]
    ax1.bar(df["hh"], df["pv"] / 10000, color=colors, label="浏览量（万次）")
    ax1.set_xlabel("小时（北京时间）")
    ax1.set_ylabel("PV（万次）")
    ax1.set_xticks(range(0, 24))
    clean_axes(ax1)

    ax2 = ax1.twinx()
    ax2.plot(df["hh"], df["buy_per_pv_pct"], color=C_MAIN, marker="o",
             markersize=4, linewidth=2, label="单位浏览购买率（%）")
    ax2.set_ylabel("单位浏览购买率（%）")
    ax2.spines["top"].set_visible(False)

    peak_pv = int(df.loc[df["pv"].idxmax(), "hh"])
    peak_rate = int(df.loc[df["buy_per_pv_pct"].idxmax(), "hh"])
    ax1.set_title(f"流量峰值在 {peak_pv} 时，但转化率峰值在 {peak_rate} 时——高峰期流量质量偏低",
                  fontsize=12, pad=12, loc="left")

    h1, l1 = ax1.get_legend_handles_labels()
    h2, l2 = ax2.get_legend_handles_labels()
    ax1.legend(h1 + h2, l1 + l2, frameon=False, loc="upper left")
    save(fig, outdir, "02_hourly_pattern.png")


# ---------------------------------------------------------------- 图3
def chart_funnel(engine, outdir):
    sql_beh = """
    SELECT behavior_type, COUNT(*) AS cnt FROM ub GROUP BY behavior_type
    """
    sql_pair = """
    SELECT SUM(has_pv) AS pv_pairs,
           SUM(has_pv AND (has_fav = 1 OR has_cart = 1)) AS intent_pairs,
           SUM(has_pv AND has_buy) AS buy_pairs
    FROM ub_pair
    """
    df_b = pd.read_sql(sql_beh, engine)
    df_p = pd.read_sql(sql_pair, engine)

    fig, axes = plt.subplots(1, 2, figsize=(12.5, 4.4))

    # 左：行为量分布
    ax = axes[0]
    order = ["pv", "cart", "fav", "buy"]
    name_map = {"pv": "浏览", "cart": "加购", "fav": "收藏", "buy": "购买"}
    df_b = df_b.set_index("behavior_type").reindex(order).dropna().reset_index()
    df_b["cnt"] = df_b["cnt"].astype(float)
    vals = df_b["cnt"] / 10000
    bars = ax.barh([name_map[b] for b in df_b["behavior_type"]], vals,
                   color=[C_MAIN, C_SECOND, C_LIGHT, C_GREY])
    ax.invert_yaxis()
    total = df_b["cnt"].sum()
    for bar, v, raw in zip(bars, vals, df_b["cnt"]):
        ax.text(bar.get_width() + max(vals) * 0.01, bar.get_y() + bar.get_height() / 2,
                f"{v:.1f}万 ({raw / total:.1%})", va="center", fontsize=9.5, color="#24292f")
    ax.set_xlabel("行为次数（万次）")
    ax.set_xlim(0, max(vals) * 1.28)
    clean_axes(ax)
    ax.grid(axis="x", color="#eef1f4", linewidth=0.8)
    ax.grid(axis="y", visible=False)
    ax.set_title("行为量分布口径：浏览占绝对主导", fontsize=11.5, loc="left", pad=10)

    # 右：商品级路径漏斗
    ax = axes[1]
    pv, intent, buy = (float(df_p.loc[0, c]) for c in ["pv_pairs", "intent_pairs", "buy_pairs"])
    steps = ["浏览过商品", "产生收藏/加购意向", "最终购买"]
    prices = [pv, intent, buy]
    bars = ax.barh(steps, prices, color=[C_MAIN, C_SECOND, C_ACCENT])
    ax.invert_yaxis()
    for bar, v in zip(bars, prices):
        pct = v / pv if pv else 0
        ax.text(bar.get_width() + pv * 0.01, bar.get_y() + bar.get_height() / 2,
                f"{v:,.0f} 对  ({pct:.2%})", va="center", fontsize=9.5, color="#24292f")
    ax.set_xlabel("用户-商品对数量（对）")
    ax.set_xlim(0, pv * 1.34)
    clean_axes(ax)
    ax.grid(axis="x", color="#eef1f4", linewidth=0.8)
    ax.grid(axis="y", visible=False)
    ax.set_title(f"商品级路径口径：浏览→购买转化 {(buy / pv if pv else 0):.2%}", fontsize=11.5,
                 loc="left", pad=10)

    fig.suptitle("转化漏斗（两种口径对照）", fontsize=13, x=0.02, ha="left", y=1.04)
    fig.tight_layout()
    save(fig, outdir, "03_funnel.png")


# ---------------------------------------------------------------- 图4
def chart_rfm(engine, outdir):
    sql = """
    SELECT CASE
             WHEN r_s >= 4 AND f_s >= 4 AND m_s >= 4 THEN '重要价值'
             WHEN r_s >= 4 AND f_s <  4 AND m_s >= 4 THEN '重要发展'
             WHEN r_s <  4 AND f_s >= 4 AND m_s >= 4 THEN '重要保持'
             WHEN r_s <  4 AND f_s <  4 AND m_s >= 4 THEN '重要挽留'
             WHEN r_s >= 4 AND f_s >= 4 AND m_s <  4 THEN '一般价值'
             WHEN r_s >= 4 AND f_s <  4 AND m_s <  4 THEN '一般发展'
             WHEN r_s <  4 AND f_s >= 4 AND m_s <  4 THEN '一般保持'
             ELSE '一般挽留' END AS segment,
           COUNT(*) AS users,
           ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM rfm_score), 2) AS pct
    FROM rfm_score GROUP BY segment
    """
    df = pd.read_sql(sql, engine)
    if df.empty:
        return
    df["pct"] = df["pct"].astype(float)
    df = df.sort_values("pct", ascending=False)

    fig, ax = plt.subplots(figsize=(9.5, 4.2))
    colors = [C_ACCENT if s == "重要价值" else (C_MAIN if s.startswith("重要") else C_LIGHT)
              for s in df["segment"]]
    bars = ax.bar(df["segment"], df["pct"], color=colors)
    for bar, pct, u in zip(bars, df["pct"], df["users"]):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.35,
                f"{pct:.1f}%", ha="center", fontsize=9.5, color="#24292f")
    ax.set_ylabel("用户占比（%）")
    ax.set_xlabel("RFM 客户分层")
    ax.tick_params(axis="x", rotation=20)
    top = df.iloc[0]
    ax.set_title(f"RFM 分层：{top['segment']}客户占比最高（{top['pct']:.1f}%）",
                 fontsize=12, loc="left", pad=12)
    clean_axes(ax)
    save(fig, outdir, "04_rfm_segment.png")


# ---------------------------------------------------------------- 图5
def chart_repurchase(engine, outdir):
    sql = """
    WITH b AS (SELECT DISTINCT user_id, dt FROM ub WHERE behavior_type = 'buy'),
    g AS (SELECT user_id,
                 DATEDIFF(dt, LAG(dt) OVER (PARTITION BY user_id ORDER BY dt)) AS gap
          FROM b)
    SELECT CASE WHEN gap = 1 THEN '间隔1天'
                WHEN gap <= 3 THEN '间隔2-3天'
                WHEN gap <= 5 THEN '间隔4-5天'
                WHEN gap <= 8 THEN '间隔6-8天'
                ELSE '间隔8天以上' END AS gap_bucket,
           COUNT(*) AS samples
    FROM g WHERE gap IS NOT NULL GROUP BY gap_bucket
    """
    df = pd.read_sql(sql, engine)
    if df.empty:
        return
    order = ["间隔1天", "间隔2-3天", "间隔4-5天", "间隔6-8天", "间隔8天以上"]
    df = df.set_index("gap_bucket").reindex(order).dropna().reset_index()
    df["samples"] = df["samples"].astype(float)
    total = df["samples"].sum()

    fig, ax = plt.subplots(figsize=(8.6, 4.0))
    colors = [C_ACCENT if v == df["samples"].max() else C_MAIN for v in df["samples"]]
    bars = ax.bar(df["gap_bucket"], df["samples"], color=colors)
    for bar, v in zip(bars, df["samples"]):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + total * 0.008,
                f"{v / total:.1%}", ha="center", fontsize=9.5, color="#24292f")
    ax.set_ylabel("复购样本数（次）")
    ax.set_xlabel("相邻两次购买的间隔（天）")
    ax.set_title("复购间隔分布：短间隔复购占主导（受 9 天窗口限制，长周期观测不到）",
                 fontsize=11.5, loc="left", pad=12)
    clean_axes(ax)
    save(fig, outdir, "05_repurchase_gap.png")


# ---------------------------------------------------------------- 图6
def chart_pareto(engine, outdir):
    sql = """
    WITH r AS (
      SELECT category_id, pv,
             ROW_NUMBER() OVER (ORDER BY pv DESC) AS rn,
             SUM(pv) OVER () AS total_pv,
             SUM(pv) OVER (ORDER BY pv DESC
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_pv
      FROM cat_stat
    )
    SELECT rn, pv, ROUND(100 * cum_pv / total_pv, 2) AS cum_pct
    FROM r WHERE rn <= 30 ORDER BY rn
    """
    sql_total = """
    WITH r AS (
      SELECT pv,
             COUNT(*) OVER () AS n_cat,
             SUM(pv) OVER () AS total_pv,
             SUM(pv) OVER (ORDER BY pv DESC
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_pv
      FROM cat_stat
    )
    SELECT COUNT(*) AS n_cat_total,
           SUM(cum_pv <= 0.8 * total_pv) AS cats_80
    FROM r
    """
    df = pd.read_sql(sql, engine)
    if df.empty:
        return
    tot = pd.read_sql(sql_total, engine).iloc[0]
    df["pv"] = df["pv"].astype(float)
    df["cum_pct"] = df["cum_pct"].astype(float)

    fig, ax1 = plt.subplots(figsize=(9.6, 4.4))
    ax1.bar(df["rn"], df["pv"] / 10000, color=C_LIGHT, label="类目浏览量（万次）")
    ax1.set_xlabel("类目流量排名（Top 30）")
    ax1.set_ylabel("PV（万次）")
    clean_axes(ax1)

    ax2 = ax1.twinx()
    ax2.plot(df["rn"], df["cum_pct"], color=C_ACCENT, marker="o",
             markersize=3.5, linewidth=2, label="累计占比（%）")
    ax2.axhline(80, color=C_GREY, linestyle="--", linewidth=1)
    ax2.text(df["rn"].max(), 81.5, "80% 累计线", ha="right", fontsize=9, color=C_GREY)
    ax2.set_ylabel("累计占比（%）")
    ax2.set_ylim(0, 105)
    ax2.spines["top"].set_visible(False)

    share = float(tot["cats_80"]) / float(tot["n_cat_total"])
    ax1.set_title(f"类目流量集中度：{share:.1%} 的类目贡献了 80% 的浏览量"
                  f"（共 {int(tot['n_cat_total']):,} 个类目）",
                  fontsize=11.5, loc="left", pad=12)

    h1, l1 = ax1.get_legend_handles_labels()
    h2, l2 = ax2.get_legend_handles_labels()
    ax1.legend(h1 + h2, l1 + l2, frameon=False, loc="center right")
    save(fig, outdir, "06_category_pareto.png")


CHARTS = [
    ("01 日 PV/UV 趋势", chart_daily),
    ("02 分时访问规律", chart_hourly),
    ("03 转化漏斗", chart_funnel),
    ("04 RFM 分层", chart_rfm),
    ("05 复购间隔分布", chart_repurchase),
    ("06 类目帕累托", chart_pareto),
]


def main():
    ap = argparse.ArgumentParser(description="生成分析图表")
    ap.add_argument("--outdir", default="images")
    ap.add_argument("--only", default="", help="只画某一张，填 01~06")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    setup_font()

    url = os.getenv("MYSQL_URL", DEFAULT_URL)
    if url == DEFAULT_URL:
        print("[WARN] 未设置 MYSQL_URL，使用默认连接串（密码为占位符）。")
    # 忽略 URL 后面的查询串，避免手误写错 charset 导致 pymysql 报错
    url = url.split("?")[0]
    engine = create_engine(url, pool_pre_ping=True, connect_args={"charset": "utf8mb4"})

    failed = []
    for label, fn in CHARTS:
        if args.only and not label.startswith(args.only):
            continue
        try:
            fn(engine, args.outdir)
        except Exception as exc:                                  # noqa: BLE001
            failed.append((label, repr(exc)))
            print(f"[FAIL] {label}: {exc}")

    print("-" * 60)
    print(f"[DONE] 成功 {len(CHARTS) - len(failed)} 张，失败 {len(failed)} 张")
    for label, err in failed:
        print(f"  失败：{label} -> {err}")
    if failed:
        print("提示：失败通常是因为对应 SQL 还没跑过（例如 ub_pair / rfm_score / cat_stat 表不存在）。"
              "先把 sql/ 下的脚本按顺序执行一遍。")
        sys.exit(1)


if __name__ == "__main__":
    main()
