-- ============================================================
-- 04_repurchase.sql  模块四：复购分析
-- 复购率、用户留存、复购周期、生命周期
--
--  数据只覆盖 9 天（2017-11-25 ~ 12-03），
--   平均复购周期是观测下限
-- ============================================================
USE user_behavior;

-- ------------------------------------------------------------
-- 4.1 复购率（购买次数口径 = 平台复购）
-- ------------------------------------------------------------
WITH b AS (
  SELECT user_id, COUNT(*) AS n_buy
  FROM ub WHERE behavior_type='buy'
  GROUP BY user_id
)
SELECT COUNT(*)                   AS buyers,
       SUM(n_buy=1)               AS buy_once,
       SUM(n_buy>=2)              AS buy_twice_plus,
       ROUND(100*SUM(n_buy>=2)/COUNT(*),2) AS repurchase_rate_pct,
       ROUND(AVG(n_buy),2)        AS avg_buy_times,
       MAX(n_buy)                  AS max_buy_times
FROM b;

-- ------------------------------------------------------------
-- 4.2 购买次数分布
-- ------------------------------------------------------------
WITH b AS (
  SELECT user_id, COUNT(*) AS n_buy
  FROM ub WHERE behavior_type='buy'
  GROUP BY user_id
)
SELECT CASE WHEN n_buy=1   THEN '01_1次'
            WHEN n_buy=2   THEN '02_2次'
            WHEN n_buy<=4  THEN '03_3-4次'
            WHEN n_buy<=9  THEN '04_5-9次'
            ELSE '05_10次以上' END AS buy_bucket,
       COUNT(*) AS users,
       ROUND(100*COUNT(*)/(SELECT COUNT(*) FROM b),2) AS pct
FROM b
GROUP BY buy_bucket
ORDER BY buy_bucket;

-- ------------------------------------------------------------
-- 4.3 同商品复购率
-- ------------------------------------------------------------
WITH bu AS (
  SELECT user_id, item_id, COUNT(*) AS c
  FROM ub WHERE behavior_type='buy'
  GROUP BY user_id, item_id
),
buyers AS (SELECT COUNT(DISTINCT user_id) AS n FROM ub WHERE behavior_type='buy')
SELECT (SELECT n FROM buyers) AS total_buyers,
       COUNT(DISTINCT CASE WHEN c>=2 THEN user_id END) AS rebuy_same_item_users,
       ROUND(100*COUNT(DISTINCT CASE WHEN c>=2 THEN user_id END)
             /NULLIF((SELECT n FROM buyers),0),2) AS same_item_repurchase_pct
FROM bu;

-- ------------------------------------------------------------
-- 4.4 复购周期（LAG 取上一次购买日期）
--     先按 dt 去重：同一天多次购买会产生 0 天间隔
-- ------------------------------------------------------------
WITH b AS (
  SELECT DISTINCT user_id, dt FROM ub WHERE behavior_type='buy'
),
g AS (
  SELECT user_id, dt,
         LAG(dt) OVER (PARTITION BY user_id ORDER BY dt) AS prev_dt
  FROM b
)
SELECT COUNT(*)                       AS gap_samples,
       COUNT(DISTINCT user_id)        AS users_with_repeat,
       ROUND(AVG(DATEDIFF(dt,prev_dt)),2) AS avg_gap_days,
       MIN(DATEDIFF(dt,prev_dt))       AS min_gap_days,
       MAX(DATEDIFF(dt,prev_dt))       AS max_gap_days
FROM g
WHERE prev_dt IS NOT NULL;

-- ------------------------------------------------------------
-- 4.5 复购间隔分布
-- ------------------------------------------------------------
WITH b AS (
  SELECT DISTINCT user_id, dt FROM ub WHERE behavior_type='buy'
),
g AS (
  SELECT user_id,
         DATEDIFF(dt, LAG(dt) OVER (PARTITION BY user_id ORDER BY dt)) AS gap
  FROM b
)
SELECT CASE WHEN gap=1  THEN '01_间隔1天'
            WHEN gap<=3  THEN '02_间隔2-3天'
            WHEN gap<=5  THEN '03_间隔4-5天'
            WHEN gap<=8  THEN '04_间隔6-8天'
            ELSE '05_间隔8天以上' END AS gap_bucket,
       COUNT(*) AS samples,
       ROUND(100*COUNT(*)/(SELECT COUNT(*) FROM g WHERE gap IS NOT NULL),2) AS pct
FROM g
WHERE gap IS NOT NULL
GROUP BY gap_bucket
ORDER BY gap_bucket;

-- ------------------------------------------------------------
-- 4.6 复购用户特征
-- ------------------------------------------------------------
WITH b AS (
  SELECT user_id, COUNT(*) AS n_buy, COUNT(DISTINCT dt) AS buy_days
  FROM ub WHERE behavior_type='buy'
  GROUP BY user_id
),
lbl AS (SELECT b.*, (n_buy>=2) AS is_repeat FROM b),
act AS (
  SELECT user_id, COUNT(*) AS total_acts, COUNT(DISTINCT dt) AS active_days
  FROM ub GROUP BY user_id
)
SELECT lbl.is_repeat,
       COUNT(*) AS users,
       ROUND(AVG(act.total_acts),1)  AS avg_total_acts,
       ROUND(AVG(act.active_days),2) AS avg_active_days,
       ROUND(AVG(lbl.buy_days),2)    AS avg_buy_days
FROM lbl JOIN act ON act.user_id = lbl.user_id
GROUP BY lbl.is_repeat
ORDER BY lbl.is_repeat DESC;
