-- Base table loaded from the Glue feature-engineering output
-- (s3://ecom-glue-temp/featured_data/), one row per product per day.
CREATE TABLE IF NOT EXISTS sales_features (
  product_id            INTEGER,
  sale_date             DATE,
  daily_sales           INTEGER,
  daily_orders          INTEGER,
  avg_price             DECIMAL(10, 2),
  rolling_7day_avg_sales DECIMAL(10, 2),
  stockout_risk_flag    SMALLINT
);

-- Load the latest Parquet partitions written by feature_engineering.py.
-- IAM_ROLE default relies on the role attached to the Redshift Serverless
-- namespace (see infrastructure/main.tf) having S3 read access.
COPY sales_features
FROM 's3://ecom-glue-temp/featured_data/'
IAM_ROLE default
FORMAT AS PARQUET;

-- Extra derived features (day-of-week seasonality, week-over-week lag)
-- kept as a view so it recomputes automatically as sales_features grows.
CREATE OR REPLACE VIEW ml_features AS
SELECT
  product_id,
  sale_date,
  daily_sales,
  daily_orders,
  avg_price,
  EXTRACT(DOW FROM sale_date) AS day_of_week,
  LAG(daily_sales, 7) OVER (PARTITION BY product_id ORDER BY sale_date) AS last_week_sales
FROM sales_features;

-- Populated by model_refresh.sql / a scheduled job comparing
-- stockout_predictions against the sales that actually landed, so
-- data_validation.sql can track drift over time.
CREATE TABLE IF NOT EXISTS predictions_vs_actuals (
  product_id INTEGER,
  sale_date  DATE,
  predicted  DECIMAL(10, 2),
  actual     DECIMAL(10, 2)
);
