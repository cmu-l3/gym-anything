#!/bin/bash
set -e
echo "=== Setting up duplicate_retesting_phase task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure ProjectLibre is not running initially
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# Reset the workspace
mkdir -p /home/ga/Projects
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
WORKING_PROJECT="/home/ga/Projects/sample_project.xml"

# Ensure we start with a clean copy of the sample project
if [ -f "$SAMPLE_PROJECT" ]; then
    cp "$SAMPLE_PROJECT" "$WORKING_PROJECT"
    echo "Restored working project from sample."
else
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    exit 1
fi

# Ensure proper ownership
chown ga:ga "$WORKING_PROJECT"

# Remove any previous output file
rm -f "/home/ga/Projects/extended_project.xml"

# Launch ProjectLibre with the sample project
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$WORKING_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ProjectLibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Wait for UI to fully load project
sleep 8

# Maximize window
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "sample_project.xml" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss any potential startup dialogs/tips
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="