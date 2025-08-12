import boto3
from faker import Faker
import json
import random
import time

# Hardcoded configuration (no .env needed)
AWS_REGION = "us-east-1"                  # ← Replace with your region
KINESIS_STREAM_NAME = "ecom-sales-stream" # ← Your Kinesis stream name

fake = Faker()
kinesis = boto3.client('kinesis', region_name=AWS_REGION)

def generate_sale():
    return {
        "order_id": fake.uuid4(),
        "product_id": random.randint(1, 100),
        "quantity": random.randint(1, 5),
        "price": round(random.uniform(10.0, 100.0), 2),
        "timestamp": fake.date_time_this_month().isoformat()
    }

if __name__ == "__main__":
    print(f"Producing data to Kinesis stream: {KINESIS_STREAM_NAME}...")
    try:
        while True:
            sale = generate_sale()
            kinesis.put_record(
                StreamName=KINESIS_STREAM_NAME,
                Data=json.dumps(sale),
                PartitionKey=str(sale["product_id"])
            )
            print(f"Sent record: {sale['order_id']}")
            time.sleep(10)
    except KeyboardInterrupt:
        print("Stopped by user")