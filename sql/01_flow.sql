-- ============================================================
-- 01_flow.sql  模块一：流量分析
-- 对应 JD 关键词：PV/UV、DAU、日活趋势、时段规律、用户活跃度分层
-- ============================================================
USE user_behavior;

-- ------------------------------------------------------------
-- 1.1 整体规模（报告第一张表）
-- ------------------------------------------------------------
SELECT COUNT(*)                AS rows_total,
       COUNT(DISTINCT user_id) AS users,
       COUNT(DISTINCT item_id) AS items,
       COUNT(DISTINCT category_id) AS cats,
       MIN(dt) AS dt_start, MAX(dt) AS dt_end
FROM ub;

-- ------------------------------------------------------------
-- 1.2 行为类型分布
--     pv 约 89%，cart 约 5.5%，fav 约 2.9%，buy 约 2%
-- ------------------------------------------------------------
SELECT behavior_type, COUNT(*) AS cnt,
       ROUND(100*COUNT(*)/(SELECT COUNT(*) FROM ub), 3) AS pct
FROM ub
GROUP BY behavior_type
ORDER BY cnt DESC;

-- ------------------------------------------------------------
-- 1.3 日 PV / UV / 人均浏览页数
--     面试点：UV 必须 COUNT(DISTINCT)；NULLIF 防除零
-- ------------------------------------------------------------
SELECT dt,
       SUM(behavior_type='pv') AS pv,
       COUNT(DISTINCT CASE WHEN behavior_type='pv' THEN user_id END) AS uv,
       ROUND(SUM(behavior_type='pv') /
             NULLIF(COUNT(DISTINCT CASE WHEN behavior_type='pv' THEN user_id END), 0), 2) AS pv_per_uv
FROM ub
GROUP BY dt
ORDER BY dt;

-- ------------------------------------------------------------
-- 1.4 分时访问规律（重点：流量峰 vs 转化率峰是否重合）
--     结论：流量峰 21 点，转化峰 10-11 点，两者不重合
-- ------------------------------------------------------------
SELECT hh,
       COUNT(*) AS action_cnt,
       SUM(behavior_type='pv') AS pv,
       SUM(behavior_type='buy') AS buy,
       ROUND(100*SUM(behavior_type='buy') /
             NULLIF(SUM(behavior_type='pv'), 0), 4) AS buy_per_pv_pct
FROM ub
GROUP BY hh
ORDER BY hh;

-- ------------------------------------------------------------
-- 1.5 用户活跃度分布
--     桶名前缀加数字是为了 ORDER BY 按次数排序而非字典序
-- ------------------------------------------------------------
WITH u AS (
  SELECT user_id, COUNT(*) AS acts, COUNT(DISTINCT dt) AS active_days
  FROM ub
  GROUP BY user_id
)
SELECT CASE WHEN acts<=5   THEN '01_1-5次'
            WHEN acts<=20  THEN '02_6-20次'
            WHEN acts<=50  THEN '03_21-50次'
            WHEN acts<=100 THEN '04_51-100次'
            ELSE '05_100次以上' END AS act_bucket,
       COUNT(*) AS users,
       ROUND(100*COUNT(*)/(SELECT COUNT(*) FROM u), 2) AS user_pct,
       ROUND(AVG(active_days), 2) AS avg_active_days
FROM u
GROUP BY act_bucket
ORDER BY act_bucket;

-- ------------------------------------------------------------
-- 1.6 活跃天数 × 购买行为（交叉验证：越活跃购买率越高）
-- ------------------------------------------------------------
WITH u AS (
  SELECT user_id,
         COUNT(DISTINCT dt) AS active_days,
         SUM(behavior_type='buy') AS n_buy
  FROM ub
  GROUP BY user_id
)
SELECT active_days,
       COUNT(*) AS users,
       ROUND(AVG(n_buy), 2) AS avg_buy_times,
       ROUND(100*SUM(n_buy>0)/COUNT(*), 2) AS buy_user_pct
FROM u
GROUP BY active_days
ORDER BY active_days;
