-- ============================================================
-- 02_funnel.sql  模块二：转化漏斗（三层口径）
--
-- 【核心】漏斗有三种口径
--   A 行为量漏斗   —— 只看量级，分子分母不是同一批人
--   B 用户级漏斗   —— 多少用户走完了流程
--   C 用户-商品路径
-- ============================================================
USE user_behavior;

-- ------------------------------------------------------------
-- 口径 A：行为量漏斗（最粗）
-- ------------------------------------------------------------
SELECT COUNT(*)                AS actions_all,
       SUM(behavior_type='pv')  AS n_pv,
       SUM(behavior_type='fav') AS n_fav,
       SUM(behavior_type='cart') AS n_cart,
       SUM(behavior_type='buy') AS n_buy,
       ROUND(100*SUM(behavior_type='fav')  /NULLIF(SUM(behavior_type='pv'),0),3) AS fav_per_pv,
       ROUND(100*SUM(behavior_type='cart')/NULLIF(SUM(behavior_type='pv'),0),3) AS cart_per_pv,
       ROUND(100*SUM(behavior_type='buy')  /NULLIF(SUM(behavior_type='pv'),0),3) AS buy_per_pv
FROM ub;

-- ------------------------------------------------------------
-- 口径 B：用户级漏斗（推荐主口径）
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_funnel_user AS
SELECT COUNT(DISTINCT user_id) AS u_all,
       COUNT(DISTINCT CASE WHEN behavior_type='pv'   THEN user_id END) AS u_pv,
       COUNT(DISTINCT CASE WHEN behavior_type='fav'  THEN user_id END) AS u_fav,
       COUNT(DISTINCT CASE WHEN behavior_type='cart' THEN user_id END) AS u_cart,
       COUNT(DISTINCT CASE WHEN behavior_type='buy'  THEN user_id END) AS u_buy
FROM ub;

SELECT u_all, u_pv, u_fav, u_cart, u_buy,
       ROUND(100*u_pv  /NULLIF(u_all, 0),2) AS all_to_pv_pct,
       ROUND(100*u_cart/NULLIF(u_pv,  0),2) AS pv_to_cart_pct,
       ROUND(100*u_buy /NULLIF(u_pv,  0),2) AS pv_to_buy_pct,
       ROUND(100*u_buy /NULLIF(u_cart,0),2) AS cart_to_buy_pct
FROM v_funnel_user;

-- ------------------------------------------------------------
-- 口径 C：用户-商品路径漏斗（最严格）
--   粒度 = 同一个用户 × 同一个商品，判断是否发生过四种行为
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ub_pair;
CREATE TABLE ub_pair (
  user_id       BIGINT NOT NULL,
  item_id       BIGINT NOT NULL,
  has_pv        TINYINT,
  has_fav       TINYINT,
  has_cart      TINYINT,
  has_buy       TINYINT,
  first_pv_ts   BIGINT,
  first_cart_ts BIGINT,
  first_buy_ts  BIGINT,
  PRIMARY KEY (user_id, item_id)
) ENGINE=InnoDB COMMENT='用户-商品行为路径宽表';

INSERT INTO ub_pair
SELECT user_id, item_id,
       MAX(behavior_type='pv'),
       MAX(behavior_type='fav'),
       MAX(behavior_type='cart'),
       MAX(behavior_type='buy'),
       MIN(CASE WHEN behavior_type='pv'   THEN ts END),
       MIN(CASE WHEN behavior_type='cart' THEN ts END),
       MIN(CASE WHEN behavior_type='buy'  THEN ts END)
FROM ub
GROUP BY user_id, item_id;

CREATE INDEX idx_pair_cart ON ub_pair (has_cart);
CREATE INDEX idx_pair_buy  ON ub_pair (has_buy);

-- C-1 浏览 → 后续行为转化率
SELECT SUM(has_pv)              AS pv_pairs,
       SUM(has_pv AND has_fav)  AS pv_fav_pairs,
       SUM(has_pv AND has_cart) AS pv_cart_pairs,
       SUM(has_pv AND has_buy)  AS pv_buy_pairs,
       ROUND(100*SUM(has_pv AND has_fav) /NULLIF(SUM(has_pv),0),3) AS pv_to_fav_pct,
       ROUND(100*SUM(has_pv AND has_cart)/NULLIF(SUM(has_pv),0),3) AS pv_to_cart_pct,
       ROUND(100*SUM(has_pv AND has_buy) /NULLIF(SUM(has_pv),0),3) AS pv_to_buy_pct
FROM ub_pair;

-- C-2 加购/收藏 → 购买（定位流失最严重环节）
SELECT SUM(has_cart)                          AS cart_pairs,
       SUM(has_cart AND has_buy)              AS cart_to_buy_pairs,
       ROUND(100*SUM(has_cart AND has_buy)/NULLIF(SUM(has_cart),0),3) AS cart_to_buy_pct,
       SUM(has_fav)                           AS fav_pairs,
       SUM(has_fav AND has_buy)               AS fav_to_buy_pairs,
       ROUND(100*SUM(has_fav AND has_buy)/NULLIF(SUM(has_fav),0),3)   AS fav_to_buy_pct
FROM ub_pair;

-- C-3 加购到支付的耗时（业务价值高：可支撑"加购后X小时推送"建议）
SELECT COUNT(*) AS completed_pairs,
       ROUND(AVG((first_buy_ts - first_cart_ts)/3600), 2) AS avg_hours_cart_to_buy,
       ROUND(AVG((first_buy_ts - first_pv_ts)/3600), 2)   AS avg_hours_pv_to_buy,
       ROUND(MIN((first_buy_ts - first_cart_ts)/3600), 2) AS min_hours_cart_to_buy,
       ROUND(MAX((first_buy_ts - first_cart_ts)/3600), 2) AS max_hours_cart_to_buy
FROM ub_pair
WHERE has_cart=1 AND has_buy=1 AND first_buy_ts >= first_cart_ts;

-- C-4 加购未购买的存量商机
SELECT SUM(has_cart=1 AND (has_buy IS NULL OR has_buy=0)) AS cart_no_buy_pairs,
       SUM(has_cart=1) AS cart_pairs,
       ROUND(100*SUM(has_cart=1 AND (has_buy IS NULL OR has_buy=0))
             /NULLIF(SUM(has_cart=1),0),2) AS lost_pct
FROM ub_pair;
