#!/bin/bash
set -e
echo "=== Setting up sort_tasks_by_duration task ==="

# 1. Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# 2. Prepare the sample project
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
WORK_PROJECT="/home/ga/Projects/current_project.xml"

mkdir -p /home/ga/Projects
if [ -f "$SAMPLE_PROJECT" ]; then
    cp "$SAMPLE_PROJECT" "$WORK_PROJECT"
    chown ga:ga "$WORK_PROJECT"
    echo "Copied sample project to $WORK_PROJECT"
else
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    exit 1
fi

# 3. Remove any previous results
rm -f /home/ga/Projects/sorted_risk_review.xml
rm -f /tmp/task_result.json

# 4. Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 5. Launch ProjectLibre with the project file
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$WORK_PROJECT' > /tmp/projectlibre_launch.log 2>&1 &"

# 6. Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "projectlibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Extra sleep for Java UI to fully render
sleep 8

# 7. Dismiss potential dialogs (Tips, etc.)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 8. Maximize window
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# 9. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="