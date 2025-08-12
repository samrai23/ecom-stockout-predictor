from pyspark.sql import functions as F
from awsglue.dynamicframe import DynamicFrame

# Read cleaned data from S3
cleaned_df = glueContext.create_dynamic_frame.from_options(
    "s3",
    {"path": "s3://ecom-glue-temp-XXX/cleaned_data/"},
    format="parquet"
).toDF()

# Feature engineering: Rolling 7-day sales avg, stockout risk flag
featured_df = cleaned_df.groupBy("product_id").agg(
    F.avg("quantity").alias("avg_daily_sales"),
    F.count("order_id").alias("total_orders")
)

# Write to S3 (new folder)
glueContext.write_dynamic_frame.from_options(
    frame=DynamicFrame.fromDF(featured_df, glueContext, "featured_df"),
    connection_type="s3",
    format="parquet",
    connection_options={"path": "s3://ecom-glue-temp/featured_data/"}
)