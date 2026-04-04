#!/bin/bash
echo "=== Setting up organize_classics_by_tag task ==="

# Record start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Stop Zotero to safely modify database
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed the library with the standard mix of Classic + ML papers
# This provides ~10 classic (pre-1970) and ~8 modern (post-2010) papers
echo "Seeding library with mixed papers..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_output.log 2>&1

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to seed library"
    cat /tmp/seed_output.log
    exit 1
fi

# 3. Clean up any previous 'History of Computing' collection or 'classic-era' tags
# This ensures a clean start state even if the environment was reused
DB="/home/ga/Zotero/zotero.sqlite"
echo "Cleaning previous state..."

# Remove specific collection if it exists
sqlite3 "$DB" "DELETE FROM collections WHERE collectionName='History of Computing';" 2>/dev/null || true
# Remove specific tag if it exists
sqlite3 "$DB" "DELETE FROM tags WHERE name='classic-era';" 2>/dev/null || true
# Clean up junction tables (orphaned items handled by Zotero usually, but good to be safe)
sqlite3 "$DB" "DELETE FROM collectionItems WHERE collectionID NOT IN (SELECT collectionID FROM collections);" 2>/dev/null || true
sqlite3 "$DB" "DELETE FROM itemTags WHERE tagID NOT IN (SELECT tagID FROM tags);" 2>/dev/null || true

# 4. Restart Zotero
echo "Restarting Zotero..."
# Use setsid to detach from shell, standard pattern for this env
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &"

# 5. Wait for UI to load
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Window detected"
        break
    fi
    sleep 1
done

sleep 5

# 6. Maximize and focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 2

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="