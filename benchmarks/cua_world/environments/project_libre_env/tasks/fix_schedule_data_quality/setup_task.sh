#!/bin/bash
echo "=== Setting up fix_schedule_data_quality task ==="

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

# Inject 5 data quality errors
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

    # Error 1: Task 17 - Steel fab duration 480h → 40h (impossibly short)
    if uid == '17':
        dur = task.find(f'{{{ns}}}Duration')
        if dur is not None:
            dur.text = 'PT40H0M0S'
        rem_dur = task.find(f'{{{ns}}}RemainingDuration')
        if rem_dur is not None:
            rem_dur.text = 'PT40H0M0S'

    # Error 2: Task 8 - Shop drawings duration 80h → 800h (impossibly long)
    if uid == '8':
        dur = task.find(f'{{{ns}}}Duration')
        if dur is not None:
            dur.text = 'PT800H0M0S'
        rem_dur = task.find(f'{{{ns}}}RemainingDuration')
        if rem_dur is not None:
            rem_dur.text = 'PT800H0M0S'

    # Error 3: Task 55 - Remove all predecessors
    if uid == '55':
        for pl in task.findall(f'{{{ns}}}PredecessorLink'):
            task.remove(pl)

    # Error 4: Task 39 - Add negative lag (-60 days = -28800000 tenths of minutes)
    # In MSPDI, LagDuration is in tenths of minutes, so -480h = -480*60*10 = -288000
    # Actually, MSPDI lag format is PT-480H0M0S or similar. Let's use the duration format.
    if uid == '39':
        for pl in task.findall(f'{{{ns}}}PredecessorLink'):
            pred_uid = pl.findtext(f'{{{ns}}}PredecessorUID', '')
            if pred_uid == '38':
                # Add negative lag
                lag_elem = pl.find(f'{{{ns}}}LinkLag')
                if lag_elem is None:
                    lag_elem = ET.SubElement(pl, f'{{{ns}}}LinkLag')
                lag_elem.text = '-2880000'  # -480 hours in tenths of minutes
                lag_dur = pl.find(f'{{{ns}}}LagFormat')
                if lag_dur is None:
                    lag_dur = ET.SubElement(pl, f'{{{ns}}}LagFormat')
                lag_dur.text = '7'  # days format

    # Error 5: Task 82 - Exterior masonry duration 200h → 16h (impossibly short)
    if uid == '82':
        dur = task.find(f'{{{ns}}}Duration')
        if dur is not None:
            dur.text = 'PT16H0M0S'
        rem_dur = task.find(f'{{{ns}}}RemainingDuration')
        if rem_dur is not None:
            rem_dur.text = 'PT16H0M0S'

tree.write(task_file, encoding='unicode', xml_declaration=True)
print("Injected 5 data quality errors")
PYEOF

# Clean up any previous results
rm -f /tmp/fix_schedule_data_quality_result.json

# Record task start time
date +%s > /tmp/fix_schedule_data_quality_start_ts

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
