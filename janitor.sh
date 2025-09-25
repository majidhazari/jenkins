#!/bin/sh
set -eu

CAP_GB="${CAP_GB:-30}"
CAP_BYTES=$(( CAP_GB * 1024 * 1024 * 1024 ))
PRUNE_STEP_HOURS="${PRUNE_STEP_HOURS:-168}"
SLEEP_SECONDS="${SLEEP_SECONDS:-3600}"
PROTECT_LABEL="${PROTECT_LABEL:-}"

# Use Buildx prune flags (Buildx v0.17+):
#   --reserved-space     (always keep at least this much cache space free)
#   --min-free-space     (target free space after prune)
# See docs & release notes.  :contentReference[oaicite:0]{index=0}
BUILDX_PRUNE_BASE="docker buildx prune -af"

# Helper: return total Images size (bytes) from docker system df --format json
images_bytes() {
  # Parse docker system df JSON summary → Images.Size (bytes)
  # Works without jq; returns 0 if parse fails.
  out="$(docker system df --format json 2>/dev/null || true)"
  echo "$out" | grep -o '"Images":[^}]*"Size":[[:space:]]*[0-9]\+' \
    | grep -o '[0-9]\+$' || echo 0
}
any_containers_running() {
  docker ps -q | grep -q . && return 0 || return 1
}

buildkit_busy() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'buildx_buildkit' && return 0 || return 1
}

prune_images_until_under_cap() {
  step="$PRUNE_STEP_HOURS"
  while :; do
    used="$(images_bytes)"; used="${used:-0}"
    [ "$used" -le "$CAP_BYTES" ] && break
    echo "[janitor] over cap: used=${used} bytes > cap=${CAP_BYTES}; pruning images older than ${step}h"
    if [ -n "$PROTECT_LABEL" ]; then
      docker image prune -af --filter "until=${step}h" --filter "label!=$PROTECT_LABEL" || true
    else
      docker image prune -af --filter "until=${step}h" || true
    fi
    step=$(( step + PRUNE_STEP_HOURS ))
    [ "$step" -gt 2160 ] && break   # ~90 days ceiling
  done
}

while :; do
  USED="$(images_bytes || echo 0)"
  echo "[janitor] images used = $USED bytes (cap=$CAP_BYTES)"

  
  # Safety guards: skip while builds are active
  # if any_containers_running || buildkit_busy; then
   if buildkit_busy; then
    echo "[janitor] activity detected; skipping prune"
    sleep "$SLEEP_SECONDS"
    continue
  fi

  # Age-based cleanup for *unused* images (adjust 168h as desired)
  if [ -n "$PROTECT_LABEL" ]; then
    docker image prune -af --filter "until=168h" --filter "label!=$PROTECT_LABEL" || true
  else
    docker image prune -af --filter "until=168h" || true
  fi

  # Trim Buildx cache (new flags); keep ~1GB reserved for hot cache
  $BUILDX_PRUNE_BASE --reserved-space 1gb || true
  # (Optionally ensure some free disk overall)
  # $BUILDX_PRUNE_BASE --min-free-space 2gb || true

  # Enforce total image cap
  used="$(images_bytes)"; used="${used:-0}"
  echo "[janitor] images used = ${used} bytes (cap=${CAP_BYTES})"
  [ "$used" -gt "$CAP_BYTES" ] && prune_images_until_under_cap

  echo "[janitor] sleeping ${SLEEP_SECONDS}s"
  sleep "$SLEEP_SECONDS"
done
