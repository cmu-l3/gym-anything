#!/bin/bash
set -e
echo "=== Setting up assign_task_specific_calendar task ==="

# 1. Clean up previous run artifacts
rm -f /home/ga/Projects/weekend_work.xml
rm -f /tmp/task_result.json
rm -f /tmp/task_start_time.txt
rm -f /tmp/initial_state.png

# 2. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Prepare the specific project file
# We copy the sample to a working file to ensure a clean state
SAMPLE_SOURCE="/home/ga/Projects/samples/sample_project.xml"
WORKING_FILE="/home/ga/Projects/software_project.xml"

if [ -f "$SAMPLE_SOURCE" ]; then
    cp "$SAMPLE_SOURCE" "$WORKING_FILE"
    chown ga:ga "$WORKING_FILE"
else
    echo "ERROR: Sample project not found at $SAMPLE_SOURCE"
    exit 1
fi

# 4. Launch ProjectLibre with the working file
echo "Launching ProjectLibre..."
# Using setsid to detach, passing the file to open immediately
su - ga -c "DISPLAY=:1 setsid projectlibre '$WORKING_FILE' > /tmp/projectlibre.log 2>&1 &"

# 5. Wait for window to appear
echo "Waiting for application window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ProjectLibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done
# Extra sleep for Java UI to fully render
sleep 5

# 6. Maximize and focus
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# 7. Dismiss any startup dialogs (Tips of the Day, etc)
# Press Escape a couple of times just in case
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 8. Capture initial state
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="