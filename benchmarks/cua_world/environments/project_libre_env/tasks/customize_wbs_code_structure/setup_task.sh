#!/bin/bash
set -e
echo "=== Setting up customize_wbs_code_structure task ==="

# 1. Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2
pkill -9 -f "projectlibre" 2>/dev/null || true

# 2. Prepare the project file
# We copy the standard sample to a specific task file to ensure a clean start
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
TASK_PROJECT="/home/ga/Projects/wbs_task.xml"
OUTPUT_FILE="/home/ga/Projects/custom_coded_project.xml"

mkdir -p /home/ga/Projects
chown -R ga:ga /home/ga/Projects

if [ -f "$SAMPLE_PROJECT" ]; then
    cp "$SAMPLE_PROJECT" "$TASK_PROJECT"
    echo "Copied sample project to $TASK_PROJECT"
else
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    # Create a dummy file if sample is missing (fallback for testing)
    echo "<Project><Tasks></Tasks></Project>" > "$TASK_PROJECT"
fi

# Ensure output file doesn't exist from previous run
rm -f "$OUTPUT_FILE"

# Set permissions
chown ga:ga "$TASK_PROJECT"

# 3. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 4. Launch ProjectLibre with the task project
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$TASK_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# 5. Wait for window to appear
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "projectlibre"; then
        echo "ProjectLibre window detected"
        break
    fi
    sleep 1
done

# 6. Maximize and focus
sleep 5 # Wait for full load
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# 7. Dismiss startup dialogs (if any)
# Press Escape a few times to clear "Tip of the Day" or similar
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="