#!/bin/bash
set -e
echo "=== Setting up add_task_hyperlinks task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create Projects directory if it doesn't exist
mkdir -p /home/ga/Projects
chown ga:ga /home/ga/Projects

# Ensure sample project is available
SAMPLE_SOURCE="/home/ga/Projects/samples/sample_project.xml"
WORKING_COPY="/home/ga/Projects/current_project.xml"

if [ -f "$SAMPLE_SOURCE" ]; then
    cp "$SAMPLE_SOURCE" "$WORKING_COPY"
    chown ga:ga "$WORKING_COPY"
    echo "Sample project prepared."
else
    echo "ERROR: Sample project not found at $SAMPLE_SOURCE"
    exit 1
fi

# Clean up previous results
rm -f /home/ga/Projects/linked_project.xml

# Ensure ProjectLibre is running
if ! pgrep -f "projectlibre" > /dev/null; then
    echo "Starting ProjectLibre..."
    # Launch with the specific project file
    su - ga -c "DISPLAY=:1 setsid projectlibre '$WORKING_COPY' > /tmp/projectlibre.log 2>&1 &"
    sleep 5
fi

# Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "projectlibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Wait extra time for Java UI to fully render and load file
sleep 5

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Also try maximizing by title if the file name is in title
DISPLAY=:1 wmctrl -r "current_project.xml" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# Dismiss any potential startup dialogs (tips, etc)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take screenshot of initial state (for evidence)
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="