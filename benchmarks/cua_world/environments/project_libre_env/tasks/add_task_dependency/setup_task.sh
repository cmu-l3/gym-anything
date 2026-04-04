#!/bin/bash
echo "=== Setting up add_task_dependency task ==="

# Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# Set up task project file (fresh copy of sample project)
# Real data: Commercial Construction project (three-story office building) in MSPDI XML format
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

# Remove the FS predecessor link from task 28 (Install storm drainage) to task 27 (Rough grade site)
# This is the dependency the agent needs to add back
python3 << 'PYEOF'
import xml.etree.ElementTree as ET

task_file = "/home/ga/Projects/current_task.xml"
ns = "http://schemas.microsoft.com/project"
ET.register_namespace('', ns)

try:
    tree = ET.parse(task_file)
    root = tree.getroot()

    tasks_elem = root.find(f'{{{ns}}}Tasks')
    removed = False
    for task in tasks_elem.findall(f'{{{ns}}}Task'):
        uid = task.findtext(f'{{{ns}}}UID', '')
        if uid == '28':  # Install storm drainage
            name = task.findtext(f'{{{ns}}}Name', '')
            pred_links = task.findall(f'{{{ns}}}PredecessorLink')
            for pl in pred_links:
                pred_uid = pl.findtext(f'{{{ns}}}PredecessorUID', '')
                if pred_uid == '27':  # Rough grade site (cut and fill)
                    task.remove(pl)
                    removed = True
                    print(f"Removed predecessor link: task 27 -> task 28 ({name})")
                    break
            break

    if not removed:
        print("Warning: Predecessor link 27->28 not found (may already be absent)")

    tree.write(task_file, encoding='unicode', xml_declaration=True)
    print("Project file updated successfully")
except Exception as e:
    print(f"Warning: Could not modify project file: {e}")
PYEOF

# Remove any saved result from previous run
rm -f /tmp/task_result.json

# Record task start time
date +%s > /tmp/task_start_time

# Launch ProjectLibre with the project file
echo "Launching ProjectLibre with commercial construction project..."
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

# Maximize the window for better visibility
DISPLAY=:1 wmctrl -r "project.xml" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Verify ProjectLibre is running with the project
if pgrep -f "projectlibre" > /dev/null 2>&1; then
    echo "ProjectLibre is running"
    WINDOW=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "project" | head -1)
    echo "Window: $WINDOW"
else
    echo "WARNING: ProjectLibre may not have started properly"
    echo "--- ProjectLibre log ---"
    cat /tmp/projectlibre_task.log 2>/dev/null | tail -20
fi

echo ""
echo "Task: Add FS dependency from 'Rough grade site (cut and fill)' (task 27)"
echo "         to 'Install storm drainage' (task 28)"
echo "Find both tasks in the 'Site Grading and Utilities' section."
echo "=== Task setup complete ==="
