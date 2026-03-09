#!/bin/bash
echo "=== Setting up fix_dependency_chain_errors task ==="

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

# Inject 4 dependency errors into the project file
python3 << 'PYEOF'
import xml.etree.ElementTree as ET

task_file = "/home/ga/Projects/current_task.xml"
ns = "http://schemas.microsoft.com/project"
ET.register_namespace('', ns)

tree = ET.parse(task_file)
root = tree.getroot()
tasks_elem = root.find(f'{{{ns}}}Tasks')

for task in tasks_elem.findall(f'{{{ns}}}Task'):
    uid = task.findtext(f'{{{ns}}}UID', '')

    # Error 1: Task 48 - Change predecessor from UID=44 to UID=43
    if uid == '48':
        for pl in task.findall(f'{{{ns}}}PredecessorLink'):
            pred_uid = pl.findtext(f'{{{ns}}}PredecessorUID', '')
            if pred_uid == '44':
                pl.find(f'{{{ns}}}PredecessorUID').text = '43'
                break

    # Error 2: Task 57 - Change link type of predecessor 55 from FS(1) to SF(3)
    if uid == '57':
        for pl in task.findall(f'{{{ns}}}PredecessorLink'):
            pred_uid = pl.findtext(f'{{{ns}}}PredecessorUID', '')
            if pred_uid == '55':
                type_elem = pl.find(f'{{{ns}}}Type')
                if type_elem is not None:
                    type_elem.text = '3'
                else:
                    te = ET.SubElement(pl, f'{{{ns}}}Type')
                    te.text = '3'
                break

    # Error 3: Task 89 - Remove predecessor UID=88
    if uid == '89':
        for pl in task.findall(f'{{{ns}}}PredecessorLink'):
            pred_uid = pl.findtext(f'{{{ns}}}PredecessorUID', '')
            if pred_uid == '88':
                task.remove(pl)
                break

    # Error 4: Task 111 - Add spurious predecessor UID=109
    if uid == '111':
        new_pl = ET.SubElement(task, f'{{{ns}}}PredecessorLink')
        ET.SubElement(new_pl, f'{{{ns}}}PredecessorUID').text = '109'
        ET.SubElement(new_pl, f'{{{ns}}}Type').text = '1'

tree.write(task_file, encoding='unicode', xml_declaration=True)
print("Injected 4 dependency errors")
PYEOF

# Clean up any previous results
rm -f /tmp/fix_dependency_chain_errors_result.json

# Record task start time
date +%s > /tmp/fix_dependency_chain_errors_start_ts

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
