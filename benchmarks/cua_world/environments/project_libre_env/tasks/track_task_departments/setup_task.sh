#!/bin/bash
set -e
echo "=== Setting up track_task_departments task ==="

# 1. Kill any existing instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# 2. Prepare directories and files
mkdir -p /home/ga/Projects
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"

# Ensure sample project exists (it should be mounted/copied by env setup, but double check)
if [ ! -f "$SAMPLE_PROJECT" ]; then
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    # Fallback generation if missing (safety net)
    mkdir -p /home/ga/Projects/samples
    /workspace/scripts/create_sample_project.py "$SAMPLE_PROJECT" 2>/dev/null || true
fi

# Clean up previous outputs
rm -f /home/ga/Projects/department_tagged.xml
rm -f /tmp/task_result.json

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Launch ProjectLibre with the sample project
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$SAMPLE_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# 5. Wait for window
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "projectlibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5 # Allow project to fully load

# 6. Maximize and focus
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# 7. Dismiss potential dialogs (tips, etc)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 8. Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="