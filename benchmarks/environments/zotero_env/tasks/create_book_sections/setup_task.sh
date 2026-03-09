#!/bin/bash
echo "=== Setting up create_book_sections task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Kill Zotero to modify DB safely
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed library with classic papers
# This includes "The Mathematical Theory of Communication"
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode classic > /tmp/seed_output.txt 2>/dev/null

# 3. Manipulate the database to create the starting state
# We want the parent item to be a "Journal Article" (type 22) or generic instead of Book (type 2)
# to force the agent to fix it.
echo "Modifying database state..."
sqlite3 "$DB" <<EOF
-- Find the item ID for the Shannon/Weaver book
CREATE TEMP TABLE TargetItem AS
SELECT i.itemID
FROM items i
JOIN itemData d ON i.itemID = d.itemID
JOIN itemDataValues v ON d.valueID = v.valueID
WHERE d.fieldID = 1 AND v.value = 'The Mathematical Theory of Communication';

-- Update its type to Journal Article (22) to act as the "incorrect" starting state
UPDATE items
SET itemTypeID = 22
WHERE itemID IN (SELECT itemID FROM TargetItem);

-- Ensure it has both authors (Shannon and Weaver) - seed script usually does this,
-- but we verify/enforce strictly here if needed.
-- (Skipping detailed author manipulation as seed script usually handles 'authors' list correctly)
EOF

# Record start time and initial state counts
date +%s > /tmp/task_start_time.txt
INITIAL_SECTION_COUNT=$(sqlite3 "$DB" "SELECT COUNT(*) FROM items WHERE itemTypeID = 3" 2>/dev/null || echo "0")
echo "$INITIAL_SECTION_COUNT" > /tmp/initial_section_count.txt

# 4. Restart Zotero
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# Wait for Zotero window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Window found"
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="