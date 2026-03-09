#!/bin/bash
echo "=== Setting up fix_single_field_author_errors task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed library with classic papers
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode classic > /dev/null 2>&1

# 3. Corrupt the specific authors to be Single Field (fieldMode=1)
# We use SQLite to manually introduce the errors the agent must fix.
# fieldMode: 1 = Single Field (Organization), 0 = Two Field (Person)

echo "Corrupting author metadata..."
sqlite3 "$DB" <<EOF
-- Fix Shannon
UPDATE creators 
SET fieldMode = 1, lastName = 'Shannon, Claude E.', firstName = '' 
WHERE creatorID IN (
    SELECT ic.creatorID FROM itemCreators ic
    JOIN items i ON ic.itemID = i.itemID
    JOIN itemData d ON i.itemID = d.itemID
    JOIN itemDataValues v ON d.valueID = v.valueID
    JOIN creators c ON ic.creatorID = c.creatorID
    WHERE d.fieldID = 1 AND v.value = 'A Mathematical Theory of Communication'
    AND c.lastName = 'Shannon'
);

-- Fix Turing (Computing Machinery)
UPDATE creators 
SET fieldMode = 1, lastName = 'Turing, Alan', firstName = '' 
WHERE creatorID IN (
    SELECT ic.creatorID FROM itemCreators ic
    JOIN items i ON ic.itemID = i.itemID
    JOIN itemData d ON i.itemID = d.itemID
    JOIN itemDataValues v ON d.valueID = v.valueID
    JOIN creators c ON ic.creatorID = c.creatorID
    WHERE d.fieldID = 1 AND v.value = 'Computing Machinery and Intelligence'
    AND c.lastName = 'Turing'
);

-- Fix Huffman
UPDATE creators 
SET fieldMode = 1, lastName = 'Huffman, David A.', firstName = '' 
WHERE creatorID IN (
    SELECT ic.creatorID FROM itemCreators ic
    JOIN items i ON ic.itemID = i.itemID
    JOIN itemData d ON i.itemID = d.itemID
    JOIN itemDataValues v ON d.valueID = v.valueID
    JOIN creators c ON ic.creatorID = c.creatorID
    WHERE d.fieldID = 1 AND v.value = 'A Method for the Construction of Minimum-Redundancy Codes'
    AND c.lastName = 'Huffman'
);
EOF

# Record start time
date +%s > /tmp/task_start_time.txt

# 4. Restart Zotero to reflect DB changes
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -q "Zotero"; then
        echo "Zotero window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="