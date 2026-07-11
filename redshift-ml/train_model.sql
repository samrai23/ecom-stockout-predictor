-- Explicit predictor list (product_id, sale_date, daily_orders, avg_price)
-- so predict_stockouts()'s signature matches how it's called in
-- predict_stockouts.sql. Training FROM sales_features directly would pull
-- in rolling_7day_avg_sales/stockout_risk_flag as extra predictors too.
CREATE MODEL stockout_model
FROM (
  SELECT product_id, sale_date, daily_orders, avg_price, daily_sales
  FROM sales_features
)
TARGET daily_sales
FUNCTION predict_stockouts
SETTINGS (
  model_type = 'xgboost',
  max_runtime = 3600  -- 1 hour max training
);

-- Check training status
SELECT * FROM svv_ml_model_info;