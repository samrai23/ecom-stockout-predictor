CREATE OR REPLACE MODEL stockout_model_v2
FROM ml_features
TARGET daily_sales
FUNCTION predict_stockouts_v2
SETTINGS (
  model_type = 'xgboost',
  max_runtime = 3600
);