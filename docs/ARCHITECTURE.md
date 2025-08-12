# E-Commerce Stockout Predictor Architecture

## Overview
This project predicts product stockouts using real-time sales data, AWS Glue ETL, Redshift ML, and automated alerts.

## flowchart TD
    A[Sales Data Simulator] -->|Stream| B[AWS Kinesis]
    B -->|Trigger| C[AWS Glue ETL]
    C -->|Cleaned & Featured Data| D[S3 Bucket]
    D -->|Load| E[Redshift Serverless]
    E -->|ML Training & Prediction| F[Redshift ML]
    F -->|Query| G[AWS Lambda Alerts]
    G -->|Notify| H[SNS Topic]
    E -->|Dashboard Data| I[AWS QuickSight]

## Components

- **Data Simulator** ([data-simulator/mock_sales.py](data-simulator/mock_sales.py)): Generates synthetic sales data and streams it to AWS Kinesis.
- **AWS Kinesis**: Ingests real-time sales events.
- **AWS Glue ETL** ([glue-etl/sales_cleaning.py](glue-etl/sales_cleaning.py), [glue-etl/feature_engineering.py](glue-etl/feature_engineering.py)): Cleans and transforms sales data, performs feature engineering, and writes results to S3.
- **S3 Buckets**: Store cleaned and featured data for downstream analytics.
- **Redshift Serverless**: Hosts analytics database and ML models.
    - **Schema & Features** ([redshift-ml/utils/schema_setup.sql](redshift-ml/utils/schema_setup.sql))
    - **Model Training** ([redshift-ml/train_model.sql](redshift-ml/train_model.sql))
    - **Prediction** ([redshift-ml/predict_stockouts.sql](redshift-ml/predict_stockouts.sql))
    - **Validation & Refresh** ([redshift-ml/utils/data_validation.sql](redshift-ml/utils/data_validation.sql), [redshift-ml/utils/model_refresh.sql](redshift-ml/utils/model_refresh.sql))
- **Lambda Alerts** ([lambda-alerts/stockout_alerts.py](lambda-alerts/stockout_alerts.py)): Scheduled Lambda function queries Redshift for high-risk products and sends SNS alerts.
- **Dashboard** ([dashboards/stockout-dashboard.json](dashboards/stockout-dashboard.json)): Visualizes sales and predicted demand using AWS QuickSight.

## Infrastructure
- **Terraform** ([infrastructure/main.tf](infrastructure/main.tf), [infrastructure/variables.tf](infrastructure/variables.tf), [infrastructure/outputs.tf](infrastructure/outputs.tf)): Provisions AWS resources (Kinesis, Glue, S3, Redshift, Lambda, IAM).
- **CI/CD** ([.github/workflows/aws-deploy.yml](.github/workflows/aws-deploy.yml)): Automates deployment of ETL scripts, Lambda, and Redshift ML via GitHub Actions.

## Data Flow

1. **Simulated sales data** → Kinesis Stream
2. **Glue ETL** reads from Kinesis → cleans & features data → writes to S3
3. **Redshift ML** ingests featured data → trains model → predicts stockouts
4. **Lambda** queries predictions → sends alerts for high-risk products
5. **Dashboard** visualizes predictions and risk

## Security & Configuration

- IAM roles for Glue and Lambda
- Secrets Manager for Redshift credentials
- Environment variables for deployment flexibility
