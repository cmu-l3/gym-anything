#!/bin/bash
echo "=== Setting up catalog_non_traditional_materials task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to safely modify/check DB state
pkill -9 -f zotero 2>/dev/null || true
sleep 2

# 2. Clean up: Ensure the target collection doesn't already exist
# This prevents ambiguity if the task is re-run
if [ -f "$DB" ]; then
    sqlite3 "$DB" "DELETE FROM collections WHERE collectionName='Reproducibility Data';" 2>/dev/null || true
    # We won't purge items to avoid database corruption risks with complex item deletion logic in bash,
    # but since we check for items *inside* the collection, removing the collection is sufficient.
fi

# 3. Record task start time
date +%s > /tmp/task_start_time.txt

# 4. Start Zotero
echo "Starting Zotero..."
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /dev/null 2>&1 &"

# 5. Wait for window
echo "Waiting for Zotero window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "zotero"; then
        echo "Zotero window detected"
        break
    fi
    sleep 1
done

# 6. Maximize and focus (Critical for UI interaction)
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 7. Initial screenshot
sleep 1
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="