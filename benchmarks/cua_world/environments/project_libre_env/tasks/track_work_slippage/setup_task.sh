#!/bin/bash
set -e
echo "=== Setting up track_work_slippage task ==="

# 1. Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# 2. Prepare the project file
# We use the standard sample project which has "Database Implementation" at UID 8
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
TASK_PROJECT="/home/ga/Projects/current_task.xml"

mkdir -p /home/ga/Projects
if [ -f "$SAMPLE_PROJECT" ]; then
    cp "$SAMPLE_PROJECT" "$TASK_PROJECT"
    echo "Copied sample project to $TASK_PROJECT"
else
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    # Fallback creation if sample missing (failsafe)
    exit 1
fi

# Ensure correct permissions
chown -R ga:ga /home/ga/Projects

# 3. Clean up previous results
rm -f /home/ga/Projects/work_slippage.xml
rm -f /tmp/task_result.json

# 4. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch ProjectLibre with the project file
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$TASK_PROJECT' > /tmp/projectlibre_task.log 2>&1 &"

# 6. Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "projectlibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# 7. Maximize and focus
sleep 5 # Wait for Java UI to fully render
DISPLAY=:1 wmctrl -r "project.xml" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# 8. Dismiss potential dialogs (tips, etc)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 9. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="