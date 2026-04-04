#!/bin/bash
echo "=== Setting up fix_resource_assignments task ==="

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

# Inject 4 wrong resource assignments
python3 << 'PYEOF'
import xml.etree.ElementTree as ET

task_file = "/home/ga/Projects/current_task.xml"
ns = "http://schemas.microsoft.com/project"
ET.register_namespace('', ns)

tree = ET.parse(task_file)
root = tree.getroot()
assignments_elem = root.find(f'{{{ns}}}Assignments')

# Map of task UIDs to their wrong resource UIDs
wrong_assignments = {
    '48': '9',    # Steel erection → G.C. Labor Crew (wrong)
    '84': '32',   # Tile installation → Painting Contractor (wrong)
    '90': '29',   # Roofing material → Carpet Contractor (wrong)
    '127': '19',  # HVAC mechanical room → Elevator Contractor (wrong)
}

changed = 0
for assignment in assignments_elem.findall(f'{{{ns}}}Assignment'):
    task_uid = assignment.findtext(f'{{{ns}}}TaskUID', '')
    if task_uid in wrong_assignments:
        resource_elem = assignment.find(f'{{{ns}}}ResourceUID')
        if resource_elem is not None:
            old_val = resource_elem.text
            resource_elem.text = wrong_assignments[task_uid]
            changed += 1

tree.write(task_file, encoding='unicode', xml_declaration=True)
print(f"Changed {changed} resource assignments to wrong contractors")
PYEOF

# Clean up any previous results
rm -f /tmp/fix_resource_assignments_result.json

# Record task start time
date +%s > /tmp/fix_resource_assignments_start_ts

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
