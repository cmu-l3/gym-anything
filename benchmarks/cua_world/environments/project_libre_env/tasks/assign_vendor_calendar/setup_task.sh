#!/bin/bash
set -e
echo "=== Setting up assign_vendor_calendar task ==="

# Source task utilities if available, otherwise define basics
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
pkill -f "java" 2>/dev/null || true
sleep 2

# Prepare working project file
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
WORKING_PROJECT="/home/ga/Projects/current_project.xml"
OUTPUT_PROJECT="/home/ga/Projects/vendor_schedule_project.xml"

# Ensure clean state
rm -f "$OUTPUT_PROJECT"
rm -f /tmp/task_result.json

if [ -f "$SAMPLE_PROJECT" ]; then
    cp "$SAMPLE_PROJECT" "$WORKING_PROJECT"
    chown ga:ga "$WORKING_PROJECT"
    echo "Copied sample project to $WORKING_PROJECT"
else
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    # Fallback for robustness: create a minimal valid MSPDI XML if sample missing
    cat > "$WORKING_PROJECT" <<EOF
<?xml version="1.0" encoding="UTF-8"?><Project xmlns="http://schemas.microsoft.com/project"><Tasks><Task><UID>11</UID><ID>11</ID><Name>Security Audit</Name></Task></Tasks></Project>
EOF
    chown ga:ga "$WORKING_PROJECT"
fi

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Launch ProjectLibre
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$WORKING_PROJECT' > /tmp/projectlibre_task.log 2>&1 &"

# Wait for window
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "projectlibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Extra sleep for Java loading
sleep 8

# Dismiss potential dialogs (tips, etc.)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize window
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="