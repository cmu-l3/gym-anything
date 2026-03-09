#!/bin/bash
set -e
echo "=== Setting up curate_conference_reading_list task ==="

# Define paths
DB_PATH="/home/ga/Zotero/zotero.sqlite"
SEED_SCRIPT="/workspace/scripts/seed_library.py"

# 1. Stop Zotero to safely modify DB
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed the library with the full set of 18 papers
# (10 classic + 8 ML papers, covering the required NeurIPS papers)
echo "Seeding library..."
if [ -f "$SEED_SCRIPT" ]; then
    python3 "$SEED_SCRIPT" --mode all > /tmp/seed_output.txt 2>&1
else
    echo "Error: seed_library.py not found"
    exit 1
fi

# 3. Clean up any previous task artifacts (if re-running)
# Remove the target collection if it exists from a previous run
echo "Cleaning DB..."
sqlite3 "$DB_PATH" <<EOF
DELETE FROM collections WHERE collectionName = 'NeurIPS Preparation';
DELETE FROM tags WHERE name = 'neurips-reading';
EOF

# 4. Record initial state for anti-gaming verification
# Record task start timestamp
date +%s > /tmp/task_start_time.txt
# Record initial item count
INITIAL_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1, 14)" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_item_count.txt

# 5. Restart Zotero
echo "Starting Zotero..."
# Use setsid to detach from shell, ensure it runs as 'ga'
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &"

# 6. Wait for window and maximize
echo "Waiting for Zotero window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Ensure window is maximized and focused
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="