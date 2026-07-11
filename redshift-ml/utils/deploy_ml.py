import sys
import time

import boto3

redshift = boto3.client("redshift-data")

WORKGROUP_NAME = "ecom-analytics-wg"
DATABASE = "ecom_db"


def deploy_model(sql_file):
    with open(f"utils/{sql_file}") as f:
        sql = f.read()

    response = redshift.execute_statement(
        WorkgroupName=WORKGROUP_NAME,
        Database=DATABASE,
        Sql=sql,
    )
    statement_id = response["Id"]

    while True:
        status = redshift.describe_statement(Id=statement_id)
        state = status["Status"]
        if state in ("FINISHED", "FAILED", "ABORTED"):
            break
        time.sleep(2)

    if state != "FINISHED":
        raise RuntimeError(f"{sql_file} {state}: {status.get('Error', 'unknown error')}")

    print(f"{sql_file} deployed successfully ({statement_id})")


if __name__ == "__main__":
    files = sys.argv[1:] or [
        "schema_setup.sql",
        "data_validation.sql",
        "model_refresh.sql",
    ]
    for sql_file in files:
        deploy_model(sql_file)
