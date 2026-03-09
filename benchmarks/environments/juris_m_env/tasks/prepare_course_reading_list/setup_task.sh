#!/bin/bash
set -e
echo "=== Setting up prepare_course_reading_list task ==="
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Find Jurism database
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    exit 1
fi
echo "Using database: $JURISM_DB"

# Stop Jurism to perform DB cleanup
echo "Stopping Jurism..."
pkill -f /opt/jurism/jurism 2>/dev/null || true
sleep 3

# Inject references if library is sparse (we need Marbury and the Article)
ITEM_COUNT=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1,3,31)" 2>/dev/null || echo "0")
if [ "$ITEM_COUNT" -lt 5 ]; then
    echo "Injecting legal references..."
    python3 /workspace/utils/inject_references.py "$JURISM_DB" 2>/dev/null || true
fi

# Clean up previous task artifacts (specific collection, notes, and output file)
echo "Cleaning up previous artifacts..."
rm -f /home/ga/Documents/week1_syllabus.html
sqlite3 "$JURISM_DB" <<EOF
-- Remove the specific collection if it exists
DELETE FROM collections WHERE collectionName = 'Week 1 - Judicial Review';
DELETE FROM collectionItems WHERE collectionID NOT IN (SELECT collectionID FROM collections);

-- Remove notes containing the specific text to prevent false positives
DELETE FROM itemNotes WHERE note LIKE '%original jurisdiction%';
-- Clean up orphaned note items (itemTypeID=1 is note in some schemas, usually 1 or linked via itemNotes)
DELETE FROM items WHERE itemID NOT IN (SELECT itemID FROM itemData) AND itemID NOT IN (SELECT itemID FROM itemNotes) AND itemID NOT IN (SELECT itemID FROM itemAttachments);
EOF

# Relaunch Jurism
echo "Relaunching Jurism..."
setsid sudo -u ga bash -c 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus DISPLAY=:1 /opt/jurism/jurism --no-remote >> /home/ga/jurism.log 2>&1 &'
sleep 5

# Wait for Jurism and handle alerts
wait_and_dismiss_jurism_alerts 45

# Maximize window
DISPLAY=:1 wmctrl -r "Jurism" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Jurism" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="