#!/bin/bash
# pre_task hook for annotate_and_index_downloads on Finder/macOS.
#
# Seeds 15 files of 5 types in ~/Downloads:
#   3 PDFs (financial), 3 images, 3 .txt notes, 3 .m3u playlists, 3 misc
# Agent must sort, tag, comment, and index them.
set -eu

echo "=== Setting up annotate_and_index_downloads ==="

DOWNLOADS="$HOME/Downloads"

# 1) Clean slate
mkdir -p "$DOWNLOADS"
/usr/bin/find "$DOWNLOADS" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
rm -rf "$HOME/Documents/Organized" 2>/dev/null || true
rm -f "$HOME/Desktop/File_Index.txt" 2>/dev/null || true

# 2) Seed files
# Financial PDFs
/bin/echo "%PDF-1.4 stub: 2024 Tax Return Summary — for sorting task use only." > "$DOWNLOADS/2024_Tax_Return_Summary.pdf"
/bin/echo "%PDF-1.4 stub: Bank Statement March 2025 — for sorting task use only." > "$DOWNLOADS/Bank_Statement_March_2025.pdf"
/bin/echo "%PDF-1.4 stub: Investment Portfolio Q1 — for sorting task use only." > "$DOWNLOADS/Investment_Portfolio_Q1.pdf"

# Image stubs (JPEG/PNG markers in comment for identification)
/bin/echo "JPEG stub: family reunion photo." > "$DOWNLOADS/family_reunion_photo.jpg"
/bin/echo "JPEG stub: kitchen before remodel." > "$DOWNLOADS/kitchen_before.jpg"
/bin/echo "PNG stub: garden sketch and layout." > "$DOWNLOADS/garden_sketch.png"

# Text notes
/bin/echo "Shopping list: milk, eggs, bread, olive oil, chicken, pasta." > "$DOWNLOADS/grocery_list.txt"
/bin/echo "Book recommendations from book club: Station Eleven, Piranesi, Tomorrow." > "$DOWNLOADS/book_recs.txt"
/bin/echo "Home repair notes: fix leaky bathroom faucet, patch drywall, repaint trim." > "$DOWNLOADS/home_repairs.txt"

# Media playlists
/bin/echo '#EXTM3U' > "$DOWNLOADS/workout_playlist.m3u"
/bin/echo '#EXTINF:180,Workout Track 1' >> "$DOWNLOADS/workout_playlist.m3u"
/bin/echo 'file:///Music/track1.mp3' >> "$DOWNLOADS/workout_playlist.m3u"
/bin/echo '#EXTM3U' > "$DOWNLOADS/relaxing_evenings.m3u"
/bin/echo '#EXTINF:210,Evening Track 1' >> "$DOWNLOADS/relaxing_evenings.m3u"
/bin/echo 'file:///Music/eve1.mp3' >> "$DOWNLOADS/relaxing_evenings.m3u"
/bin/echo '#EXTM3U' > "$DOWNLOADS/road_trip_mix.m3u"
/bin/echo '#EXTINF:240,Road Trip Track 1' >> "$DOWNLOADS/road_trip_mix.m3u"
/bin/echo 'file:///Music/road1.mp3' >> "$DOWNLOADS/road_trip_mix.m3u"

# Other formats
/bin/echo '<?xml version="1.0"?><gpx version="1.1"><trk><name>Hiking Trail Loop</name></trk></gpx>' > "$DOWNLOADS/hiking_trail_loop.gpx"
/bin/echo 'PK stub: household budget 2025 (xlsx format stub).' > "$DOWNLOADS/household_budget.xlsx"
/bin/echo 'BEGIN:VCALENDAR' > "$DOWNLOADS/dentist_appointment.ics"
/bin/echo 'BEGIN:VEVENT' >> "$DOWNLOADS/dentist_appointment.ics"
/bin/echo 'SUMMARY:Dentist Appointment' >> "$DOWNLOADS/dentist_appointment.ics"
/bin/echo 'END:VEVENT' >> "$DOWNLOADS/dentist_appointment.ics"
/bin/echo 'END:VCALENDAR' >> "$DOWNLOADS/dentist_appointment.ics"

SEED_COUNT=$(/usr/bin/find "$DOWNLOADS" -mindepth 1 -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
echo "seeded_file_count=$SEED_COUNT (expected: 15)"
if [ "${SEED_COUNT:-0}" -lt 15 ]; then
  echo "ERROR: setup failed to seed all 15 files" >&2
  exit 1
fi

mkdir -p "$HOME/Documents"
mkdir -p "$HOME/Desktop"

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

echo "=== annotate_and_index_downloads setup complete ==="
echo "15 files of 5 types seeded in ~/Downloads. Agent should sort, tag, comment, and create File_Index.txt on Desktop."
