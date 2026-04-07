#!/bin/bash
set -e
echo "=== Setting up generate_top_cost_tasks_report task ==="

# Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Set up task project file (fresh copy of sample project)
TASK_PROJECT="/home/ga/Projects/sample_project.xml"
SAMPLE_SOURCE="/home/ga/Projects/samples/sample_project.xml"

# Ensure clean state for the project file
if [ -f "$SAMPLE_SOURCE" ]; then
    cp "$SAMPLE_SOURCE" "$TASK_PROJECT"
    echo "Copied sample project to $TASK_PROJECT"
else
    echo "ERROR: Sample project not found at $SAMPLE_SOURCE"
    exit 1
fi
chown ga:ga "$TASK_PROJECT"

# Remove any previous output file
rm -f "/home/ga/Desktop/top_cost_report.pdf"
rm -f "/tmp/top_cost_report.pdf"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Launch ProjectLibre with the sample project
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$TASK_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "projectlibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Wait for UI to settle
sleep 5

# Dismiss startup dialogs (Tips of the day, etc.)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize window
DISPLAY=:1 wmctrl -r "projectlibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="