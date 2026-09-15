import io
from datetime import datetime

from airflow.sdk import DAG, task
from airflow.models import Variable
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
from airflow.providers.amazon.aws.operators.emr import EmrServerlessStartJobOperator
from airflow.providers.amazon.aws.transfers.local_to_s3 import LocalFilesystemToS3Operator
from airflow.providers.amazon.aws.transfers.sql_to_s3 import SqlToS3Operator

RAW_BUCKET = Variable.get("s3_raw_bucket")
PROCESSED_BUCKET = Variable.get("s3_processed_bucket")
EMR_APPLICATION_ID = Variable.get("emr_application_id")
EMR_JOB_ROLE_ARN = Variable.get("emr_job_role_arn")

with DAG(
    dag_id="user_analytics_extract",
    description="Extract user_purchase (RDS) and movie_review (vendor CSV), classify reviews on EMR Serverless",
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

    classify_reviews = EmrServerlessStartJobOperator(
        task_id="classify_reviews",
        application_id=EMR_APPLICATION_ID,
        execution_role_arn=EMR_JOB_ROLE_ARN,
        job_driver={
            "sparkSubmit": {
                "entryPoint": f"s3://{RAW_BUCKET}/scripts/classify_reviews.py",
                "entryPointArguments": [RAW_BUCKET, PROCESSED_BUCKET],
                "sparkSubmitParameters": (
                    "--conf spark.executor.cores=1 "
                    "--conf spark.executor.memory=2g "
                    "--conf spark.driver.cores=1 "
                    "--conf spark.driver.memory=2g"
                ),
            }
        },
        aws_conn_id=None,
        waiter_delay=15,
        waiter_max_attempts=60,
    )

    @task
    def validate_processed_reviews():
        import pandas as pd
        from cuallee import Check, CheckLevel

        hook = S3Hook(aws_conn_id=None)
        keys = hook.list_keys(bucket_name=PROCESSED_BUCKET, prefix="processed/movie_review/")
        parquet_keys = [k for k in keys if k.endswith(".parquet")]
        if not parquet_keys:
            raise ValueError(
                "No Parquet files found under processed/movie_review/ — did classify_reviews run?"
            )

        frames = []
        for key in parquet_keys:
            obj = hook.get_key(key, bucket_name=PROCESSED_BUCKET)
            frames.append(pd.read_parquet(io.BytesIO(obj.get()["Body"].read())))
        df = pd.concat(frames, ignore_index=True)

        check = Check(CheckLevel.ERROR, "movie_review_quality")
        check.is_complete("cid")
        check.is_complete("positive_review")
        check.is_unique("cid")
        result = check.validate(df)

        failed = result[result["status"] != "PASS"]
        if not failed.empty:
            raise ValueError(f"Data quality checks failed:\n{failed.to_string()}")

    movie_review_to_s3 >> classify_reviews >> validate_processed_reviews()
