#!/bin/bash
set -e
echo "=== Setting up Configure Work Day task ==="

# 1. Kill any existing ProjectLibre instances to ensure clean state
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# 2. Prepare the workspace directories
mkdir -p /home/ga/Projects
chown -R ga:ga /home/ga/Projects

# 3. Setup the starting project file
# We use the standard sample project which defaults to 8h days
SAMPLE_SOURCE="/workspace/assets/sample_project.xml"
if [ ! -f "$SAMPLE_SOURCE" ]; then
    # Fallback if asset mount fails - try standard location or create dummy
    SAMPLE_SOURCE="/home/ga/Projects/samples/sample_project.xml"
fi

START_FILE="/home/ga/Projects/construction_schedule.xml"

if [ -f "$SAMPLE_SOURCE" ]; then
    cp "$SAMPLE_SOURCE" "$START_FILE"
    echo "Loaded sample project to $START_FILE"
else
    echo "ERROR: Sample project not found. Creating minimal valid MSPDI..."
    cat > "$START_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?><Project xmlns="http://schemas.microsoft.com/project"><Name>Construction Project</Name><Tasks><Task><UID>1</UID><ID>1</ID><Name>Start</Name></Task></Tasks></Project>
EOF
fi
chown ga:ga "$START_FILE"

# 4. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 5. Launch ProjectLibre with the file
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$START_FILE' > /tmp/projectlibre.log 2>&1 &"

# 6. Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "projectlibre"; then
        echo "Window detected."
        break
    fi
    sleep 1
done
sleep 5  # Allow Java UI to fully render

# 7. Maximize window (Critical for VLM and clicking)
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Also try maximizing by file title if generic title fails
DISPLAY=:1 wmctrl -r "construction_schedule.xml" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Dismiss any potential "Tip of the day" or startup dialogs
# Press Escape a few times
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 9. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="