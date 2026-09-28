-- ============================================================
-- 03_rfm.sql  模块三：RFM 用户分层
--
-- 本数据集没有金额，M 用行为加权分做代理指标：
--         pv=1 / fav=3 / cart=4 / buy=5
-- ============================================================
USE user_behavior;

-- 3.1 RFM 基础表
DROP TABLE IF EXISTS rfm_base;
CREATE TABLE rfm_base AS
SELECT user_id,
       DATEDIFF((SELECT MAX(dt) FROM ub), MAX(dt)) AS r_days,
       COUNT(DISTINCT dt) AS f_active_days,
       COUNT(*)           AS f_acts,
       SUM(behavior_type='buy') AS n_buy,
       SUM(CASE behavior_type
             WHEN 'pv'   THEN 1
             WHEN 'fav'  THEN 3
             WHEN 'cart' THEN 4
             WHEN 'buy'  THEN 5
             ELSE 0 END) AS m_proxy
FROM ub
GROUP BY user_id;

CREATE INDEX idx_rfm_user ON rfm_base (user_id);

-- 3.2 五分位打分（★ R 是距今天数，越小越好，所以 DESC 排）
DROP TABLE IF EXISTS rfm_score;
CREATE TABLE rfm_score AS
SELECT user_id, r_days, f_acts, f_active_days, m_proxy, n_buy,
       NTILE(5) OVER (ORDER BY r_days  DESC) AS r_s,
       NTILE(5) OVER (ORDER BY f_acts  ASC)  AS f_s,
       NTILE(5) OVER (ORDER BY m_proxy ASC)  AS m_s
FROM rfm_base;

CREATE INDEX idx_rfm_user2 ON rfm_score (user_id);

-- 打分均匀性校验
SELECT r_s, COUNT(*) AS users FROM rfm_score GROUP BY r_s ORDER BY r_s;
SELECT f_s, COUNT(*) AS users FROM rfm_score GROUP BY f_s ORDER BY f_s;
SELECT m_s, COUNT(*) AS users FROM rfm_score GROUP BY m_s ORDER BY m_s;

-- 3.3 八类客户分层
SELECT CASE
         WHEN r_s>=4 AND f_s>=4 AND m_s>=4 THEN '1_重要价值客户'
         WHEN r_s>=4 AND f_s<4  AND m_s>=4 THEN '2_重要发展客户'
         WHEN r_s<4  AND f_s>=4 AND m_s>=4 THEN '3_重要保持客户'
         WHEN r_s<4  AND f_s<4  AND m_s>=4 THEN '4_重要挽留客户'
         WHEN r_s>=4 AND f_s>=4 AND m_s<4  THEN '5_一般价值客户'
         WHEN r_s>=4 AND f_s<4  AND m_s<4  THEN '6_一般发展客户'
         WHEN r_s<4  AND f_s>=4 AND m_s<4  THEN '7_一般保持客户'
         ELSE                                  '8_一般挽留客户' END AS segment,
       COUNT(*) AS users,
       ROUND(100*COUNT(*)/(SELECT COUNT(*) FROM rfm_score),2) AS user_pct,
       ROUND(AVG(r_days),1)      AS avg_r_days,
       ROUND(AVG(f_acts),1)      AS avg_f_acts,
       ROUND(AVG(m_proxy),1)     AS avg_m_proxy,
       ROUND(AVG(n_buy),2)       AS avg_buy_times
FROM rfm_score
GROUP BY segment
ORDER BY segment;

-- 3.4 简化三类
SELECT CASE
         WHEN r_s>=4 AND f_s>=4 THEN '1_高价值活跃'
         WHEN r_s>=4 AND f_s<4  THEN '2_高潜低活跃'
         ELSE                       '3_流失风险' END AS seg_simple,
       COUNT(*) AS users,
       ROUND(100*COUNT(*)/(SELECT COUNT(*) FROM rfm_score),2) AS pct,
       ROUND(AVG(n_buy),2) AS avg_buy,
       ROUND(AVG(r_days),1) AS avg_r_days
FROM rfm_score
GROUP BY seg_simple
ORDER BY seg_simple;
