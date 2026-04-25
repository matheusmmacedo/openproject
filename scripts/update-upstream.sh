#!/usr/bin/env bash
# Pull latest commits from opf/openproject-docker-compose stable/17 and
# overlay them onto our tree. Different from the Zammad equivalent because
# upstream uses branches (no release tags) — we pin commit SHA instead.
#
# Usage:
#   ./scripts/update-upstream.sh                show diff vs current pinned SHA
#   ./scripts/update-upstream.sh --apply        apply latest stable/17 HEAD

set -euo pipefail

UPSTREAM_REPO="opf/openproject-docker-compose"
UPSTREAM_BRANCH="stable/17"
PINNED="$(tr -d '[:space:]' < UPSTREAM)"

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
  esac
done

echo "Pinned: $PINNED"
TARGET_SHA="$(curl -s "https://api.github.com/repos/$UPSTREAM_REPO/commits/$UPSTREAM_BRANCH" \
  | grep '"sha"' | head -1 | sed -E 's/.*"sha": "([^"]+)".*/\1/' | cut -c1-12)"
echo "Target: $UPSTREAM_BRANCH @ $TARGET_SHA"

if echo "$PINNED" | grep -q "$TARGET_SHA"; then
  echo "Already up-to-date."
  exit 0
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
echo "Fetching tarball ..."
curl -sL "https://github.com/$UPSTREAM_REPO/archive/refs/heads/${UPSTREAM_BRANCH/\//%2F}.tar.gz" \
  -o "$STAGE/src.tgz"
tar -xzf "$STAGE/src.tgz" -C "$STAGE"
SRC="$(ls -d "$STAGE"/openproject-docker-compose-* | head -1)"

FILES=(docker-compose.yml docker-compose.control.yml .env.example)
DIRS=(control proxy)

if [ $APPLY -eq 1 ]; then
  for f in "${FILES[@]}"; do [ -f "$SRC/$f" ] && cp "$SRC/$f" "./$f"; done
  for d in "${DIRS[@]}"; do [ -d "$SRC/$d" ] && rm -rf "./$d" && cp -r "$SRC/$d" "./$d"; done
  [ -f "$SRC/README.md" ] && cp "$SRC/README.md" "./README.upstream.md"
  echo "$UPSTREAM_BRANCH @ $TARGET_SHA" > UPSTREAM
  echo "Applied. Review 'git diff' before committing."
else
  echo
  echo '--- diff (preview) ---'
  for f in "${FILES[@]}"; do [ -f "$SRC/$f" ] && diff -u "./$f" "$SRC/$f" || true; done
  echo
  echo 'Run with --apply to overwrite files.'
fi
