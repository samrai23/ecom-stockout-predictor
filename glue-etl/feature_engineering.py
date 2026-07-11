import sys
from awsglue.utils import getResolvedOptions
from awsglue.dynamicframe import DynamicFrame
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.window import Window

args = getResolvedOptions(sys.argv, ["JOB_NAME"])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

# Read cleaned data written by sales_cleaning.py
cleaned_df = glueContext.create_dynamic_frame.from_options(
    "s3",
    {"paths": ["s3://ecom-glue-temp/cleaned_data/"], "recurse": True},
    format="parquet",
).toDF()

# Daily grain per product: this is what train_model.sql / predict_stockouts.sql
# expect in the `sales_features` Redshift table (product_id, sale_date,
# daily_sales, daily_orders, avg_price).
daily_df = cleaned_df.groupBy("product_id", "sale_date").agg(
    F.sum("quantity").alias("daily_sales"),
    F.count("order_id").alias("daily_orders"),
    F.avg("price").alias("avg_price"),
)

# Rolling 7-day average sales per product, used as a leading indicator of
# demand trend (also exposed separately via the ml_features view in
# schema_setup.sql, computed here too so it can be inspected pre-load).
product_window = Window.partitionBy("product_id").orderBy("sale_date").rowsBetween(-6, 0)

featured_df = daily_df.withColumn(
    "rolling_7day_avg_sales", F.avg("daily_sales").over(product_window)
).withColumn(
    # Simple heuristic flag: today's sales are running hot vs. the trailing
    # week, i.e. a candidate for a stockout before the ML model even runs.
    "stockout_risk_flag",
    F.when(F.col("daily_sales") > F.col("rolling_7day_avg_sales") * 1.5, 1).otherwise(0),
)

glueContext.write_dynamic_frame.from_options(
    frame=DynamicFrame.fromDF(featured_df, glueContext, "featured_dynamic_frame"),
    connection_type="s3",
    connection_options={
        "path": "s3://ecom-glue-temp/featured_data/",
        "partitionKeys": ["sale_date"],
    },
    format="parquet",
)

job.commit()
