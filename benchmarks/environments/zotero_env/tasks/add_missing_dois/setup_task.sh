#!/bin/bash
set -e
echo "=== Setting up add_missing_dois task ==="

DB_PATH="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to safely manipulate DB
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed the library with papers
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_output.txt 2>&1

# 3. Sanitize: Remove ALL existing DOIs to ensure clean start state
# Field ID 59 is DOI in Zotero 7 schema
echo "Clearing any existing DOIs..."
sqlite3 "$DB_PATH" "DELETE FROM itemData WHERE fieldID = 59;"

# 4. Record baseline state
INITIAL_DOI_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM itemData WHERE fieldID = 59;" 2>/dev/null || echo "0")
echo "$INITIAL_DOI_COUNT" > /tmp/initial_doi_count
date +%s > /tmp/task_start_time.txt
echo "Initial DOI count: $INITIAL_DOI_COUNT (should be 0)"

# 5. Restart Zotero
echo "Restarting Zotero..."
# Use setsid to detach from shell, avoiding hangs
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &"

# 6. Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Zotero"; then
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

echo "=== Task setup complete ==="