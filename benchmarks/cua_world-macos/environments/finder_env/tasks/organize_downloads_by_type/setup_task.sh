#!/bin/bash
# pre_task hook for organize_downloads_by_type on Finder/macOS.
#
# Responsibilities:
#   1. Cleanup: remove ANY pre-existing files/folders in ~/Downloads/ so the
#      task starts from a deterministic empty-Downloads state. This is the
#      "clean slate" anti-pattern #3 (record baseline after cleanup).
#   2. Seed exactly 8 source files at ~/Downloads/<file>. Names and
#      categories are fixed by the task.json description; categorization
#      rule (extension → folder) is also in task.json. We do NOT echo the
#      target folder for each file (anti-pattern #10), only the filenames
#      themselves (which are already in task.json's description anyway).
#   3. Record an authoritative task-start Unix timestamp so export_result.sh
#      can compute freshness deltas.
#   4. Ensure Finder is running and open a window at ~/Downloads so the
#      agent sees the task state on the first observation frame.
set -eu

DOWNLOADS="$HOME/Downloads"

echo "=== Setting up organize_downloads_by_type ==="

# 1) Clean slate. Remove every file and folder in ~/Downloads/ so the task
#    starts with a known-empty parent. Using `find -maxdepth 1 -mindepth 1 -delete`
#    instead of `rm -rf ~/Downloads/*` so dotfiles + hidden state are also wiped.
mkdir -p "$DOWNLOADS"
/usr/bin/find "$DOWNLOADS" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true

# Sanity-check the cleanup
ROOT_COUNT_AFTER_CLEAN=$(/usr/bin/find "$DOWNLOADS" -mindepth 1 -maxdepth 1 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
echo "downloads_root_after_cleanup=$ROOT_COUNT_AFTER_CLEAN (expected: 0)"

# 2) Seed the 8 source files. Each gets a small amount of realistic-looking
#    content so it's not a zero-byte file (which would look broken in Finder).
#    PDF, ZIP, etc. don't need to be VALID — Finder's "Get Info" reads file
#    type from the extension, so plain-text bodies are fine for our purposes.
#    File mtimes are spread over the past 30 days so chronological sort in
#    Finder is also realistic (not all timestamps identical).
seed_file() {
  local name="$1"
  local body="$2"
  local mtime_offset_days="$3"
  /bin/echo "$body" > "$DOWNLOADS/$name"
  # macOS `touch -t YYYYMMDDHHMM` requires explicit timestamp; build it.
  local stamp
  stamp=$(/bin/date -v-"${mtime_offset_days}"d +%Y%m%d%H%M 2>/dev/null || /bin/date +%Y%m%d%H%M)
  /usr/bin/touch -t "$stamp" "$DOWNLOADS/$name"
}

seed_file "reading_list.pdf"     "%PDF-1.4 stub: 2026 reading list — not a real PDF, but the .pdf extension is what matters for the task." 28
seed_file "meeting_notes.txt"    "Meeting notes — 2026-04-12. Action items: organize Downloads folder." 14
seed_file "wallpaper.jpg"        "JPEG stub — desktop wallpaper. Real bytes not required for this task." 7
seed_file "screenshot.png"       "PNG stub — Screen capture 2026-04-30." 3
seed_file "backup.zip"           "ZIP stub — partial backup of project files." 21
seed_file "data.tar.gz"          "tarball stub — exported analytics data, gzipped." 10
seed_file "playlist.m3u"         "#EXTM3U
#EXTINF:217,Track 1
file:///Users/lume/Music/track1.mp3" 5
seed_file "route_planning.gpx"   "<?xml version=\"1.0\"?><gpx><trk><name>Pittsburgh loop</name></trk></gpx>" 18

SEED_COUNT=$(/usr/bin/find "$DOWNLOADS" -mindepth 1 -maxdepth 1 -type f 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
echo "seeded_file_count=$SEED_COUNT (expected: 8)"
if [ "${SEED_COUNT:-0}" -lt 8 ]; then
  echo "ERROR: setup failed to seed all 8 files — task cannot proceed correctly." >&2
  /bin/ls -la "$DOWNLOADS" >&2
  exit 1
fi

# 3) Record task start (Unix epoch, seconds) AFTER seeding completes so
#    any file move the agent does is strictly after this timestamp.
/bin/date +%s > /tmp/task_start_timestamp
echo "task_start_unix=$(cat /tmp/task_start_timestamp)"

# 4) Ensure Finder is up and pointing at Downloads. The post_start hook may
#    have just bounced Finder; re-confirm + open the window.
if ! /usr/bin/pgrep -x Finder >/dev/null 2>&1; then
  /usr/bin/open -a Finder
fi
for i in $(seq 1 15); do
  if /usr/bin/pgrep -x Finder >/dev/null 2>&1; then break; fi
  sleep 1
done

/usr/bin/open "$DOWNLOADS"
sleep 2

# Force ~/Downloads into column view. The global `FXPreferredViewStyle=clmv`
# in setup_finder.sh applies to fresh folders the user hasn't visited, but
# ~/Downloads has a saved per-folder view that overrides it. Setting
# `current view of front window` via AppleEvent applies per-folder. AppleEvent
# to Finder works over SSH (Automation TCC). Surfaced in audit B1 (2026-05-18).
osascript -e 'tell application "Finder" to set current view of front window to column view' 2>/dev/null || true
sleep 1

# Start-state screenshot for the trajectory archive.
/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

echo "=== organize_downloads_by_type setup complete ==="
echo "Finder is open on ~/Downloads/ with 8 seed files. Agent should create the 4 category subfolders and move each file into its correct one."
