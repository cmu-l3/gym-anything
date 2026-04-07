#!/bin/bash
set -e
echo "=== Setting up configure_six_day_week task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Projects
rm -f /home/ga/Projects/crunch_schedule.xml

# Define project source and target
SAMPLE_SOURCE="/home/ga/Projects/samples/sample_project.xml"
TASK_PROJECT="/home/ga/Projects/task_start.xml"

# Ensure we start with a fresh, unmodified copy of the sample project
if [ -f "$SAMPLE_SOURCE" ]; then
    cp "$SAMPLE_SOURCE" "$TASK_PROJECT"
    chown ga:ga "$TASK_PROJECT"
    echo "Prepared fresh project file: $TASK_PROJECT"
else
    echo "ERROR: Sample project source not found at $SAMPLE_SOURCE"
    exit 1
fi

# Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# Launch ProjectLibre with the project file
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$TASK_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "projectlibre"; then
        echo "ProjectLibre window detected."
        break
    fi
    sleep 1
done

# Additional sleep to ensure UI is responsive
sleep 5

# Maximize the window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "task_start.xml" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# Dismiss potential startup dialogs (Tip of the Day, etc.)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="