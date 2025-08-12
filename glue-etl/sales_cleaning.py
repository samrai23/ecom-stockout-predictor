import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

# Initialize Glue context
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)

# Read from Kinesis
source_df = glueContext.create_data_frame.from_options(
    connection_type="kinesis",
    connection_options={
        "typeOfData": "kinesis",
        "streamARN": "arn:aws:kinesis:us-east-1:183900808320:stream/ecom-sales-stream",
        "classification": "json",
        "startingPosition": "TRIM_HORIZON"
    }
)

# Deduplicate and clean data
cleaned_df = source_df.dropDuplicates(["order_id"])

# Write to S3 in Parquet format (optimized for Redshift)
glueContext.write_dynamic_frame.from_options(
    frame=cleaned_df,
    connection_type="s3",
    connection_options={
        "path": "s3://ecom-glue-temp/cleaned_data/",
        "partitionKeys": []
    },
    format="parquet"
)

job.commit()