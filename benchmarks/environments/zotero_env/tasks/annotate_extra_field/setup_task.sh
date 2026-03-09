#!/bin/bash
# Setup for annotate_extra_field task
# Seeds library with 18 papers, ensures Extra fields are empty, and starts Zotero.

set -e
echo "=== Setting up annotate_extra_field task ==="

DB_PATH="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to safely manipulate DB
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed the library
echo "Seeding library with 18 papers..."
# Using 'all' mode to get Classic (10) + ML (8) papers
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# 3. Clean 'Extra' fields to ensure baseline is empty
# In Zotero 7 schema, fieldID for 'extra' needs to be found first
echo "Cleaning existing Extra fields..."
sqlite3 "$DB_PATH" <<EOF
DELETE FROM itemData 
WHERE fieldID = (SELECT fieldID FROM fields WHERE fieldName = 'extra')
  AND itemID IN (SELECT itemID FROM items WHERE itemTypeID != 1 AND itemTypeID != 14);
EOF

# 4. Record task start time (for anti-gaming check)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# 5. Restart Zotero
echo "Restarting Zotero..."
# Use sudo -u ga to run as user 'ga'
sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &'

# 6. Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Zotero window detected"
        break
    fi
    sleep 1
done

# 7. Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 8. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="