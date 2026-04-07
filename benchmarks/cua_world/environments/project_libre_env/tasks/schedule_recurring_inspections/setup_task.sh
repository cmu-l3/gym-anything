#!/bin/bash
set -e
echo "=== Setting up schedule_recurring_inspections task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Projects directory exists
mkdir -p /home/ga/Projects
chown -R ga:ga /home/ga/Projects

# Prepare the starting project file
# We use the standard sample project but copy it to a working location
SOURCE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
WORKING_PROJECT="/home/ga/Projects/current_project.xml"

if [ -f "$SOURCE_PROJECT" ]; then
    cp "$SOURCE_PROJECT" "$WORKING_PROJECT"
    echo "Copied sample project to $WORKING_PROJECT"
else
    echo "ERROR: Sample project not found at $SOURCE_PROJECT"
    # Create a dummy one if missing to prevent complete fail (though strictly should fail)
    echo '<Project><Tasks></Tasks></Project>' > "$WORKING_PROJECT"
fi
chown ga:ga "$WORKING_PROJECT"

# Remove any previous output file
rm -f /home/ga/Projects/safety_schedule.xml

# Kill any running ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# Launch ProjectLibre with the working project
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$WORKING_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ProjectLibre" > /dev/null; then
        echo "ProjectLibre window detected."
        break
    fi
    sleep 1
done

# Wait a bit for the project to fully load
sleep 5

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# Dismiss any startup dialogs (Tips of the day, etc)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state (for evidence)
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="