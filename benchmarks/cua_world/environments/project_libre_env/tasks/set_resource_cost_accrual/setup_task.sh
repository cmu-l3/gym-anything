#!/bin/bash
set -e
echo "=== Setting up set_resource_cost_accrual task ==="

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Prepare the project file
# We copy the sample project to a working location to ensure a clean state
SAMPLE_SOURCE="/home/ga/Projects/samples/sample_project.xml"
WORKING_FILE="/home/ga/Projects/development_project.xml"

# Remove any previous output
rm -f /home/ga/Projects/resource_costs.xml

if [ -f "$SAMPLE_SOURCE" ]; then
    cp "$SAMPLE_SOURCE" "$WORKING_FILE"
    chown ga:ga "$WORKING_FILE"
    echo "Prepared working file: $WORKING_FILE"
else
    echo "ERROR: Sample project not found at $SAMPLE_SOURCE"
    exit 1
fi

# 3. Launch ProjectLibre
# Check if already running, if so kill it to ensure fresh state
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

echo "Starting ProjectLibre..."
# Launch with the file directly
su - ga -c "DISPLAY=:1 setsid projectlibre '$WORKING_FILE' > /tmp/projectlibre.log 2>&1 &"

# 4. Wait for window
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "projectlibre"; then
        echo "Application window detected"
        break
    fi
    sleep 1
done
# Extra sleep for Java UI to fully render and load file
sleep 10

# 5. Maximize and focus
# ProjectLibre often has "ProjectLibre" or the filename in the title
DISPLAY=:1 wmctrl -r "projectlibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "projectlibre" 2>/dev/null || true

# 6. Dismiss startup dialogs (Tips of the day, etc)
# Hitting Escape a few times usually clears modal dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="