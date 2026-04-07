#!/bin/bash
set -e
echo "=== Setting up Backward Scheduling Task ==="

# 1. Cleanup previous artifacts
rm -f /home/ga/Projects/jit_schedule.xml
rm -f /tmp/task_result.json
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# 2. Prepare Source Data
# We use the standard sample project which defaults to Forward Scheduling
SOURCE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
WORKING_PROJECT="/home/ga/Projects/logistics_project.xml"

mkdir -p /home/ga/Projects
if [ -f "$SOURCE_PROJECT" ]; then
    cp "$SOURCE_PROJECT" "$WORKING_PROJECT"
    chown ga:ga "$WORKING_PROJECT"
else
    echo "ERROR: Sample project not found at $SOURCE_PROJECT"
    # Fallback creation if sample missing (should not happen in correct env)
    echo "<Project><Tasks></Tasks></Project>" > "$WORKING_PROJECT"
    chown ga:ga "$WORKING_PROJECT"
fi

# 3. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 4. Launch ProjectLibre
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$WORKING_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# 5. Wait for Window and Maximize
echo "Waiting for window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "projectlibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Extra sleep for Java UI to render
sleep 5

# Dismiss tips/dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Ensure the specific project window inside is also maximized/focused if child window exists
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# 6. Initial Screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="