#!/bin/bash
# pre_task hook for declutter_desktop_to_projects on Finder/macOS.
#
# Seeds 18 files on ~/Desktop with three filename prefixes:
#   HV_ (6 files) → Home Renovation
#   SC_ (6 files) → School Schedule
#   GD_ (6 files) → Garden Design
# Agent must sort by prefix, lock files, create README.txt per project, clean Desktop.
set -eu

echo "=== Setting up declutter_desktop_to_projects ==="

DESKTOP="$HOME/Desktop"
PROJECTS="$HOME/Documents/Projects"

# 1) Clean slate — remove any previous HV_/SC_/GD_ files on Desktop and Projects/ subfolders
for prefix in HV_ SC_ GD_; do
  /usr/bin/find "$DESKTOP" -maxdepth 1 -name "${prefix}*" -exec rm -f {} + 2>/dev/null || true
done
rm -rf "$PROJECTS/Home Renovation" "$PROJECTS/School Schedule" "$PROJECTS/Garden Design" 2>/dev/null || true
mkdir -p "$DESKTOP" "$HOME/Documents/Projects"

# 2) Seed 18 project files on the Desktop
# Home Renovation (6)
/bin/echo "Contractor quotes for kitchen remodel — three bids compared." > "$DESKTOP/HV_kitchen_quotes.txt"
/bin/echo "Bathroom tile options and pricing from HomeDepot and TileShop." > "$DESKTOP/HV_bathroom_tiles.txt"
/bin/echo "Paint colors shortlist: Benjamin Moore OC-17, Sherwin SW7015." > "$DESKTOP/HV_paint_colors.txt"
/bin/echo "Permit application checklist for structural changes." > "$DESKTOP/HV_permit_checklist.txt"
/bin/echo "Before photos index: kitchen, bathroom, living room, hallway." > "$DESKTOP/HV_before_photos.txt"
/bin/echo "Project timeline week by week through end of Q3 2026." > "$DESKTOP/HV_timeline.txt"

# School Schedule (6)
/bin/echo "Fall semester class schedule: Math 8:00, Science 10:00, English 13:00." > "$DESKTOP/SC_fall_schedule.txt"
/bin/echo "Teacher contact list with email and office hours." > "$DESKTOP/SC_teacher_contacts.txt"
/bin/echo "Extracurricular activities calendar: soccer Mon/Wed, art Thu." > "$DESKTOP/SC_activities.txt"
/bin/echo "Homework tracker template for each subject and due date." > "$DESKTOP/SC_homework_tracker.txt"
/bin/echo "School supply list for fall 2026 from school website." > "$DESKTOP/SC_supply_list.txt"
/bin/echo "School holidays and closures calendar for 2026–2027." > "$DESKTOP/SC_holidays.txt"

# Garden Design (6)
/bin/echo "Planting zone map: USDA zone 7b, last frost date Apr 2." > "$DESKTOP/GD_zone_map.txt"
/bin/echo "Vegetable bed layout sketch: four 4x8 raised beds." > "$DESKTOP/GD_bed_layout.txt"
/bin/echo "Seed catalog wishlist: Baker Creek, Johnny's, Territorial." > "$DESKTOP/GD_seed_wishlist.txt"
/bin/echo "Drip irrigation plan notes: emitter spacing and flow rates." > "$DESKTOP/GD_irrigation.txt"
/bin/echo "Composting schedule: turn every 2 weeks, add kitchen scraps." > "$DESKTOP/GD_composting.txt"
/bin/echo "Pest management log: aphids Apr, squash bugs Jul, deer Aug." > "$DESKTOP/GD_pest_log.txt"

SEED_COUNT=$(/usr/bin/find "$DESKTOP" -maxdepth 1 -name "HV_*.txt" -o -name "SC_*.txt" -o -name "GD_*.txt" 2>/dev/null | wc -l | tr -d ' ')
echo "seeded_file_count=$SEED_COUNT (expected: 18)"
if [ "${SEED_COUNT:-0}" -lt 18 ]; then
  echo "ERROR: setup failed to seed all 18 files" >&2
  exit 1
fi

# 3) Record task start timestamp
/bin/date +%s > /tmp/task_start_timestamp
echo "task_start_unix=$(cat /tmp/task_start_timestamp)"

# 4) Ensure Finder is running and open Desktop
if ! /usr/bin/pgrep -x Finder >/dev/null 2>&1; then
  /usr/bin/open -a Finder
fi
for i in $(seq 1 15); do
  if /usr/bin/pgrep -x Finder >/dev/null 2>&1; then break; fi
  sleep 1
done

/usr/bin/open "$DESKTOP"
sleep 2
osascript -e 'tell application "Finder" to set current view of front window to column view' 2>/dev/null || true
sleep 1

# 5) Start-state screenshot
/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

echo "=== declutter_desktop_to_projects setup complete ==="
echo "18 files seeded on Desktop (HV_/SC_/GD_ prefixes). Agent must sort into ~/Documents/Projects/{Home Renovation,School Schedule,Garden Design}/, lock each file, create README.txt per folder, clear Desktop."
