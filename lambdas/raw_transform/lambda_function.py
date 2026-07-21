"""
Lambda: Staging → Raw (Iceberg)
────────────────────────────────
Invoked by Step Functions after ingestion. Scans the Staging bucket for both
source shapes this pipeline ever produces — live YouTube API JSON responses
and the one-time Kaggle historical CSV/JSON seed — normalizes each into one
stable, uniform schema per dataset, and writes Iceberg tables to Raw via
Athena (awswrangler.athena.to_iceberg), registering/updating the Raw Glue
Catalog as a side effect. No Spark, no crawler: Iceberg tables self-describe.

Shape normalization happens HERE, not in dbt — it's source-system plumbing
(API vs Kaggle column shapes), not business logic. dbt's curated models
assume Raw already has one stable schema per dataset and focus purely on
cleaning/dedup/derivation. Raw is written with mode="append" — it's an
immutable ingestion log; "latest wins" dedup is dbt's job downstream via
incremental merge, not a Raw-layer concern.

Two Iceberg tables, mirroring the pipeline's two datasets:
    raw_statistics       — per-video-per-region-per-day trending stats
    raw_reference_data   — per-category-id-per-region name lookup

Environment Variables:
    S3_BUCKET_STAGING, S3_BUCKET_RAW
    GLUE_DB_RAW, ATHENA_WORKGROUP
    RAW_TABLE_STATS (default raw_statistics), RAW_TABLE_REF (default raw_reference_data)
    SNS_ALERT_TOPIC_ARN
"""

import io
import json
import logging
import os
from datetime import datetime, timezone
from urllib.parse import unquote_plus

import awswrangler as wr
import boto3
import pandas as pd

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client("s3")
sns_client = boto3.client("sns")

STAGING_BUCKET = os.environ["S3_BUCKET_STAGING"]
RAW_BUCKET = os.environ["S3_BUCKET_RAW"]
GLUE_DB = os.environ["GLUE_DB_RAW"]
ATHENA_WORKGROUP = os.environ["ATHENA_WORKGROUP"]
TABLE_STATS = os.environ.get("RAW_TABLE_STATS", "raw_statistics")
TABLE_REF = os.environ.get("RAW_TABLE_REF", "raw_reference_data")
SNS_TOPIC = os.environ.get("SNS_ALERT_TOPIC_ARN", "")

STATS_PREFIX = "youtube/raw_statistics/"
REF_PREFIX = "youtube/raw_statistics_reference_data/"

# Stable Raw contract for statistics — every row, regardless of source, ends
# up with exactly these columns. trending_date_raw is left as the source's
# native string (ISO for API, Kaggle's yy.dd.MM for historical) — dbt's
# curated model parses both formats explicitly, this Lambda does not.
STATS_COLUMNS = [
    "video_id",
    "title",
    "channel_title",
    "category_id",
    "publish_time",
    "trending_date_raw",
    "tags",
    "views",
    "likes",
    "dislikes",
    "comment_count",
    "description",
    "region",
    "source",
    "_ingestion_timestamp",
    "_source_file",
]

REF_COLUMNS = [
    "id",
    "title",
    "region",
    "source",
    "_ingestion_timestamp",
    "_source_file",
]


def _region_from_key(key: str) -> str:
    for part in key.split("/"):
        if part.startswith("region="):
            return part.split("=", 1)[1]
    return "unknown"


def _list_keys(prefix: str) -> list:
    keys = []
    paginator = s3_client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=STAGING_BUCKET, Prefix=prefix):
        for obj in page.get("Contents", []):
            keys.append(obj["Key"])
    return keys


def _read_json(key: str) -> dict:
    body = s3_client.get_object(Bucket=STAGING_BUCKET, Key=key)["Body"].read()
    return json.loads(body.decode("utf-8"))


def _read_csv(key: str) -> pd.DataFrame:
    body = s3_client.get_object(Bucket=STAGING_BUCKET, Key=key)["Body"].read()
    # Kaggle's CSVs are notoriously inconsistent on encoding (latin-1 in a few
    # region files) — errors="replace" keeps a bad byte from failing the whole run.
    return pd.read_csv(io.BytesIO(body), encoding="utf-8", encoding_errors="replace")


def _normalize_api_statistics(key: str) -> pd.DataFrame:
    data = _read_json(key)
    items = data.get("items", [])
    meta = data.get("_pipeline_metadata", {})
    region = meta.get("region") or _region_from_key(key)
    ingestion_ts = meta.get(
        "ingestion_timestamp", datetime.now(timezone.utc).isoformat()
    )

    rows = []
    for item in items:
        snippet = item.get("snippet", {})
        stats = item.get("statistics", {})
        rows.append(
            {
                "video_id": item.get("id"),
                "title": snippet.get("title"),
                "channel_title": snippet.get("channelTitle"),
                "category_id": snippet.get("categoryId"),
                "publish_time": snippet.get("publishedAt"),
                "trending_date_raw": ingestion_ts,
                "tags": (
                    ",".join(snippet.get("tags", [])) if snippet.get("tags") else None
                ),
                "views": stats.get("viewCount"),
                "likes": stats.get("likeCount"),
                "dislikes": None,  # YouTube retired the public dislike count in Dec 2021
                "comment_count": stats.get("commentCount"),
                "description": snippet.get("description"),
                "region": region,
                "source": "youtube_api_v3",
                "_ingestion_timestamp": ingestion_ts,
                "_source_file": key,
            }
        )
    return pd.DataFrame(rows, columns=STATS_COLUMNS)


