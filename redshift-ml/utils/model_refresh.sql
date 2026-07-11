-- Same predictor list/signature as train_model.sql (sourced from ml_features
-- instead of sales_features) so predict_stockouts_v2() is a drop-in
-- replacement for predict_stockouts() wherever it's called below.
CREATE OR REPLACE MODEL stockout_model_v2
FROM (
  SELECT product_id, sale_date, daily_orders, avg_price, daily_sales
  FROM ml_features
)
TARGET daily_sales
FUNCTION predict_stockouts_v2
SETTINGS (
  model_type = 'xgboost',
  max_runtime = 3600
);

-- Record how the refreshed model would have performed on data we now know
-- the outcome for, so data_validation.sql can compute a real error rate.
INSERT INTO predictions_vs_actuals (product_id, sale_date, predicted, actual)
SELECT
  product_id,
  sale_date,
  predict_stockouts_v2(product_id, sale_date, daily_orders, avg_price) AS predicted,
  daily_sales AS actual
FROM sales_features
WHERE sale_date = CURRENT_DATE - 1;