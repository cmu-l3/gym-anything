#!/bin/bash
set -e
echo "=== Setting up Generate Milestone Report task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Define paths
PROJECT_DIR="/home/ga/Projects"
SAMPLE_PROJECT="${PROJECT_DIR}/samples/sample_project.xml"
OUTPUT_FILE="${PROJECT_DIR}/milestones.pdf"

# Ensure clean state
rm -f "$OUTPUT_FILE"
rm -f /tmp/task_result.json

# Ensure ProjectLibre is not running
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# Launch ProjectLibre with the sample project
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$SAMPLE_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "projectlibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Additional wait for Java UI to fully load
sleep 5

# Dismiss any startup dialogs (Tips of the day, etc)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize window (Critical for finding UI elements)
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="