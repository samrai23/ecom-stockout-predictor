import boto3
redshift = boto3.client('redshift-data')
def deploy_model(sql_file):
    with open(f'utils/{sql_file}') as f:
        redshift.execute_statement(
            ClusterIdentifier='ecom-analytics',
            Database='dev',
            Sql=f.read()
        )