terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# S3 Bucket for Glue scripts and temp data
resource "aws_s3_bucket" "ecom_glue_temp" {
  bucket        = "ecom-glue-temp"
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_lifecycle_configuration" "glue_temp_cleanup" {
  bucket = aws_s3_bucket.ecom_glue_temp.id

  rule {
    id     = "auto-cleanup"
    status = "Enabled"

    filter {}

    expiration {
      days = 7
    }
  }
}

# Upload the Glue PySpark scripts so the Glue jobs below can reference them.
resource "aws_s3_object" "sales_cleaning_script" {
  bucket = aws_s3_bucket.ecom_glue_temp.bucket
  key    = "scripts/sales_cleaning.py"
  source = "${var.glue_script_path}sales_cleaning.py"
  etag   = filemd5("${var.glue_script_path}sales_cleaning.py")
}

resource "aws_s3_object" "feature_engineering_script" {
  bucket = aws_s3_bucket.ecom_glue_temp.bucket
  key    = "scripts/feature_engineering.py"
  source = "${var.glue_script_path}feature_engineering.py"
  etag   = filemd5("${var.glue_script_path}feature_engineering.py")
}

# Kinesis Stream for real-time sales data
resource "aws_kinesis_stream" "sales_stream" {
  name             = "ecom-sales-stream"
  shard_count      = var.kinesis_shard_count
  retention_period = 24 # hours
  tags             = var.tags
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

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Glue Job: streams from Kinesis, dedupes/cleans, writes Parquet to S3.
# Reading a Kinesis source requires the "gluestreaming" job type.
resource "aws_glue_job" "sales_cleaning" {
  name         = "ecom-sales-cleaning"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"

  command {
    name            = "gluestreaming"
    script_location = "s3://${aws_s3_bucket.ecom_glue_temp.bucket}/${aws_s3_object.sales_cleaning_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--TempDir"             = "s3://${aws_s3_bucket.ecom_glue_temp.bucket}/temp/"
    "--job-bookmark-option" = "job-bookmark-disable"
    "--job-language"        = "python"
  }

  number_of_workers = var.glue_worker_count
  worker_type       = "G.1X"
  tags              = var.tags
}

# Glue Job: batch job that reads cleaned data from S3, computes daily
# aggregates/rolling features, and writes to featured_data/ for Redshift.
resource "aws_glue_job" "feature_engineering" {
  name         = "ecom-feature-engineering"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.ecom_glue_temp.bucket}/${aws_s3_object.feature_engineering_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--TempDir"             = "s3://${aws_s3_bucket.ecom_glue_temp.bucket}/temp/"
    "--job-bookmark-option" = "job-bookmark-enable"
    "--job-language"        = "python"
  }

  number_of_workers = var.glue_worker_count
  worker_type       = "G.1X"
  tags              = var.tags
}

# Redshift Serverless
resource "aws_redshiftserverless_namespace" "ecom" {
  namespace_name      = "ecom-namespace"
  db_name             = "ecom_db"
  admin_username      = "admin"
  admin_user_password = random_password.redshift_admin.result
  iam_roles           = [aws_iam_role.redshift_s3_read.arn]
  tags                = var.tags
}

resource "aws_redshiftserverless_workgroup" "analytics" {
  workgroup_name = "ecom-analytics-wg"
  namespace_name = aws_redshiftserverless_namespace.ecom.namespace_name
  base_capacity  = var.redshift_base_capacity

  config_parameter {
    parameter_key   = "enable_user_activity_logging"
    parameter_value = "true"
  }

  tags = var.tags
}

# IAM role attached to the Redshift namespace so `COPY ... IAM_ROLE default`
# in schema_setup.sql can read the Glue output from S3.
resource "aws_iam_role" "redshift_s3_read" {
  name = "RedshiftServerlessS3ReadRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "redshift.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "redshift_s3_read" {
  role       = aws_iam_role.redshift_s3_read.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# Redshift admin credentials, generated instead of hardcoded and stored in
# Secrets Manager for the Lambda alert function to read at runtime.
resource "random_password" "redshift_admin" {
  length  = 20
  special = false
}

resource "aws_secretsmanager_secret" "redshift_credentials" {
  name = "ecom/redshift/admin-credentials"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "redshift_credentials" {
  secret_id = aws_secretsmanager_secret.redshift_credentials.id
  secret_string = jsonencode({
    username = aws_redshiftserverless_namespace.ecom.admin_username
    password = random_password.redshift_admin.result
  })
}

# SNS Topic for stockout alerts
resource "aws_sns_topic" "stockout_alerts" {
  name = "stockout-alerts"
  tags = var.tags
}

# Lambda Alert Function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../lambda-alerts"
  output_path = "${path.module}/build/lambda-alerts.zip"
  excludes    = ["event.json", "requirements.txt"]
}

resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.ecom_glue_temp.bucket
  key    = "lambda/lambda-alerts.zip"
  source = data.archive_file.lambda_zip.output_path
  etag   = data.archive_file.lambda_zip.output_md5
}

resource "aws_lambda_function" "stockout_alert" {
  function_name = "StockoutAlert"
  handler       = "stockout_alerts.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_exec.arn
  timeout       = 30

  s3_bucket        = aws_s3_bucket.ecom_glue_temp.bucket
  s3_key           = aws_s3_object.lambda_zip.key
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      REDSHIFT_HOST       = aws_redshiftserverless_workgroup.analytics.endpoint[0].address
      REDSHIFT_DB         = aws_redshiftserverless_namespace.ecom.db_name
      REDSHIFT_SECRET_ARN = aws_secretsmanager_secret.redshift_credentials.arn
      SNS_TOPIC_ARN       = aws_sns_topic.stockout_alerts.arn
    }
  }

  tags = var.tags
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

resource "aws_iam_role_policy" "lambda_sns_publish" {
  name = "LambdaSNSPublish"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.stockout_alerts.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_secrets_read" {
  name = "LambdaSecretsRead"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.redshift_credentials.arn
      }
    ]
  })
}

# EventBridge schedule that triggers the Lambda daily to scan for
# tomorrow's high-risk products (matches lambda-alerts/event.json sample).
resource "aws_cloudwatch_event_rule" "daily_stockout_check" {
  name                = "daily-stockout-check"
  schedule_expression = "cron(0 9 * * ? *)" # 09:00 UTC daily
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "daily_stockout_check" {
  rule = aws_cloudwatch_event_rule.daily_stockout_check.name
  arn  = aws_lambda_function.stockout_alert.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stockout_alert.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_stockout_check.arn
}
