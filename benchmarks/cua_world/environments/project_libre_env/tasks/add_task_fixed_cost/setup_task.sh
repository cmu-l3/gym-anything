#!/bin/bash
set -e
echo "=== Setting up task: add_task_fixed_cost ==="

# 1. Anti-gaming: Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Clean state: Ensure output file does not exist
OUTPUT_FILE="/home/ga/Projects/updated_project_with_costs.xml"
rm -f "$OUTPUT_FILE"

# 3. Ensure input data exists
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
if [ ! -f "$SAMPLE_PROJECT" ]; then
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    # Fallback to create it if missing (using the python script in environment)
    if [ -f "/workspace/scripts/create_sample_project.py" ]; then
        python3 /workspace/scripts/create_sample_project.py "$SAMPLE_PROJECT"
    else
        exit 1
    fi
fi

# 4. Kill existing instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# 5. Launch ProjectLibre with the sample project
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$SAMPLE_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# 6. Wait for window
echo "Waiting for ProjectLibre window..."
for i in $(seq 1 60); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "projectlibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# 7. Maximize and focus
sleep 5
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true # Dismiss tips/dialogs

# 8. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="