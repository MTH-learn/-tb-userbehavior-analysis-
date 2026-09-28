-- ============================================================
-- 05_category.sql  模块五：类目分析 + 二八验证
-- 类目分析、长尾分布、帕累托、集中度
--
--  数据只有 category_id 数字编号，没有类目名称，
-- ============================================================
USE user_behavior;

-- ------------------------------------------------------------
-- 5.1 类目统计表
-- ------------------------------------------------------------
DROP TABLE IF EXISTS cat_stat;
CREATE TABLE cat_stat AS
SELECT category_id,
       SUM(behavior_type='pv')   AS pv,
       SUM(behavior_type='cart') AS cart,
       SUM(behavior_type='buy')  AS buy,
       COUNT(DISTINCT CASE WHEN behavior_type='pv'  THEN user_id END) AS uv,
       COUNT(DISTINCT CASE WHEN behavior_type='buy' THEN user_id END) AS buyer_cnt,
       ROUND(100*SUM(behavior_type='buy')
             /NULLIF(SUM(behavior_type='pv'),0),4) AS buy_per_pv_pct
FROM ub
GROUP BY category_id;

CREATE INDEX idx_cat_pv  ON cat_stat (pv);
CREATE INDEX idx_cat_buy ON cat_stat (buy);

-- 类目规模概览
SELECT COUNT(*) AS n_cat,
       SUM(pv=0) AS cat_no_pv,
       ROUND(AVG(pv),1) AS avg_pv_per_cat,
       MAX(pv) AS max_pv
FROM cat_stat;

-- ------------------------------------------------------------
-- 5.2 Top 20 类目
-- ------------------------------------------------------------
-- 流量头部
SELECT * FROM cat_stat ORDER BY pv DESC LIMIT 20;

-- 购买头部
SELECT * FROM cat_stat ORDER BY buy DESC LIMIT 20;

-- 高流量 + 高转化（潜在蓝海）
SELECT * FROM cat_stat
WHERE pv>=5000 AND buy_per_pv_pct IS NOT NULL
ORDER BY buy_per_pv_pct DESC
LIMIT 20;

-- 高流量 + 低转化
SELECT * FROM cat_stat
WHERE pv>=50000 AND buy_per_pv_pct IS NOT NULL
ORDER BY buy_per_pv_pct ASC
LIMIT 20;

-- ------------------------------------------------------------
-- 5.3 二八分布验证
-- ------------------------------------------------------------
WITH r AS (
  SELECT category_id, pv,
         ROW_NUMBER() OVER (ORDER BY pv DESC) AS rn,
         COUNT(*) OVER ()      AS n_cat,
         SUM(pv)  OVER ()      AS total_pv,
         SUM(pv)  OVER (ORDER BY pv DESC
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_pv
  FROM cat_stat
)
SELECT COUNT(*)                                              AS n_cat_total,
       SUM(cum_pv <= 0.8*total_pv)                           AS cats_covering_80pct,
       ROUND(100*SUM(cum_pv <= 0.8*total_pv)/COUNT(*),2)     AS cat_share_pct
FROM r;

-- ------------------------------------------------------------
-- 5.4 帕累托曲线数据（前 50 类目）
-- ------------------------------------------------------------
WITH r AS (
  SELECT category_id, pv,
         ROW_NUMBER() OVER (ORDER BY pv DESC) AS rn,
         SUM(pv) OVER () AS total_pv,
         SUM(pv) OVER (ORDER BY pv DESC
                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_pv
  FROM cat_stat
)
SELECT rn, category_id, pv,
       ROUND(100*pv/total_pv,3)     AS pv_pct,
       ROUND(100*cum_pv/total_pv,2) AS cum_pct
FROM r
WHERE rn<=50
ORDER BY rn;

-- ------------------------------------------------------------
-- 5.5 商品级头部 Top 20
-- ------------------------------------------------------------
SELECT item_id,
       COUNT(*)                                          AS pv,
       SUM(behavior_type='buy')                          AS buy,
       COUNT(DISTINCT CASE WHEN behavior_type='pv' THEN user_id END) AS uv,
       ROUND(100*SUM(behavior_type='buy')
             /NULLIF(SUM(behavior_type='pv'),0),4)   AS buy_per_pv_pct
FROM ub
GROUP BY item_id
ORDER BY pv DESC
LIMIT 20;
