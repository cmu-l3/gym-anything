#!/bin/bash
set -e
echo "=== Setting up add_task_notes task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Projects
mkdir -p /home/ga/Projects/samples
chown -R ga:ga /home/ga/Projects

# Prepare the sample project
SAMPLE_SOURCE="/workspace/assets/sample_project.xml"
SAMPLE_DEST="/home/ga/Projects/samples/sample_project.xml"

if [ -f "$SAMPLE_SOURCE" ]; then
    cp "$SAMPLE_SOURCE" "$SAMPLE_DEST"
    echo "Copied sample project from assets."
elif [ -f "/workspace/scripts/create_sample_project.py" ]; then
    echo "Generating sample project via script..."
    python3 /workspace/scripts/create_sample_project.py "$SAMPLE_DEST"
else
    echo "ERROR: Could not find or create sample project."
    exit 1
fi

chown ga:ga "$SAMPLE_DEST"

# Remove any previous output file to ensure clean state
rm -f /home/ga/Projects/project_with_notes.xml

# Kill any existing instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# Launch ProjectLibre with the sample project
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$SAMPLE_DEST' > /tmp/projectlibre.log 2>&1 &"

# Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "projectlibre\|project"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Wait for UI to load
sleep 5

# Dismiss any startup dialogs (Tip of the Day, etc.)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize the window
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="