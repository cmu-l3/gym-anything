#!/bin/bash
echo "=== Setting up repair_inspection_sequence task ==="

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

# Inject errors: remove inspection predecessors, delete milestone, corrupt punch list link
python3 << 'PYEOF'
import xml.etree.ElementTree as ET

task_file = "/home/ga/Projects/current_task.xml"
ns = "http://schemas.microsoft.com/project"
ET.register_namespace('', ns)

tree = ET.parse(task_file)
root = tree.getroot()
tasks_elem = root.find(f'{{{ns}}}Tasks')

task_136 = None

for task in tasks_elem.findall(f'{{{ns}}}Task'):
    uid = task.findtext(f'{{{ns}}}UID', '')

    # Remove ALL predecessor links from inspection tasks 138-141
    if uid in ('138', '139', '140', '141'):
        for pl in task.findall(f'{{{ns}}}PredecessorLink'):
            task.remove(pl)

    # Find task 136 (Substantial completion date) for removal
    if uid == '136':
        task_136 = task

    # Change task 142 predecessor from 141 to 135
    if uid == '142':
        for pl in task.findall(f'{{{ns}}}PredecessorLink'):
            pred_uid_elem = pl.find(f'{{{ns}}}PredecessorUID')
            if pred_uid_elem is not None and pred_uid_elem.text == '141':
                pred_uid_elem.text = '135'

# Remove task 136 (Substantial completion date milestone)
if task_136 is not None:
    tasks_elem.remove(task_136)
    print("Removed task 136 (Substantial completion date)")

# Also remove any assignments referencing task 136
assignments_elem = root.find(f'{{{ns}}}Assignments')
if assignments_elem is not None:
    for assignment in assignments_elem.findall(f'{{{ns}}}Assignment'):
        if assignment.findtext(f'{{{ns}}}TaskUID', '') == '136':
            assignments_elem.remove(assignment)

tree.write(task_file, encoding='unicode', xml_declaration=True)
print("Corrupted inspection sequence: removed predecessors from 138-141, deleted 136, changed 142 predecessor")
PYEOF

# Clean up any previous results
rm -f /tmp/repair_inspection_sequence_result.json

# Record task start time
date +%s > /tmp/repair_inspection_sequence_start_ts

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
