#!/bin/bash
set -e
echo "=== Setting up add_precise_publication_dates task ==="

# 1. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Stop Zotero to safely seed database
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 3. Seed library with papers (year-only dates by default)
echo "Seeding library..."
python3 /workspace/scripts/seed_library.py --mode all > /tmp/seed.log 2>&1

# 4. Start Zotero application
echo "Starting Zotero..."
# Use sudo to run as user 'ga', set DISPLAY, and run in background
sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &'

# 5. Wait for Zotero window to appear
echo "Waiting for Zotero window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# 6. Maximize and focus the window
sleep 2
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# 7. Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="