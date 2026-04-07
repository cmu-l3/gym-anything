#!/bin/bash
set -e
echo "=== Setting up export_critical_path_report task ==="

# 1. Clean up previous runs
pkill -f "projectlibre" 2>/dev/null || true
rm -f /home/ga/Projects/critical_path_report.pdf 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 2. Prepare Project File
# Copy sample to a working file to avoid corrupting the original sample
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
WORK_PROJECT="/home/ga/Projects/project.xml"

if [ -f "$SAMPLE_PROJECT" ]; then
    cp "$SAMPLE_PROJECT" "$WORK_PROJECT"
    chown ga:ga "$WORK_PROJECT"
    echo "Prepared project file: $WORK_PROJECT"
else
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    exit 1
fi

# 3. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 4. Launch Application
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$WORK_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# 5. Wait for Window
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ProjectLibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5 # Extra wait for Java UI to render

# 6. Maximize Window (Crucial for VLM visibility)
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# 7. Dismiss potential startup dialogs
# Hit Escape a few times to clear "Tip of the Day" or "Welcome"
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="