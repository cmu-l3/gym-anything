#!/bin/bash
# pre_task hook for curate_vacation_photo_album on Finder/macOS.
#
# Seeds 24 vacation JPEG stubs in ~/Downloads across three trips:
#   Grand Canyon 2019  (Jul 10–20, 8 files)
#   Pacific Coast 2021 (Apr 01–10, 8 files)
#   New England 2023   (Aug 18–28, 8 files)
# Each file name encodes the date; the "most recent" 3 per trip are determined
# by date order (last 3 in each range = Highlights).
set -eu

echo "=== Setting up curate_vacation_photo_album ==="

DOWNLOADS="$HOME/Downloads"
PICTURES="$HOME/Pictures"

# 1) Clean slate: remove any pre-existing files in ~/Downloads and ~/Pictures/Family Trips
mkdir -p "$DOWNLOADS"
/usr/bin/find "$DOWNLOADS" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
rm -rf "$PICTURES/Family Trips" 2>/dev/null || true
mkdir -p "$PICTURES"

ROOT_AFTER_CLEAN=$(/usr/bin/find "$DOWNLOADS" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
echo "downloads_root_after_cleanup=$ROOT_AFTER_CLEAN (expected: 0)"

# 2) Seed JPEG stubs. A minimal valid-looking body (comment line + name) is
#    sufficient — Finder reads file type from extension. Mtimes set explicitly
#    so chronological sort in Finder matches the embedded date.
seed_jpeg() {
  local name="$1"
  local mtime="$2"   # YYYYMMDDHHMM format for touch -t
  /bin/echo "JPEG stub: $name" > "$DOWNLOADS/$name"
  /usr/bin/touch -t "$mtime" "$DOWNLOADS/$name"
}

# Grand Canyon 2019
seed_jpeg "2019-07-10_IMG_0101.jpg" "201907100900"
seed_jpeg "2019-07-11_IMG_0128.jpg" "201907110900"
seed_jpeg "2019-07-12_IMG_0143.jpg" "201907120900"
seed_jpeg "2019-07-14_IMG_0189.jpg" "201907140900"
seed_jpeg "2019-07-16_IMG_0221.jpg" "201907160900"
seed_jpeg "2019-07-17_IMG_0256.jpg" "201907170900"
seed_jpeg "2019-07-19_IMG_0312.jpg" "201907190900"
seed_jpeg "2019-07-20_IMG_0389.jpg" "201907200900"

# Pacific Coast 2021
seed_jpeg "2021-04-01_IMG_1101.jpg" "202104010900"
seed_jpeg "2021-04-02_IMG_1119.jpg" "202104020900"
seed_jpeg "2021-04-03_IMG_1142.jpg" "202104030900"
seed_jpeg "2021-04-05_IMG_1178.jpg" "202104050900"
seed_jpeg "2021-04-06_IMG_1204.jpg" "202104060900"
seed_jpeg "2021-04-08_IMG_1222.jpg" "202104080900"
seed_jpeg "2021-04-09_IMG_1267.jpg" "202104090900"
seed_jpeg "2021-04-10_IMG_1311.jpg" "202104100900"

# New England 2023
seed_jpeg "2023-08-18_IMG_2101.jpg" "202308180900"
seed_jpeg "2023-08-19_IMG_2118.jpg" "202308190900"
seed_jpeg "2023-08-20_IMG_2134.jpg" "202308200900"
seed_jpeg "2023-08-22_IMG_2167.jpg" "202308220900"
seed_jpeg "2023-08-23_IMG_2194.jpg" "202308230900"
seed_jpeg "2023-08-25_IMG_2227.jpg" "202308250900"
seed_jpeg "2023-08-26_IMG_2271.jpg" "202308260900"
seed_jpeg "2023-08-28_IMG_2316.jpg" "202308280900"

SEED_COUNT=$(/usr/bin/find "$DOWNLOADS" -mindepth 1 -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
echo "seeded_file_count=$SEED_COUNT (expected: 24)"
if [ "${SEED_COUNT:-0}" -lt 24 ]; then
  echo "ERROR: setup failed to seed all 24 files" >&2
  /bin/ls -la "$DOWNLOADS" >&2
  exit 1
fi

# 3) Record task start timestamp
/bin/date +%s > /tmp/task_start_timestamp
echo "task_start_unix=$(cat /tmp/task_start_timestamp)"

# 4) Ensure Finder is running and open Downloads
if ! /usr/bin/pgrep -x Finder >/dev/null 2>&1; then
  /usr/bin/open -a Finder
fi
for i in $(seq 1 15); do
  if /usr/bin/pgrep -x Finder >/dev/null 2>&1; then break; fi
  sleep 1
done

/usr/bin/open "$DOWNLOADS"
sleep 2
osascript -e 'tell application "Finder" to set current view of front window to column view' 2>/dev/null || true
sleep 1

# 5) Start-state screenshot
/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

echo "=== curate_vacation_photo_album setup complete ==="
echo "24 JPEG stubs seeded in ~/Downloads. Agent should organize into ~/Pictures/Family Trips/ with one subfolder per trip, Highlights subfolders, color tags, and Finder comments."
