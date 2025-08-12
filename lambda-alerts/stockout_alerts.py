import boto3
import psycopg2

def lambda_handler(event, context):
    conn = psycopg2.connect(
        host="your-redshift-endpoint",
        dbname="your_db",
        user="admin",
        password="your_password",
        port=5439
    )
    
    cur = conn.cursor()
    cur.execute("""
        SELECT product_id, sale_date, predicted_demand 
        FROM stockout_predictions
        WHERE predicted_demand > daily_sales * 1.5
        AND sale_date = CURRENT_DATE + 1  -- Tomorrow's prediction
    """)
    
    sns = boto3.client('sns')
    for row in cur.fetchall():
        sns.publish(
            TopicArn="arn:aws:sns:us-east-1:123456789012:stockout-alerts",
            Message=f"Stockout risk: Product {row[0]} on {row[1]}. Predicted demand: {row[2]}"
        )
    
    conn.close()