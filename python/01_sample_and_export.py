import argparse
import numpy as np
import pandas as pd

def main():
    # ---- ① 接收命令行参数 ----
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="原始 UserBehavior.csv")
    ap.add_argument("--out", required=True, help="输出的抽样 TSV")
    ap.add_argument("--ratio", type=float, default=0.03, help="抽样比例")
    args = ap.parse_args()

    # 原始数据没有表头，5 列依次是这些
    COLS = ["user_id", "item_id", "category_id", "behavior_type", "ts"]

    # category_id 有空值，int 列存不了 NaN，所以先用 float64（坑点！）
    DTYPES = {
        "user_id": "int64",
        "item_id": "int64",
        "category_id": "float64",
        "behavior_type": "category",
        "ts": "int64",
    }

    rng = np.random.default_rng(42)   # 固定种子，每次抽样结果一样，可复现
    parts = []
    total = 0

    # ---- ② 分块读取，每块 300 万行 ----
    chunks = pd.read_csv(
        args.input, names=COLS, dtype=DTYPES,
        chunksize=3_000_000, on_bad_lines="warn",
    )

    for i, chunk in enumerate(chunks):
        total += len(chunk)

        # ③ 每块独立抽样 3%
        mask = rng.random(len(chunk)) < args.ratio
        sub = chunk.loc[mask].copy()

        # ts 是 UTC 秒：先标 UTC，再转北京时间，直接转会差 8 小时
        ts_utc = pd.to_datetime(sub["ts"], unit="s", utc=True)
        bj = ts_utc.dt.tz_convert("Asia/Shanghai")
        sub["dt"] = bj.dt.date.astype(str)   # 如 2017-11-25
        sub["hh"] = bj.dt.hour.astype("int8")
        # 只保留业务窗口：2017-11-25 ~ 2017-12-03，剔除脏时间戳
        sub = sub[(sub["dt"] >= "2017-11-25") & (sub["dt"] <= "2017-12-03")]

        # 空类目填 0 占位
        sub["category_id"] = sub["category_id"].fillna(0).astype("int64")

        parts.append(sub)
        print(f"[read] 已扫描 {total/1e6:.0f}M 行")

    # ---- ④ 合并所有抽样块，导出 TSV（无表头，LOAD DATA 按列位置导）----
    df = pd.concat(parts, ignore_index=True)
    df = df[["user_id", "item_id", "category_id",
             "behavior_type", "ts", "dt", "hh"]]
    df.to_csv(args.out, sep="\t", index=False, header=False)

    print(f"[DONE] 抽样保留 {len(df):,} 行（{args.ratio:.1%}）")
    print(f"[CHECK] 日期范围 {df['dt'].min()} ~ {df['dt'].max()}")


if __name__ == "__main__":
    main()
