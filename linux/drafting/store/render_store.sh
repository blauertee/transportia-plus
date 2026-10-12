#!/usr/bin/env bash
# Renders the fastlane store screenshots. See README.md beside this file.
#
#   linux/drafting/store/render_store.sh [--out DIR] [--install]
#
# --install copies the result over fastlane's phoneScreenshots.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
out="$repo/build/store"
install=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --install) install=true; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
work="$out/work"
mkdir -p "$work/maps" "$work/data"

# Map backgrounds: name, itinerary, legs to fit, size, padding, max zoom.
# The journey map's own area is 400x756 below its app bar.
export NODE_PATH="${NODE_PATH:-$(npm root -g)}"
maps=(
  "transfer 4 12 400 756 {\"top\":60,\"bottom\":280,\"left\":60,\"right\":60} 17"
  "bike 0 0 400 756 {\"top\":70,\"bottom\":260,\"left\":50,\"right\":50} 16"
)
for entry in "${maps[@]}"; do
  read -r name itinerary focus w h pad zoom <<<"$entry"
  python3 -I "$here/map/mkspec.py" "$here/data/plan.json" "$itinerary" "$focus" \
    "$work/maps/$name.json"
  node "$here/map/shoot.mjs" "$work/maps/$name.json" "$work/maps/$name.png" \
    "$w" "$h" "$pad" "$zoom"
done

# The capture is for a fixed day. Move it so the first trip leaves 21 minutes
# after the render starts ("Depart in 20m"), and pick a time zone whose wall
# clock shows the times London riders would have seen. Widgets read
# DateTime.now(), so this is the only way to pin what they print.
tz="$(python3 -I - "$here/data/plan.json" "$work/data/plan.json" <<'PY'
import datetime as dt, json, re, sys
src, dst = sys.argv[1:3]
raw = open(src).read()
first = json.loads(raw)['itineraries'][0]['startTime']
first = dt.datetime.fromisoformat(first.replace('Z', '+00:00'))
now = dt.datetime.now(dt.timezone.utc).replace(second=0, microsecond=0)
delta = now + dt.timedelta(minutes=22) - first
def shift(m):
    t = dt.datetime.fromisoformat(m.group(0).replace('Z', '+00:00')) + delta
    return t.strftime('%Y-%m-%dT%H:%M:%SZ')
open(dst, 'w').write(
    re.sub(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z', shift, raw))
london = dt.timedelta(hours=1)  # BST, when the capture was taken
minutes = round((london - delta).total_seconds() / 60) % 1440
# POSIX TZ counts west as positive.
print(f'STO-{minutes // 60}:{minutes % 60:02d}')
PY
)"
cp "$here/data/geocode_decathlon.json" "$work/data/"

cd "$repo"
STORE_DATA="$work/data" STORE_MAPS="$work/maps" TZ="$tz" \
  linux/drafting/render.sh --tag store --out "$out" \
  linux/drafting/store/store_draft_test.dart

if $install; then
  dest="$repo/fastlane/metadata/android/en-US/images/phoneScreenshots"
  for i in 1 2 3 4 5 6; do cp "$out/store_$i.png" "$dest/$i.png"; done
  echo "Installed into $dest"
fi
