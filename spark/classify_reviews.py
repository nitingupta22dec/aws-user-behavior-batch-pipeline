"""
Classifies movie reviews as positive/negative and writes the result to the
S3 processed zone as Parquet. Runs on EMR Serverless, submitted by the
user_analytics_extract DAG.

The classifier is a deliberate naive placeholder (a deterministic hash of
the review id, not real sentiment analysis) — the point of this job is the
EMR Serverless submission mechanics, not the ML content. Swapping this for
a genuine keyword/model-based classifier is a natural later iteration.
"""
import sys

from pyspark.sql import SparkSession
from pyspark.sql.functions import col
from pyspark.sql.functions import hash as spark_hash


def main(raw_bucket: str, processed_bucket: str) -> None:
    spark = SparkSession.builder.appName("movie_review_classifier").getOrCreate()

    reviews = (
        spark.read.option("header", True)
        .option("multiLine", True)
        .option("escape", '"')
        .csv(f"s3://{raw_bucket}/raw/movie_review.csv")
    )

    classified = reviews.withColumn(
        "positive_review", (spark_hash(col("cid")) % 2 == 0)
    )

    classified.select("cid", "positive_review").write.mode("overwrite").parquet(
        f"s3://{processed_bucket}/processed/movie_review/"
    )

    spark.stop()


if __name__ == "__main__":
    main(raw_bucket=sys.argv[1], processed_bucket=sys.argv[2])
