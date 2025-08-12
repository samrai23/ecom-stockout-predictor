output "kinesis_stream_arn" {
  description = "ARN of the Kinesis data stream for sales data"
  value       = aws_kinesis_stream.sales_stream.arn
}

output "glue_job_arn" {
  description = "ARN of the Glue ETL job"
  value       = aws_glue_job.sales_cleaning.arn
}

output "redshift_serverless_endpoint" {
  description = "Redshift Serverless endpoint for analytics"
  value       = "${aws_redshiftserverless_workgroup.analytics.endpoint[0].address}:${aws_redshiftserverless_workgroup.analytics.endpoint[0].port}"
}

output "lambda_function_name" {
  description = "Name of the stockout alert Lambda function"
  value       = aws_lambda_function.stockout_alert.function_name
}

output "glue_temp_bucket_name" {
  description = "Name of the S3 bucket for Glue temporary files"
  value       = aws_s3_bucket.ecom_glue_temp.bucket
}

output "redshift_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret for Redshift credentials"
  value       = aws_secretsmanager_secret.redshift_credentials.arn
  sensitive   = true
}