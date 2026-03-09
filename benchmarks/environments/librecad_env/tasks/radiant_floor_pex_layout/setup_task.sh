#!/bin/bash
set -e
echo "=== Setting up Radiant Floor PEX Layout Task ==="

# 1. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up any previous runs
rm -f /home/ga/Documents/LibreCAD/radiant_heating_layout.dxf
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 3. Ensure LibreCAD is not running
pkill -f librecad 2>/dev/null || true
sleep 2

# 4. Start LibreCAD with a fresh empty drawing
# We do NOT pass a file argument, ensuring a blank slate
echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_task.log 2>&1 &"

# 5. Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# 6. Maximize the window (Critical for agent vision)
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 7. Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 8. Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="