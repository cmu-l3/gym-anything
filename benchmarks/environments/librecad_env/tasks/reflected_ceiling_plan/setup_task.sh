#!/bin/bash
set -e
echo "=== Setting up Reflected Ceiling Plan task ==="

# 1. Prepare Workspace
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# Remove previous output file to ensure clean state
rm -f /home/ga/Documents/LibreCAD/reflected_ceiling_plan.dxf

# 2. Record Task Start Time (Anti-Gaming)
date +%s > /tmp/task_start_time.txt

# 3. Start LibreCAD
# Kill any existing instances
pkill -f librecad 2>/dev/null || true
sleep 2

echo "Starting LibreCAD..."
# Start with no file (blank drawing)
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad_task.log 2>&1 &"

# 4. Wait for Window and Configure
# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs (e.g., Tip of the Day)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# 5. Capture Initial State
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="