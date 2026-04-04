#!/bin/bash
echo "=== Setting up create_milestone task ==="

# Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# Set up task project file
TASK_PROJECT="/home/ga/Projects/current_task.xml"
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"

if [ -f "$SAMPLE_PROJECT" ]; then
    cp "$SAMPLE_PROJECT" "$TASK_PROJECT"
    echo "Copied sample project: $SAMPLE_PROJECT → $TASK_PROJECT"
else
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    exit 1
fi

chown ga:ga "$TASK_PROJECT"

# Remove any saved result from previous run
rm -f /tmp/task_result.json

# Record task start time
date +%s > /tmp/task_start_time

# Launch ProjectLibre with the project file
echo "Launching ProjectLibre with project file..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$TASK_PROJECT' > /tmp/projectlibre_task.log 2>&1 &"

# Wait for ProjectLibre window
echo "Waiting for ProjectLibre window..."
for i in $(seq 1 40); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "projectlibre\|Commercial Construction\|project.xml"; then
        echo "ProjectLibre window appeared after ${i}s"
        break
    fi
    sleep 1
done

# Additional wait for full UI load (large project with 146 tasks)
sleep 8

# Dismiss any startup dialogs
for attempt in $(seq 1 3); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize the window
DISPLAY=:1 wmctrl -r "project.xml" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Verify ProjectLibre is running
if pgrep -f "projectlibre" > /dev/null 2>&1; then
    echo "ProjectLibre is running"
    WINDOW=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "project" | head -1)
    echo "Window: $WINDOW"
else
    echo "WARNING: ProjectLibre may not have started properly"
    cat /tmp/projectlibre_task.log 2>/dev/null | tail -20
fi

echo ""
echo "Task: Add a new milestone named 'Foundation Work Complete' after task row 44"
echo "       ('Strip column piers and foundation forms') in the Foundations section."
echo "Set the milestone duration to 0 to mark it as a milestone."
echo "The project is open in the Gantt chart view."
echo "=== Task setup complete ==="
