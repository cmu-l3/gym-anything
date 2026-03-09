#!/bin/bash
set -e
echo "=== Setting up create_diverse_reference_types task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

DB_PATH="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to safely seed/check DB
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed library with standard journal articles (so it's not empty)
# We use 'all' mode which gives ~18 items. None of them are Thesis/Patent/Report/BookSection.
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed.log 2>&1

# 3. Record baseline state
# Record start time for anti-gaming (items must be added AFTER this)
date +%s > /tmp/task_start_time.txt

# Count existing items of specific types to ensure clean start state logic works
if [ -f "$DB_PATH" ]; then
    # Zotero 7 itemTypeIDs: Thesis=7, Patent=35, Report=27, BookSection=5
    # (IDs are standard across Zotero 5/6/7, but we'll query dynamically in verification to be safe)
    # Just record total count for now
    INITIAL_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1, 14)" 2>/dev/null || echo "0")
    echo "$INITIAL_COUNT" > /tmp/initial_item_count.txt
    echo "Initial item count: $INITIAL_COUNT"
else
    echo "0" > /tmp/initial_item_count.txt
fi

# 4. Restart Zotero
echo "Restarting Zotero..."
# Use setsid to detach from shell, standard pattern for this env
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote &"

# 5. Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# 6. Maximize and focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 7. Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="