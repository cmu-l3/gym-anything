#!/bin/bash
set -e
echo "=== Setting up create_swing_shift_calendar task ==="

# 1. Cleanup previous run artifacts
rm -f /home/ga/Projects/swing_shift_project.xml
rm -f /tmp/task_result.json
rm -f /tmp/task_start_time.txt
rm -f /tmp/task_initial.png
rm -f /tmp/task_final.png

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Prepare the starting project file
# We use the standard sample project
mkdir -p /home/ga/Projects
cp /home/ga/Projects/samples/sample_project.xml /home/ga/Projects/current_project.xml
chown ga:ga /home/ga/Projects/current_project.xml

# 4. Launch ProjectLibre
# Kill any existing instances first
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre /home/ga/Projects/current_project.xml > /tmp/projectlibre.log 2>&1 &"

# 5. Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "projectlibre"; then
        echo "Window detected."
        break
    fi
    sleep 1
done
sleep 5 # Allow UI to fully load

# 6. Maximize window (Critical for VLM/Agent)
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Dismiss any startup dialogs (Tip of the day, etc.)
# ProjectLibre often shows a "Tip of the Day" or "Welcome" dialog.
# Pressing Escape a few times usually clears them.
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 8. Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="