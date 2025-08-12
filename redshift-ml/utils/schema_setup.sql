-- Example: Feature engineering view
CREATE OR REPLACE VIEW ml_features AS
SELECT 
  product_id,
  EXTRACT(DOW FROM sale_date) AS day_of_week,
  daily_sales,
  LAG(daily_sales, 7) OVER (PARTITION BY product_id ORDER BY sale_date) AS last_week_sales
FROM sales_features;