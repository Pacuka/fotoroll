#!/usr/bin/env bash
# Downloads the shared Immich translations (the same i18n/*.json files the web
# and mobile clients use) for a given server version into assets/i18n/.
#   tool/update_translations.sh v3.3.3
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${1:-v3.3.3}"
DEST=assets/i18n
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -sSfL "https://api.github.com/repos/immich-app/immich/contents/i18n?ref=$TAG" -o "$TMP/list.json"
python3 -I - "$TMP/list.json" > "$TMP/names" <<'PY'
import json, sys
for e in json.load(open(sys.argv[1])):
    if e["name"].endswith(".json"):
        print(e["name"])
PY

mkdir -p "$TMP/out"
while read -r name; do
  curl -sSfL "https://raw.githubusercontent.com/immich-app/immich/$TAG/i18n/$name" -o "$TMP/out/$name"
  python3 -I -c "import json,sys; json.load(open(sys.argv[1]))" "$TMP/out/$name"
done < "$TMP/names"

rm -f "$DEST"/*.json
cp "$TMP"/out/*.json "$DEST"/
echo "$TAG" > "$DEST/VERSION"
echo "Updated $(ls "$DEST"/*.json | wc -l) translations from immich-app/immich@$TAG"
