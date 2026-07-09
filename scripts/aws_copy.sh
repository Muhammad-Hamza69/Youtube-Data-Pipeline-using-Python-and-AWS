#!/usr/bin/env bash
# One-time historical seed: uploads the Kaggle CSV/JSON dataset from data/
# to the Bronze bucket. Run from the repo root: ./scripts/aws_copy.sh
set -euo pipefail

BUCKET="s3://yt-pipeline-bronze-us-east-1-300617413029"
DATA_DIR="$(dirname "$0")/../data"

for region in ca de fr gb in jp kr mx ru us; do
  region_upper=$(echo "$region" | tr '[:lower:]' '[:upper:]')
  aws s3 cp "$DATA_DIR/${region_upper}videos.csv" "$BUCKET/youtube/raw_statistics/region=$region/"
  aws s3 cp "$DATA_DIR/${region_upper}_category_id.json" "$BUCKET/youtube/raw_statistics_reference_data/region=$region/"
done
