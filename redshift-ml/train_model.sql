CREATE MODEL stockout_model
FROM sales_features
TARGET daily_sales
FUNCTION predict_stockouts
SETTINGS (
  model_type = 'xgboost',
  max_runtime = 3600  -- 1 hour max training
);

-- Check training status
SELECT * FROM svv_ml_model_info;