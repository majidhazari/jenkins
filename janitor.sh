#!/bin/sh
set -eu

CAP_BYTES="${CAP_BYTES:-32212254720}"  # default 30GB
PRUNE_STEP_HOURS="${PRUNE_STEP_HOURS:-168}"
SLEEP_SECONDS="${SLEEP_SECONDS:-3600}"
PROTECT_LABEL="${PROTECT_LABEL:-}"

# Helper: return total Images size (bytes) from docker system df --format json
images_bytes() {
  docker system df --format json \
  | awk -v RS= -v ORS= '
      /"Images":/ {
        match($0, /"Images":[^}]*"Size": *([0-9]+)/, m);
        if (m[1]!="") print m[1];
      }'
}

while :; do
  USED="$(images_bytes || echo 0)"
  echo "[janitor] images used = $USED bytes (cap=$CAP_BYTES)"

  # # 1) If ANY container is running, skip (covers builds and buildx/buildkit workers)
  # if [ -n "$(docker ps -q)" ]; then
  #   echo "[janitor] active containers detected; skipping this cycle"
  #   sleep "$SLEEP_SECONDS"
  #   continue
  # fi

  # 2) Extra safety: if any buildx/buildkit containers are present/running, skip
  if docker ps --format '{{.Names}}' | grep -q 'buildx_buildkit'; then
    echo "[janitor] buildx/buildkit activity detected; skipping"
    sleep "$SLEEP_SECONDS"
    continue
  fi

  # Always keep build cache in check (fast and safe)
  docker builder prune -af --keep-storage 1GB || true

  # If still above cap, progressively prune older unused images
  if [ "$USED" -gt "$CAP_BYTES" ]; then
    STEP="$PRUNE_STEP_HOURS"
    # escalate in steps: 7d → 14d → 21d → ... up to 90d
    while [ "$(images_bytes || echo 0)" -gt "$CAP_BYTES" ] && [ "$STEP" -le 2160 ]; do
      echo "[janitor] over cap, pruning images older than ${STEP}h"
      if [ -n "$PROTECT_LABEL" ]; then
        docker image prune -af --filter "until=${STEP}h" --filter "label!=$PROTECT_LABEL" || true
      else
        docker image prune -af --filter "until=${STEP}h" || true
      fi
      STEP=$((STEP + PRUNE_STEP_HOURS))
    done
  fi

  echo "[janitor] sleeping ${SLEEP_SECONDS}s"
  sleep "$SLEEP_SECONDS"
done
