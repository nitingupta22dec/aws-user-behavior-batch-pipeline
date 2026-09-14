from datetime import datetime

from airflow.sdk import DAG
from airflow.models import Variable
from airflow.providers.amazon.aws.transfers.local_to_s3 import LocalFilesystemToS3Operator
from airflow.providers.amazon.aws.transfers.sql_to_s3 import SqlToS3Operator

RAW_BUCKET = Variable.get("s3_raw_bucket")

with DAG(
    dag_id="user_analytics_extract",
    description="Extract user_purchase (RDS) and movie_review (vendor CSV) into S3 raw zone",
    start_date=datetime(2026, 1, 1),
    schedule=None,  # manually triggered for now; will schedule once the full pipeline exists
    catchup=False,
    tags=["extraction"],
) as dag:

    movie_review_to_s3 = LocalFilesystemToS3Operator(
        task_id="movie_review_to_s3",
        filename="/opt/airflow/data/movie_review.csv",
        dest_key=f"s3://{RAW_BUCKET}/raw/movie_review.csv",
        aws_conn_id=None,
        replace=True,
    )

    user_purchase_to_s3 = SqlToS3Operator(
        task_id="user_purchase_to_s3",
        sql_conn_id="postgres_default",
        query="SELECT * FROM retail.user_purchase",
        s3_bucket=RAW_BUCKET,
        s3_key="raw/user_purchase/user_purchase.csv",
        aws_conn_id=None,
        replace=True,
    )
