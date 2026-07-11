import json
import os

import boto3
import psycopg2

REDSHIFT_HOST = os.environ["REDSHIFT_HOST"]
REDSHIFT_DB = os.environ["REDSHIFT_DB"]
REDSHIFT_SECRET_ARN = os.environ["REDSHIFT_SECRET_ARN"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

secrets_client = boto3.client("secretsmanager")
sns = boto3.client("sns")


def get_redshift_credentials():
    secret = secrets_client.get_secret_value(SecretId=REDSHIFT_SECRET_ARN)
    payload = json.loads(secret["SecretString"])
    return payload["username"], payload["password"]


def lambda_handler(event, context):
    username, password = get_redshift_credentials()

    conn = psycopg2.connect(
        host=REDSHIFT_HOST,
        dbname=REDSHIFT_DB,
        user=username,
        password=password,
        port=5439,
    )

    alerts_sent = 0
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT product_id, sale_date, predicted_demand, daily_sales
            FROM stockout_predictions
            WHERE predicted_demand > daily_sales * 1.5
            AND sale_date = CURRENT_DATE + 1
            """
        )

        for product_id, sale_date, predicted_demand, daily_sales in cur.fetchall():
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=f"Stockout risk: product {product_id}",
                Message=(
                    f"Stockout risk for product {product_id} on {sale_date}. "
                    f"Predicted demand {predicted_demand} vs. current daily sales {daily_sales}."
                ),
            )
            alerts_sent += 1

        cur.close()
    finally:
        conn.close()

    return {"statusCode": 200, "alerts_sent": alerts_sent}
