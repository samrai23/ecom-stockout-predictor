variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev/stage/prod)"
  type        = string
  default     = "dev"
}

variable "glue_script_path" {
  description = "Local path to Glue PySpark scripts"
  type        = string
  default     = "../glue-etl/"
}

variable "kinesis_shard_count" {
  description = "Number of shards for Kinesis stream"
  type        = number
  default     = 1
}

variable "redshift_base_capacity" {
  description = "Base RPU capacity for Redshift Serverless"
  type        = number
  default     = 8
}

variable "glue_worker_count" {
  description = "Number of workers for Glue job"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "ecom-analytics"
    ManagedBy   = "Terraform"
    Environment = "dev"
  }
}