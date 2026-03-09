#!/bin/bash
echo "=== Setting up add_security_systems_phase task ==="

# Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# Set up task project file (fresh copy of sample project)
TASK_PROJECT="/home/ga/Projects/current_task.xml"
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"

if [ -f "$SAMPLE_PROJECT" ]; then
    cp "$SAMPLE_PROJECT" "$TASK_PROJECT"
    echo "Copied sample project to $TASK_PROJECT"
else
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    exit 1
fi

chown ga:ga "$TASK_PROJECT"

# Record baseline task count for verification
python3 << 'PYEOF'
import xml.etree.ElementTree as ET

ns = "http://schemas.microsoft.com/project"
tree = ET.parse("/home/ga/Projects/current_task.xml")
root = tree.getroot()
tasks = root.find(f'{{{ns}}}Tasks')
count = len(tasks.findall(f'{{{ns}}}Task'))
print(f"Baseline task count: {count}")
with open('/tmp/add_security_baseline_count', 'w') as f:
    f.write(str(count))
PYEOF

# Clean up any previous results
rm -f /tmp/add_security_systems_phase_result.json

# Record task start time
date +%s > /tmp/add_security_systems_phase_start_ts

# Launch ProjectLibre with the project file
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$TASK_PROJECT' > /tmp/projectlibre_task.log 2>&1 &"

# Wait for ProjectLibre window
for i in $(seq 1 40); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "projectlibre\|Commercial Construction\|project.xml"; then
        echo "ProjectLibre window appeared after ${i}s"
        break
    fi
    sleep 1
done

sleep 8

# Dismiss startup dialogs
for attempt in $(seq 1 3); do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize window
DISPLAY=:1 wmctrl -r "project.xml" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

echo "=== Setup Complete ==="
