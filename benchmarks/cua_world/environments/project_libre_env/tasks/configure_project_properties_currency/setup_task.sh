#!/bin/bash
set -e
echo "=== Setting up task: configure_project_properties_currency ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and clean up previous artifacts
mkdir -p /home/ga/Projects
rm -f /home/ga/Projects/euro_project.xml
rm -f /home/ga/Projects/euro_project.pod
rm -f /tmp/task_result.json

# Ensure sample project exists
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
if [ ! -f "$SAMPLE_PROJECT" ]; then
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    # Fallback copy if available in assets
    if [ -f "/workspace/assets/sample_project.xml" ]; then
        cp "/workspace/assets/sample_project.xml" "$SAMPLE_PROJECT"
    else
        # Critical failure if no sample data
        echo "Creating dummy sample project..."
        mkdir -p /home/ga/Projects/samples
        cat > "$SAMPLE_PROJECT" <<EOF
<?xml version="1.0" encoding="UTF-8"?><Project><Name>Enterprise Software Development Project</Name></Project>
EOF
    fi
fi
chown ga:ga "$SAMPLE_PROJECT"

# Kill any existing ProjectLibre instances to ensure clean state
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# Launch ProjectLibre with the sample project
echo "Launching ProjectLibre with sample project..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$SAMPLE_PROJECT' > /tmp/projectlibre_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ProjectLibre" > /dev/null; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5 # Allow Java UI to fully hydrate

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# Dismiss any potential "Tip of the Day" or startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state (for evidence)
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="