def _normalize_kaggle_statistics(key: str) -> pd.DataFrame:
    df = _read_csv(key)
    region = _region_from_key(key)
    ingestion_ts = datetime.now(timezone.utc).isoformat()

    out = pd.DataFrame()
    out["video_id"] = df.get("video_id")
    out["title"] = df.get("title")
    out["channel_title"] = df.get("channel_title")
    out["category_id"] = (
        df.get("category_id").astype(str) if "category_id" in df else None
    )
    out["publish_time"] = df.get("publish_time")
    out["trending_date_raw"] = df.get("trending_date")
    out["tags"] = df.get("tags")
    out["views"] = df.get("views")
    out["likes"] = df.get("likes")
    out["dislikes"] = df.get("dislikes")
    out["comment_count"] = df.get("comment_count")
    out["description"] = df.get("description")
    out["region"] = region
    out["source"] = "kaggle_historical"
    out["_ingestion_timestamp"] = ingestion_ts
    out["_source_file"] = key
    return out[STATS_COLUMNS]


def _normalize_reference_data(key: str) -> pd.DataFrame:
    # Kaggle's *_category_id.json files ARE YouTube API videoCategories
    # responses (same {"items": [{"id", "snippet": {"title"}}]} shape) — no
    # source-shape branching needed here, unlike statistics.
    data = _read_json(key)
    items = data.get("items", [])
    region = (data.get("_pipeline_metadata") or {}).get("region") or _region_from_key(
        key
    )
    ingestion_ts = (data.get("_pipeline_metadata") or {}).get(
        "ingestion_timestamp", datetime.now(timezone.utc).isoformat()
    )
    source = "youtube_api_v3" if "_pipeline_metadata" in data else "kaggle_historical"

    rows = [
        {
            "id": item.get("id"),
            "title": item.get("snippet", {}).get("title"),
            "region": region,
            "source": source,
            "_ingestion_timestamp": ingestion_ts,
            "_source_file": key,
        }
        for item in items
    ]
    return pd.DataFrame(rows, columns=REF_COLUMNS)


def _write_iceberg(df: pd.DataFrame, table: str):
    if df.empty:
        logger.info("No rows to write for %s, skipping", table)
        return
    wr.athena.to_iceberg(
        df=df,
        database=GLUE_DB,
        table=table,
        table_location=f"s3://{RAW_BUCKET}/youtube/{table}/",
        temp_path=f"s3://{RAW_BUCKET}/_athena_temp/{table}/",
        workgroup=ATHENA_WORKGROUP,
        partition_cols=["region"],
        mode="append",
        keep_files=False,
    )
    logger.info("Wrote %d rows to %s.%s", len(df), GLUE_DB, table)


def _send_alert(subject: str, message: str):
    if SNS_TOPIC:
        sns_client.publish(TopicArn=SNS_TOPIC, Subject=subject[:100], Message=message)


def lambda_handler(event, context):
    errors = []
    stats_frames = []
    ref_frames = []

    for key in _list_keys(STATS_PREFIX):
        key = unquote_plus(key)
        try:
            if key.endswith(".json"):
                stats_frames.append(_normalize_api_statistics(key))
            elif key.endswith(".csv"):
                stats_frames.append(_normalize_kaggle_statistics(key))
        except Exception as e:
            logger.error("Failed to normalize %s: %s", key, e, exc_info=True)
            errors.append({"key": key, "error": str(e)})

    for key in _list_keys(REF_PREFIX):
        key = unquote_plus(key)
        try:
            if key.endswith(".json"):
                ref_frames.append(_normalize_reference_data(key))
        except Exception as e:
            logger.error("Failed to normalize %s: %s", key, e, exc_info=True)
            errors.append({"key": key, "error": str(e)})

    stats_df = (
        pd.concat(stats_frames, ignore_index=True)
        if stats_frames
        else pd.DataFrame(columns=STATS_COLUMNS)
    )
    ref_df = (
        pd.concat(ref_frames, ignore_index=True)
        if ref_frames
        else pd.DataFrame(columns=REF_COLUMNS)
    )

    _write_iceberg(stats_df, TABLE_STATS)
    _write_iceberg(ref_df, TABLE_REF)

    if errors:
        _send_alert(
            subject="[YT Pipeline] Raw transform had partial failures",
            message=json.dumps(errors, indent=2),
        )

    result = {
        "statusCode": 200,
        "statistics_rows": len(stats_df),
        "reference_rows": len(ref_df),
        "errors": errors,
    }
    if not stats_frames and not ref_frames:
        # Nothing at all found in Staging is a real failure, not a quiet no-op
        # — the ingest step is expected to have written something first.
        raise RuntimeError(
            "No staging files found under raw_statistics/ or raw_statistics_reference_data/"
        )
    return result
