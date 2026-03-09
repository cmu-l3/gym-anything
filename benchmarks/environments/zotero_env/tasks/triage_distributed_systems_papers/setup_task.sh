#!/bin/bash
set -e
echo "=== Setting up triage_distributed_systems_papers task ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Prepare Zotero State
# Stop Zotero if running
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# Seed the library with the specific "triage_pipeline" dataset (20 Systems papers)
echo "Seeding library with Distributed Systems papers..."
python3 /workspace/scripts/seed_library.py --mode triage_pipeline > /tmp/seed.log 2>&1

# 3. Launch Zotero
echo "Launching Zotero..."
# Use the standard launch pattern for this env to avoid blocking
sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &'

# 4. Wait for window and maximize
echo "Waiting for Zotero window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Ensure window is maximized and focused
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true
sleep 2

# 5. Dismiss any potential startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Verify initial state (Screen capture)
echo "Capturing initial state..."
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="