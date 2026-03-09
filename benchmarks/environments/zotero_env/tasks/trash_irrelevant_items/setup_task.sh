#!/bin/bash
echo "=== Setting up trash_irrelevant_items task ==="

DB="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to ensure clean database access
pkill -9 -f zotero 2>/dev/null || true
sleep 2

# 2. Seed the library with the standard set of 18 papers (10 classic + 8 ML)
# This includes both 'A Mathematical Theory...' (1948) and 'The Mathematical Theory...' (1949)
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /dev/null 2>&1

# 3. Ensure Trash is empty initially (clean slate)
if [ -f "$DB" ]; then
    sqlite3 "$DB" "DELETE FROM deletedItems;" 2>/dev/null || true
    echo "Trash emptied."
fi

# 4. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 5. Restart Zotero to load the seeded data
echo "Restarting Zotero..."
# Use setsid to detach from shell, avoiding hangs
sudo -u ga bash -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &"

# 6. Wait for Zotero window
echo "Waiting for Zotero UI..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Zotero"; then
        echo "Zotero window detected."
        break
    fi
    sleep 1
done

# 7. Maximize and Focus
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 8. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="