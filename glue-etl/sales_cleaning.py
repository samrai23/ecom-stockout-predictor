import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.dynamicframe import DynamicFrame
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F

args = getResolvedOptions(sys.argv, ["JOB_NAME"])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

# Source: Kinesis is a streaming source, so this job must run as a Glue
# streaming ETL job (job type = "Streaming ETL job" / worker uses
# forEachBatch, not a single batch read).
source_data = glueContext.create_data_frame.from_options(
    connection_type="kinesis",
    connection_options={
        "typeOfData": "kinesis",
        "streamARN": "arn:aws:kinesis:us-east-1:183900808320:stream/ecom-sales-stream",
        "classification": "json",
        "startingPosition": "TRIM_HORIZON",
        "inferSchema": "true",
    },
    transformation_ctx="source_data",
)


def process_batch(data_frame, batch_id):
    if data_frame.count() == 0:
        return

    # Drop duplicate orders (Kinesis has at-least-once delivery) and
    # bad records (missing ids, non-positive quantity/price).
    cleaned_df = (
        data_frame.dropDuplicates(["order_id"])
        .filter(
            F.col("order_id").isNotNull()
            & F.col("product_id").isNotNull()
            & (F.col("quantity") > 0)
            & (F.col("price") > 0)
        )
        # Derive a plain sale_date from the event timestamp so downstream
        # jobs can group sales by day.
        .withColumn("sale_date", F.to_date("timestamp"))
    )

    cleaned_dynamic_frame = DynamicFrame.fromDF(cleaned_df, glueContext, "cleaned_dynamic_frame")

    glueContext.write_dynamic_frame.from_options(
        frame=cleaned_dynamic_frame,
        connection_type="s3",
        connection_options={
            "path": "s3://ecom-glue-temp/cleaned_data/",
            "partitionKeys": ["sale_date"],
        },
        format="parquet",
        transformation_ctx=f"write_cleaned_{batch_id}",
    )


glueContext.forEachBatch(
    frame=source_data,
    batch_function=process_batch,
    options={
        "windowSize": "100 seconds",
        "checkpointLocation": "s3://ecom-glue-temp/checkpoints/sales_cleaning/",
    },
)

job.commit()
