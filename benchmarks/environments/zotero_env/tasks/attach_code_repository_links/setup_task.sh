#!/bin/bash
# Setup for attach_code_repository_links task
# Seeds library with ML papers and ensures clean state

echo "=== Setting up attach_code_repository_links task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to safely modify DB
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed papers (using 'all' mode to ensure ML papers are present)
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed.log 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: Seeding failed"
    cat /tmp/seed.log
    exit 1
fi

# 3. Clean up any existing attachments on target papers (to ensure a fresh start)
# We need to find IDs for the 3 papers and remove their children
sqlite3 "$DB" <<EOF
DELETE FROM items WHERE itemID IN (
    SELECT i.itemID FROM items i
    JOIN itemNotes n ON i.itemID = n.itemID 
    WHERE n.parentItemID IN (
        SELECT itemID FROM items WHERE itemID IN (
            SELECT itemID FROM itemData WHERE valueID IN (
                SELECT valueID FROM itemDataValues WHERE value IN (
                    'Attention Is All You Need',
                    'BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding',
                    'Deep Residual Learning for Image Recognition'
                )
            )
        )
    )
);
-- Also delete standard attachments
DELETE FROM items WHERE parentItemID IN (
    SELECT itemID FROM items WHERE itemID IN (
         SELECT itemID FROM itemData WHERE valueID IN (
             SELECT valueID FROM itemDataValues WHERE value IN (
                 'Attention Is All You Need',
                 'BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding',
                 'Deep Residual Learning for Image Recognition'
             )
         )
    )
);
EOF

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Restart Zotero
echo "Restarting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# 6. Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Window found"
        break
    fi
    sleep 1
done

# 7. Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="