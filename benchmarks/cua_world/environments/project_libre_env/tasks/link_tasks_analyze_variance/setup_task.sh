#!/bin/bash
set -e
echo "=== Setting up link_tasks_analyze_variance task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# Create project directory
mkdir -p /home/ga/Projects
chown -R ga:ga /home/ga/Projects

# Prepare the starting project file
# We start with the sample project but ensure Task 5 has NO predecessors
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
TASK_PROJECT="/home/ga/Projects/variance_task.xml"

if [ -f "$SAMPLE_PROJECT" ]; then
    echo "Creating task project file from sample..."
    
    # Use python to strip any existing predecessors from Task 5 to ensure clean state
    python3 -c "
import xml.etree.ElementTree as ET
import sys

try:
    ET.register_namespace('', 'http://schemas.microsoft.com/project')
    ns = {'p': 'http://schemas.microsoft.com/project'}
    
    tree = ET.parse('$SAMPLE_PROJECT')
    root = tree.getroot()
    
    tasks = root.find('p:Tasks', ns)
    if tasks is not None:
        for task in tasks.findall('p:Task', ns):
            uid = task.find('p:UID', ns)
            if uid is not None and uid.text == '5': # Design Review Milestone
                # Remove all PredecessorLink elements
                for link in task.findall('p:PredecessorLink', ns):
                    task.remove(link)
                print('Cleared predecessors for Task 5')
                
                # Ensure no baseline exists
                for bl in task.findall('p:Baseline', ns):
                    task.remove(bl)
                    
    # Also clear project-level baselines if any
    for task in tasks.findall('p:Task', ns):
        for bl in task.findall('p:Baseline', ns):
            task.remove(bl)
            
    tree.write('$TASK_PROJECT', encoding='UTF-8', xml_declaration=True)
    print('Project file prepared: $TASK_PROJECT')
except Exception as e:
    print(f'Error preparing project file: {e}')
    sys.exit(1)
"
    
    chown ga:ga "$TASK_PROJECT"
else
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    exit 1
fi

# Launch ProjectLibre
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$TASK_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# Wait for window
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ProjectLibre"; then
        echo "Window found"
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# Dismiss any startup dialogs (tips, etc)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="