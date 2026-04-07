#!/bin/bash
set -e
echo "=== Setting up Add New Resource Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Projects/updated_project.xml
rm -f /tmp/task_result.json

# 3. Prepare the initial project file
# Ensure the sample project exists in the expected location
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
if [ ! -f "$SAMPLE_PROJECT" ]; then
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    # Fallback: check if we can copy it from assets
    if [ -f "/workspace/assets/sample_project.xml" ]; then
        mkdir -p /home/ga/Projects/samples
        cp /workspace/assets/sample_project.xml "$SAMPLE_PROJECT"
        chown ga:ga "$SAMPLE_PROJECT"
    else
        echo "CRITICAL: Could not find sample project source."
        exit 1
    fi
fi

# 4. Launch ProjectLibre
echo "Launching ProjectLibre..."
# Kill any stale instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# Launch with the sample project loaded
su - ga -c "DISPLAY=:1 setsid projectlibre '$SAMPLE_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# 5. Wait for window and maximize
echo "Waiting for ProjectLibre window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ProjectLibre" > /dev/null; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Wait extra time for Java UI to fully render
sleep 5

# Maximize the window (Critical for VLM visibility)
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Ensure it is focused
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# Dismiss any potential "Tip of the Day" or startup dialogs if they appear
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 6. Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="