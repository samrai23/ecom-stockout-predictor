-- Check for data drift
SELECT 
  COUNT(CASE WHEN ABS(predicted - actual) > actual * 0.3 THEN 1 END) * 100.0 / COUNT(*) AS error_rate
FROM predictions_vs_actuals;