#!/bin/sh
set -eu

FLV_DIR="/recordings/flv"
MP4_DIR="/recordings/mp4"
QUIET_SECONDS="${QUIET_SECONDS:-60}"
FLV_MAX_AGE_SECONDS="${FLV_MAX_AGE_SECONDS:-0}"

mkdir -p "$FLV_DIR" "$MP4_DIR"

is_quiet_enough () {
  file="$1"
  now=$(date +%s)
  mtime=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file")
  age=$(( now - mtime ))
  [ "$age" -ge "$QUIET_SECONDS" ]
}

remux_one () {
  src="$1"
  base="$(basename "$src" .flv)"
  dst="${MP4_DIR}/${base}.mp4"
  tmp="${MP4_DIR}/${base}.mp4.tmp"
  lock="${src}.lock"

  [ -f "$dst" ] && return 0
  ( set -o noclobber; : > "$lock" ) 2>/dev/null || return 0

  echo "[remux] $src -> $dst"
  if ffmpeg -hide_banner -loglevel error -y -i "$src" -c copy -movflags faststart "$tmp"; then
    mv "$tmp" "$dst"
    echo "[remux] done: $dst"
    echo "[remux] cleanup: $src (converted to MP4)"
    rm -f "$src"
  else
    echo "[remux] ERROR processing $src" >&2
    rm -f "$tmp"
  fi

  rm -f "$lock"
}

echo "[remux] watching $FLV_DIR -> $MP4_DIR (QUIET_SECONDS=$QUIET_SECONDS)"
echo "[remux] processing chunked recordings - each chunk will be converted individually"
while true; do
  find "$FLV_DIR" -type f -name '*.flv' -print | while read -r f; do
    if is_quiet_enough "$f"; then
      remux_one "$f"
    fi
  done

  sleep 5
done
