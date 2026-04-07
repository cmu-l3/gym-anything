#!/bin/bash
set -e
echo "=== Setting up add_calendar_holidays task ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Prepare directories
mkdir -p /home/ga/Projects/output
# Ensure output directory is empty of target file to prevent false positives
rm -f /home/ga/Projects/output/project_with_holidays.xml
chown -R ga:ga /home/ga/Projects

# 3. Verify sample project exists
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
if [ ! -f "$SAMPLE_PROJECT" ]; then
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    # Fallback/Recovery: Try to find it in assets
    if [ -f "/workspace/assets/sample_project.xml" ]; then
        cp "/workspace/assets/sample_project.xml" "$SAMPLE_PROJECT"
    else
        exit 1
    fi
fi

# 4. Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# 5. Launch ProjectLibre with the sample project
echo "Launching ProjectLibre..."
# We use setsid to detach from the shell so it survives script exit
su - ga -c "DISPLAY=:1 setsid projectlibre '$SAMPLE_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# 6. Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "projectlibre"; then
        echo "ProjectLibre window detected"
        break
    fi
    sleep 1
done

# Extra wait for Java GUI to fully render and load the project
sleep 10

# 7. Maximize the window (CRITICAL for VLM and agent interaction)
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Fallback: try maximizing by active window if name matching fails
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Focus the window
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# 9. Dismiss any startup dialogs (Tip of the Day, etc)
# Sending Escape a few times helps clear modal popups
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 10. Capture initial state screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="