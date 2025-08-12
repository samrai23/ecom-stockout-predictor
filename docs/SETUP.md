# Setup Guide

## Prerequisites

- AWS account with permissions for Kinesis, Glue, S3, Redshift, Lambda, IAM, SNS
- Terraform >= 1.5.0
- Python 3.9+
- GitHub Actions (for CI/CD)

## Terraform Variables

The main configuration is in [variables.tf]:

| Variable               | Description                                 | Default         |
|------------------------|---------------------------------------------|-----------------|
| `aws_region`           | AWS region to deploy resources              | `us-east-1`     |
| `environment`          | Deployment environment (dev/stage/prod)     | `dev`           |
| `glue_script_path`     | Local path to Glue PySpark scripts          | `../glue-etl/`  |
| `kinesis_shard_count`  | Number of shards for Kinesis stream         | `1`             |
| `redshift_base_capacity` | Base RPU capacity for Redshift Serverless | `8`             |
| `glue_worker_count`    | Number of workers for Glue job              | `2`             |
| `tags`                 | Common tags for all resources               | See file        |

You can customize these in `terraform.tfvars` or via CLI.

## Steps

1. **Clone the Repository**
    ```sh
    git clone https://github.com/samrai23/ecom-stockout-predictor.git
    cd ecom-stockout-predictor
    ```

2. **Provision AWS Infrastructure**
    ```sh
    cd infrastructure
    terraform init
    terraform apply
    ```

3. **Deploy ETL and Lambda**
    - Manual: Upload scripts to S3, zip and upload Lambda code.
    - Automated: Push to `main` to trigger GitHub Actions.

4. **Configure Redshift ML**
    - Run SQL scripts in Redshift Query Editor.

5. **Simulate Sales Data**
    ```sh
    cd data-simulator
    pip install -r requirements.txt
    python mock_sales.py
    ```

6. **Monitor & Visualize**
    - Alerts via SNS.
    - Dashboard via QuickSight.

## Troubleshooting

- Check CloudWatch logs for errors.
- Ensure IAM roles and S3 bucket names match Terraform outputs.
