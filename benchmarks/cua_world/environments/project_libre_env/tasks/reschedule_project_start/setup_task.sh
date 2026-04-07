#!/bin/bash
set -e
echo "=== Setting up reschedule_project_start task ==="

# 1. Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# 2. Prepare the sample project
# We use the standard sample provided in the environment
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
if [ ! -f "$SAMPLE_PROJECT" ]; then
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    # Fallback: create directory if needed (though env should have it)
    mkdir -p /home/ga/Projects/samples
    exit 1
fi

# Ensure output directory exists and is clean
mkdir -p /home/ga/Projects
rm -f /home/ga/Projects/updated_project.xml

# 3. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
md5sum "$SAMPLE_PROJECT" | awk '{print $1}' > /tmp/original_project_md5.txt

# 4. Launch ProjectLibre with the sample project
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$SAMPLE_PROJECT' > /tmp/projectlibre_launch.log 2>&1 &"

# 5. Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ProjectLibre"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# 6. Window management (Maximize and Focus)
# Wait a bit for the UI to fully render
sleep 5

# Attempt to maximize
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# 7. Dismiss startup dialogs (Tips, etc.)
# Press Escape a few times to close any "Tip of the Day" or welcome dialogs
echo "Dismissing dialogs..."
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="