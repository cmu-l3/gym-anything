#!/bin/bash
echo "=== Setting up catalog_research_software task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Stop Zotero cleanly to prepare DB
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed library with standard papers (so it's not empty)
# Using 'classic' mode to keep it lightweight but realistic
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode classic > /dev/null 2>&1

# 3. Clean up any pre-existing items that might conflict (Zotero or PyTorch)
# This ensures we are testing creation, not just finding existing items
echo "Cleaning potential conflicts..."
DB_PATH="/home/ga/Zotero/zotero.sqlite"
sqlite3 "$DB_PATH" <<EOF
DELETE FROM items WHERE itemID IN (
    SELECT itemID FROM itemDataValues v 
    JOIN itemData d ON v.valueID = d.valueID 
    WHERE d.fieldID = 1 AND (v.value = 'Zotero' OR v.value = 'PyTorch')
);
EOF

# 4. Record baseline state
echo "Recording baseline..."
INITIAL_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1, 14)" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_item_count
date +%s > /tmp/task_start_time

# 5. Restart Zotero
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 6. Capture initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="