#!/bin/bash
set -e
echo "=== Setting up set_project_baseline task ==="

# 1. Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# 2. Prepare the project file
# We use a specific name 'enterprise_project.xml' to match the scenario
SOURCE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
TASK_PROJECT="/home/ga/Projects/enterprise_project.xml"
OUTPUT_PROJECT="/home/ga/Projects/baseline_project.xml"

# Ensure clean slate
rm -f "$TASK_PROJECT"
rm -f "$OUTPUT_PROJECT"
rm -f /tmp/task_result.json

if [ -f "$SOURCE_PROJECT" ]; then
    cp "$SOURCE_PROJECT" "$TASK_PROJECT"
    echo "Prepared project file: $TASK_PROJECT"
else
    echo "ERROR: Sample project not found at $SOURCE_PROJECT"
    exit 1
fi

# Set ownership
chown ga:ga "$TASK_PROJECT"
mkdir -p /home/ga/Projects
chown ga:ga /home/ga/Projects

# 3. Record task start time and initial file hash (for anti-gaming)
date +%s > /tmp/task_start_time
md5sum "$TASK_PROJECT" | cut -d' ' -f1 > /tmp/initial_project_hash.txt

# 4. Launch ProjectLibre with the project loaded
echo "Launching ProjectLibre..."
# We use setsid to detach, but keeping it simple for the container environment
su - ga -c "DISPLAY=:1 setsid projectlibre '$TASK_PROJECT' > /tmp/projectlibre_task.log 2>&1 &"

# 5. Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "projectlibre"; then
        echo "ProjectLibre window detected"
        break
    fi
    sleep 1
done

# Extra sleep to ensure Java UI is fully rendered and project is loaded
sleep 10

# 6. Maximize window (Critical for VLM visibility)
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Also try maximizing by specific window title if project is loaded
DISPLAY=:1 wmctrl -r "enterprise_project" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Dismiss potential startup dialogs ("Tip of the day", "Welcome", etc.)
# Sending Escape a few times helps clear these
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="