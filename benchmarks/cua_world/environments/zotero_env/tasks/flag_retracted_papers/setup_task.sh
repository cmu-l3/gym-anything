#!/bin/bash
set -e
echo "=== Setting up flag_retracted_papers task ==="

DB_PATH="/home/ga/Zotero/zotero.sqlite"

# 1. Stop Zotero to ensure DB safety during seeding
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed library with papers (including the ML papers needed for this task)
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed.log 2>&1
echo "Library seeded."

# 3. Record start time for anti-gaming (modification checks)
date +%s > /tmp/task_start_time.txt

# 4. Restart Zotero
echo "Restarting Zotero..."
sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /home/ga/zotero_run.log 2>&1 &'

# 5. Wait for Zotero to launch and stabilize
echo "Waiting for window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5

# 6. Maximize and focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 7. Take initial screenshot
echo "Taking initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="