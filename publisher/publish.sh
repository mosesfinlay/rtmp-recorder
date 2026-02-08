#!/bin/sh
set -eu

DIR="${RECORDINGS_DIR:-/recordings/mp4}"
INTERVAL="${SYNC_INTERVAL_SECONDS:-30}"
BUCKET="${S3_BUCKET:?missing}"
PREFIX="${S3_PREFIX:?missing}"
REGION="${AWS_REGION:-us-west-2}"

echo "[publisher] sync + cleanup: $DIR -> s3://$BUCKET/$PREFIX (every ${INTERVAL}s)"
while true; do
  aws s3 sync "$DIR" "s3://$BUCKET/$PREFIX" \
    --region "$REGION" \
    --no-progress \
    --only-show-errors

  if [ $? -eq 0 ]; then
    find "$DIR" -type f -name '*.mp4' -print | while read -r f; do
      base="$(basename "$f")"
      if aws s3 ls "s3://$BUCKET/$PREFIX/$base" --region "$REGION" >/dev/null 2>&1; then
        echo "[publisher] cleanup: $f (uploaded to S3)"
        rm -f "$f" || true
      fi
    done
  fi

  sleep "$INTERVAL"
done
