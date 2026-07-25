#!/bin/bash
# pre_task hook for archive_completed_projects on Finder/macOS.
#
# Seeds ~/Documents/Projects/ with 5 project folders:
#   Active:  HomeRenovation, LearnPiano
#   Done:    VegetableGarden (DONE.txt), BookClub2024 (DONE.txt), CookingChallenge (DONE.txt)
# Agent must discover done status from DONE.txt presence, then tag/zip/archive/delete.
set -eu

echo "=== Setting up archive_completed_projects ==="

PROJECTS="$HOME/Documents/Projects"
ARCHIVE="$HOME/Documents/Archive"

# 1) Clean slate
rm -rf "$PROJECTS" 2>/dev/null || true
rm -rf "$ARCHIVE" 2>/dev/null || true
mkdir -p "$HOME/Documents"

# 2) Seed project folders
mkdir -p "$PROJECTS/HomeRenovation"
/bin/echo "Kitchen renovation sketches and material samples." > "$PROJECTS/HomeRenovation/kitchen_plan.txt"
/bin/echo "Bathroom tile options and pricing from three vendors." > "$PROJECTS/HomeRenovation/bathroom_notes.txt"
/bin/echo "Contractor quotes — comparing three bids." > "$PROJECTS/HomeRenovation/quotes.txt"

mkdir -p "$PROJECTS/VegetableGarden"
/bin/echo "Spring 2024 planting schedule: tomatoes week 12, basil week 14." > "$PROJECTS/VegetableGarden/planting_schedule.txt"
/bin/echo "Harvest log: 12 lbs tomatoes, 3 lbs zucchini, 1 lb basil." > "$PROJECTS/VegetableGarden/harvest_log.txt"
/bin/echo "done" > "$PROJECTS/VegetableGarden/DONE.txt"

mkdir -p "$PROJECTS/LearnPiano"
/bin/echo "Weekly scales practice: C major, G major, D major." > "$PROJECTS/LearnPiano/practice_routine.txt"
/bin/echo "Song wishlist: Fur Elise, Moonlight Sonata, Clair de Lune." > "$PROJECTS/LearnPiano/song_wishlist.txt"

mkdir -p "$PROJECTS/BookClub2024"
/bin/echo "Reading list: 12 books for 2024." > "$PROJECTS/BookClub2024/reading_list.txt"
/bin/echo "Discussion notes from Jan–Dec 2024 meetings." > "$PROJECTS/BookClub2024/discussion_notes.txt"
/bin/echo "Member contacts and reading preferences." > "$PROJECTS/BookClub2024/members.txt"
/bin/echo "done" > "$PROJECTS/BookClub2024/DONE.txt"

mkdir -p "$PROJECTS/CookingChallenge"
/bin/echo "52 recipes tried through 2024." > "$PROJECTS/CookingChallenge/recipe_log.txt"
/bin/echo "Ratings and tasting notes for each recipe." > "$PROJECTS/CookingChallenge/ratings.txt"
/bin/echo "done" > "$PROJECTS/CookingChallenge/DONE.txt"

mkdir -p "$ARCHIVE"

FOLDER_COUNT=$(/usr/bin/find "$PROJECTS" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
echo "project_folder_count=$FOLDER_COUNT (expected: 5)"
if [ "${FOLDER_COUNT:-0}" -lt 5 ]; then
  echo "ERROR: setup failed to create all 5 project folders" >&2
  exit 1
fi

# 3) Record task start timestamp
/bin/date +%s > /tmp/task_start_timestamp
echo "task_start_unix=$(cat /tmp/task_start_timestamp)"

# 4) Ensure Finder is running and open Projects
if ! /usr/bin/pgrep -x Finder >/dev/null 2>&1; then
  /usr/bin/open -a Finder
fi
for i in $(seq 1 15); do
  if /usr/bin/pgrep -x Finder >/dev/null 2>&1; then break; fi
  sleep 1
done

/usr/bin/open "$PROJECTS"
sleep 2
osascript -e 'tell application "Finder" to set current view of front window to column view' 2>/dev/null || true
sleep 1

# 5) Start-state screenshot
/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

echo "=== archive_completed_projects setup complete ==="
echo "5 project folders created in ~/Documents/Projects/. Agent must find DONE.txt in done projects, tag/zip/archive/delete those, and tag active ones Green."
