#!/bin/bash
# Setup for add_missing_abstracts task
# Seeds library and ensures abstracts are empty

echo "=== Setting up add_missing_abstracts task ==="

ZOTERO_DB="/home/ga/Zotero/zotero.sqlite"

# 1. Kill Zotero to allow DB operations
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed the library
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# 3. Ensure abstracts are empty (just in case seed adds them later)
# fieldID 2 is abstractNote in Zotero schema
if [ -f "$ZOTERO_DB" ]; then
    echo "Clearing any existing abstracts..."
    sqlite3 "$ZOTERO_DB" "DELETE FROM itemData WHERE fieldID = 2;" 2>/dev/null || true
fi

# 4. Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 5. Record initial state count (should be 0)
INITIAL_ABSTRACT_COUNT=$(sqlite3 "$ZOTERO_DB" "SELECT COUNT(*) FROM itemData WHERE fieldID = 2" 2>/dev/null || echo "0")
echo "$INITIAL_ABSTRACT_COUNT" > /tmp/initial_abstract_count.txt

# 6. Restart Zotero
echo "Starting Zotero..."
sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /home/ga/zotero_log.txt 2>&1 &'

# 7. Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "zotero"; then
        echo "Zotero window detected"
        break
    fi
    sleep 1
done

# 8. Maximize and focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 9. Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="