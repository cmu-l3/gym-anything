#!/bin/bash
# Setup for correct_item_types_to_conference task
# Ensures library is seeded and specific papers are set to Journal Article initially.

set -e
echo "=== Setting up correct_item_types_to_conference task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero cleanly
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed library with papers
echo "Seeding library..."
# This script adds the papers if they don't exist
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed_output.txt 2>&1

# 3. Enforce initial state: All target papers must be 'journalArticle'
# We use sqlite3 to force this state so the agent has work to do.
echo "Enforcing initial state (Journal Article)..."

sqlite3 "$DB" <<EOF
-- Get Journal Article Type ID
CREATE TEMP TABLE IF NOT EXISTS Vars (val INTEGER);
INSERT INTO Vars SELECT itemTypeID FROM itemTypes WHERE typeName='journalArticle';

-- Update 'Attention Is All You Need'
UPDATE items SET itemTypeID = (SELECT val FROM Vars)
WHERE itemID IN (
    SELECT i.itemID FROM items i
    JOIN itemData d ON i.itemID=d.itemID
    JOIN itemDataValues v ON d.valueID=v.valueID
    WHERE d.fieldID=1 AND v.value LIKE '%Attention Is All You Need%'
);

-- Update 'ImageNet Classification...'
UPDATE items SET itemTypeID = (SELECT val FROM Vars)
WHERE itemID IN (
    SELECT i.itemID FROM items i
    JOIN itemData d ON i.itemID=d.itemID
    JOIN itemDataValues v ON d.valueID=v.valueID
    WHERE d.fieldID=1 AND v.value LIKE '%ImageNet Classification with Deep%'
);

-- Update 'Deep Residual Learning...'
UPDATE items SET itemTypeID = (SELECT val FROM Vars)
WHERE itemID IN (
    SELECT i.itemID FROM items i
    JOIN itemData d ON i.itemID=d.itemID
    JOIN itemDataValues v ON d.valueID=v.valueID
    WHERE d.fieldID=1 AND v.value LIKE '%Deep Residual Learning for Image%'
);

-- Update 'Mastering the Game of Go...' (Control)
UPDATE items SET itemTypeID = (SELECT val FROM Vars)
WHERE itemID IN (
    SELECT i.itemID FROM items i
    JOIN itemData d ON i.itemID=d.itemID
    JOIN itemDataValues v ON d.valueID=v.valueID
    WHERE d.fieldID=1 AND v.value LIKE '%Mastering the Game of Go%'
);
EOF

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Start time recorded."

# 4. Restart Zotero
echo "Restarting Zotero..."
# Use setsid and no-remote to ensure it runs as a standalone instance
sudo -u ga bash -c "DISPLAY=:1 setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &"

# 5. Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Zotero window detected."
        break
    fi
    sleep 1
done

# 6. Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 7. Initial Screenshot
sleep 2
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="