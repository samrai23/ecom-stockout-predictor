terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# S3 Bucket for Glue scripts and temp data
resource "aws_s3_bucket" "ecom_glue_temp" {
  bucket = "ecom-glue-temp"
  force_destroy = true
}

resource "aws_s3_bucket_lifecycle_configuration" "glue_temp_cleanup" {
  bucket = aws_s3_bucket.ecom_glue_temp.id

  rule {
    id     = "auto-cleanup"
    status = "Enabled"

    expiration {
      days = 7
    }
  }
}

# Kinesis Stream for real-time sales data
resource "aws_kinesis_stream" "sales_stream" {
  name             = "ecom-sales-stream"
  shard_count      = 1
  retention_period = 24 # hours
}

# IAM Role for Glue
resource "aws_iam_role" "glue_role" {
  name = "GlueKinesisRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_kinesis" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonKinesisFullAccess"
}

resource "aws_iam_role_policy_attachment" "glue_s3" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Glue Job
resource "aws_glue_job" "sales_cleaning" {
  name         = "ecom-sales-cleaning"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"

  command {
    script_location = "s3://${aws_s3_bucket.ecom_glue_temp.bucket}/scripts/sales_cleaning.py"
    python_version  = "3"
  }

  default_arguments = {
    "--TempDir"             = "s3://${aws_s3_bucket.ecom_glue_temp.bucket}/temp/"
    "--job-bookmark-option" = "job-bookmark-enable"
    "--job-language"        = "python"
  }

  number_of_workers = 2
  worker_type       = "G.1X"
}

# Redshift Serverless
resource "aws_redshiftserverless_namespace" "ecom" {
  namespace_name = "ecom-namespace"
  db_name        = "ecom_db"
}

resource "aws_redshiftserverless_workgroup" "analytics" {
  workgroup_name = "ecom-analytics-wg"
  namespace_name = aws_redshiftserverless_namespace.ecom.namespace_name
  base_capacity  = 8 # RPUs

  config_parameter {
    parameter_key   = "enable_user_activity_logging"
    parameter_value = "true"
  }
}

# Lambda Alert Function
resource "aws_lambda_function" "stockout_alert" {
  function_name = "StockoutAlert"
  handler       = "stockout_alert.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_exec.arn

  s3_bucket = aws_s3_bucket.ecom_glue_temp.bucket
  s3_key    = "lambda-alerts.zip"

  environment {
    variables = {
      REDSHIFT_HOST     = aws_redshiftserverless_workgroup.analytics.endpoint[0].address
      REDSHIFT_DB       = aws_redshiftserverless_namespace.ecom.db_name
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "LambdaRedshiftAlertRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Outputs
output "kinesis_stream_name" {
  value = aws_kinesis_stream.sales_stream.name
}

output "redshift_endpoint" {
  value = aws_redshiftserverless_workgroup.analytics.endpoint[0].address
}

output "glue_job_name" {
  value = aws_glue_job.sales_cleaning.name
}