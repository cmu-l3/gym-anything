#!/bin/bash
echo "=== Setting up schedule_recovery_rebaseline task ==="

# Kill any existing ProjectLibre instances and Firefox (from cached env)
pkill -f "projectlibre" 2>/dev/null || true
pkill -9 -f "firefox" 2>/dev/null || true
su - ga -c "DISPLAY=:1 wmctrl -c Firefox" 2>/dev/null || true
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

# Modify XML: Set task 44 duration to 5 days (40h) so the agent must reduce it to 3 days
# This simulates the pre-delay schedule where form stripping was planned for 5 days
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
    if uid == '44':
        dur = task.find(f'{{{ns}}}Duration')
        if dur is not None:
            dur.text = 'PT40H0M0S'
        rem_dur = task.find(f'{{{ns}}}RemainingDuration')
        if rem_dur is not None:
            rem_dur.text = 'PT40H0M0S'
        print(f"Task 44 duration set to PT40H0M0S (5 days)")
        break

tree.write(task_file, encoding='unicode', xml_declaration=True)
PYEOF

# Create output directory (ensure it exists for the agent to save into)
mkdir -p /home/ga/Projects/output
chown ga:ga /home/ga/Projects/output

# Clean up any previous results
rm -f /home/ga/Projects/output/schedule_recovery.xml
rm -f /tmp/task_result.json
rm -f /tmp/result_project.xml
rm -f /tmp/task_start_time.txt

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Launch ProjectLibre with the project file
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$TASK_PROJECT' > /tmp/projectlibre_task.log 2>&1 &"

# Wait for ProjectLibre window
for i in $(seq 1 50); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "projectlibre\|Commercial Construction\|current_task"; then
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

# Kill Firefox again if it respawned
pkill -9 -f "firefox" 2>/dev/null || true
su - ga -c "DISPLAY=:1 wmctrl -c Firefox" 2>/dev/null || true
sleep 1

# Maximize and bring ProjectLibre to front
su - ga -c "DISPLAY=:1 wmctrl -a 'project.xml'" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "current_task" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "project.xml" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "Commercial Construction" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
