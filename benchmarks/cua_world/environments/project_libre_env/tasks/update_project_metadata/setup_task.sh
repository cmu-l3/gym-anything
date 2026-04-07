#!/bin/bash
echo "=== Setting up update_project_metadata task ==="

# 1. Clean up environment
pkill -f "projectlibre" 2>/dev/null || true
rm -f /home/ga/Projects/compliant_project.xml 2>/dev/null || true
sleep 2

# 2. Prepare Data
# Ensure we have a clean copy of the sample project to work on
SAMPLE_SOURCE="/home/ga/Projects/samples/sample_project.xml"
WORKING_COPY="/home/ga/Projects/current_project.xml"

if [ -f "$SAMPLE_SOURCE" ]; then
    cp "$SAMPLE_SOURCE" "$WORKING_COPY"
    chown ga:ga "$WORKING_COPY"
    echo "Prepared working copy at $WORKING_COPY"
else
    echo "ERROR: Sample project not found at $SAMPLE_SOURCE"
    exit 1
fi

# 3. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Launch Application
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$WORKING_COPY' > /tmp/projectlibre.log 2>&1 &"

# 5. Wait for Window and Configure
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "projectlibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Wait for UI to stabilize
sleep 5

# Dismiss potential dialogs (Esc key)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize Window
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Also try targeting by project name in title
DISPLAY=:1 wmctrl -r "current_project" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus Window
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# 6. Take Initial Screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="