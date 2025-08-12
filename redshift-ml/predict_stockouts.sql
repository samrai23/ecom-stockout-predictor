-- Create predictions table
CREATE TABLE stockout_predictions AS
SELECT
  product_id,
  sale_date,
  daily_sales,
  predict_stockouts(product_id, sale_date, daily_orders, avg_price) AS predicted_demand
FROM sales_features;

-- Identify high-risk products
SELECT * FROM stockout_predictions
WHERE predicted_demand > daily_sales * 1.5  -- 50% demand surge
ORDER BY predicted_demand DESC;