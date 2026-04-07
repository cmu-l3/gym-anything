#!/bin/bash
set -e
echo "=== Setting up group_by_resource_pdf task ==="

# 1. Kill any running ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# 2. Prepare the Desktop directory
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# 3. clean up previous runs
rm -f /home/ga/Desktop/resource_report.pdf
rm -f /tmp/task_result.json

# 4. Set up the project file (fresh copy)
PROJECT_FILE="/home/ga/Projects/current_project.xml"
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"

if [ -f "$SAMPLE_PROJECT" ]; then
    cp "$SAMPLE_PROJECT" "$PROJECT_FILE"
    chown ga:ga "$PROJECT_FILE"
else
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    exit 1
fi

# 5. Record task start time
date +%s > /tmp/task_start_time.txt

# 6. Launch ProjectLibre
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$PROJECT_FILE' > /tmp/projectlibre_task.log 2>&1 &"

# 7. Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "projectlibre"; then
        echo "ProjectLibre window detected"
        break
    fi
    sleep 1
done

# Wait for UI to stabilize
sleep 5

# 8. Maximize window (CRITICAL for visual tasks)
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "project" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 9. Ensure default view (WBS) - usually default on load, but we can verify via screenshot later
# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 10. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="