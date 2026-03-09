#!/bin/bash
echo "=== Setting up create_saved_searches task ==="

DB="/home/ga/Zotero/zotero.sqlite"
TASK_START_FILE="/tmp/task_start_time.txt"

# 1. Stop Zotero to safely manipulate DB
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed library with papers (Classic + ML)
echo "Seeding library..."
# This script inserts items. We also need to make sure there are NO existing saved searches
# so the agent starts with a clean slate for searches.
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# 3. Clean up any existing saved searches to ensure clean state
if [ -f "$DB" ]; then
    echo "Clearing existing saved searches..."
    sqlite3 "$DB" "DELETE FROM savedSearches WHERE libraryID=1;"
    sqlite3 "$DB" "DELETE FROM savedSearchConditions WHERE savedSearchID NOT IN (SELECT savedSearchID FROM savedSearches);"
    
    # Verify baseline
    INITIAL_SEARCH_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM savedSearches WHERE libraryID=1" 2>/dev/null || echo "0")
    echo "Initial saved searches: $INITIAL_SEARCH_COUNT"
else
    echo "WARNING: Database not found, creating directory..."
    mkdir -p /home/ga/Zotero
fi

# 4. Record start time for anti-gaming checks
date +%s > "$TASK_START_FILE"

# 5. Restart Zotero
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# 6. Wait for Zotero window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# 7. Maximize and focus
sleep 3
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 8. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="