#!/bin/bash
set -e
echo "=== Setting up create_wbs_summary_group task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous results
rm -f /home/ga/Projects/updated_project.xml
rm -f /tmp/task_result.json

# Kill any existing ProjectLibre instances to ensure clean state
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# Verify sample project exists
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
if [ ! -f "$SAMPLE_PROJECT" ]; then
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    # Fallback: Create directory if needed
    mkdir -p /home/ga/Projects/samples
    exit 1
fi

# Ensure output directory exists
mkdir -p /home/ga/Projects
chown -R ga:ga /home/ga/Projects

# Launch ProjectLibre with the sample project
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$SAMPLE_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "projectlibre"; then
        echo "ProjectLibre window detected"
        break
    fi
    sleep 1
done

# Additional sleep to ensure Java UI is fully rendered and ready for input
sleep 8

# Maximize the window (Critical for VLM visibility)
# Try maximizing both the main window and the project window inside it if MDI
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Enterprise Software" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# Dismiss any potential "Tip of the Day" or startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="