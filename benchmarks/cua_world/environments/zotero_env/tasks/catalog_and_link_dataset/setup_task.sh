#!/bin/bash
echo "=== Setting up catalog_and_link_dataset task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to safely modify DB
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed library with ML papers (contains Krizhevsky et al.)
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# 3. Record Task Start Time
date +%s > /tmp/task_start_timestamp

# 4. Verify target paper exists and record its ID
# We need this ID to verify the link later
TARGET_PAPER_TITLE="ImageNet Classification with Deep Convolutional Neural Networks"
TARGET_ID=$(sqlite3 "$DB" "SELECT i.itemID FROM items i JOIN itemData d ON i.itemID=d.itemID JOIN itemDataValues v ON d.valueID=v.valueID WHERE d.fieldID=1 AND v.value LIKE '%$TARGET_PAPER_TITLE%'" 2>/dev/null)

if [ -z "$TARGET_ID" ]; then
    echo "ERROR: Target paper '$TARGET_PAPER_TITLE' not found in DB!"
    # Fallback: try to insert it or fail
    exit 1
fi
echo "$TARGET_ID" > /tmp/target_paper_id
echo "Target paper ID: $TARGET_ID"

# 5. Restart Zotero
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# 6. Wait for Zotero window
echo "Waiting for Zotero window..."
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "zotero"; then
        echo "Zotero window found"
        break
    fi
    sleep 1
done
sleep 5

# 7. Maximize and focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 8. Initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="