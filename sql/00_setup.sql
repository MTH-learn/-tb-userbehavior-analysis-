CREATE DATABASE IF NOT EXISTS user_behavior DEFAULT CHARACTER SET utf8mb4;
USE user_behavior;

DROP TABLE IF EXISTS ub;
CREATE TABLE ub (
  user_id       BIGINT       NOT NULL COMMENT '用户ID',
  item_id       BIGINT       NOT NULL COMMENT '商品ID',
  category_id   BIGINT       NULL     COMMENT '商品类目ID',
  behavior_type VARCHAR(8)   NOT NULL COMMENT 'pv/fav/cart/buy',
  ts            BIGINT       NOT NULL COMMENT 'Unix秒时间戳',
  dt            DATE         NOT NULL COMMENT '行为日期(北京时间)',
  hh            TINYINT      NOT NULL COMMENT '行为小时 0-23'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
