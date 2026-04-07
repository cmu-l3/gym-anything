#!/bin/bash
set -e
echo "=== Setting up insert_slack_column_report task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/Projects/critical_path_report.txt
rm -f /tmp/task_result.json

# Kill any existing ProjectLibre instances to ensure clean state
pkill -f "projectlibre" 2>/dev/null || true
sleep 2
pkill -9 -f "projectlibre" 2>/dev/null || true
sleep 1

# Ensure sample project exists
SAMPLE_XML="/home/ga/Projects/samples/sample_project.xml"
if [ ! -f "$SAMPLE_XML" ]; then
    echo "ERROR: Sample project file not found at $SAMPLE_XML"
    # Fallback: try to locate it or fail
    exit 1
fi

# Launch ProjectLibre with the sample project
echo "Launching ProjectLibre..."
# We use setsid to detach, but keeping it simple for the environment
su - ga -c "DISPLAY=:1 setsid projectlibre '$SAMPLE_XML' > /tmp/projectlibre.log 2>&1 &"

# Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "projectlibre"; then
        echo "ProjectLibre window detected."
        break
    fi
    sleep 1
done

# Wait a bit for the project to fully load and UI to settle
sleep 10

# Dismiss potential startup dialogs (Tip of the Day, etc.)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize the window (CRITICAL for visual tasks)
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Ensure focus
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# Capture initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="