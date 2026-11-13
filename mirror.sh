#!/usr/bin/env bash
# Mirror RKE2 / Rancher container images to ghcr.io/alfamecom/rancher-mirror-test.
#
# Source is registry.rancher.com rather than docker.io: it carries the same
# images, allows anonymous pulls, and has no pull rate limit.
#
# Usage: ./mirror.sh [filter]
#   filter  optional substring; only matching images are mirrored

set -uo pipefail

SRC_REGISTRY="${SRC_REGISTRY:-registry.rancher.com}"
DST_PREFIX="${DST_PREFIX:-ghcr.io/alfamecom/rancher-mirror-test}"
LIST="${LIST:-images.txt}"
FILTER="${1:-}"

ok=0; skipped=0; failed=0; total=0
failures=()

while read -r image; do
  [[ -z "$image" || "$image" == \#* ]] && continue
  [[ -n "$FILTER" && "$image" != *"$FILTER"* ]] && continue
  total=$((total + 1))

  src="$SRC_REGISTRY/$image"
  dst="$DST_PREFIX/$image"

  src_digest="$(crane digest "$src" 2>/dev/null)"
  dst_digest="$(crane digest "$dst" 2>/dev/null)"

  if [[ -n "$src_digest" && "$src_digest" == "$dst_digest" ]]; then
    echo "== skip  $image (already mirrored)"
    skipped=$((skipped + 1))
    continue
  fi

  echo "== copy  $image"
  if crane copy "$src" "$dst"; then
    ok=$((ok + 1))
  else
    echo "!! failed $image"
    failed=$((failed + 1))
    failures+=("$image")
  fi
done < "$LIST"

echo
echo "copied=$ok skipped=$skipped failed=$failed total=$total"

if ((failed > 0)); then
  printf 'failed image: %s\n' "${failures[@]}"
  exit 1
fi
