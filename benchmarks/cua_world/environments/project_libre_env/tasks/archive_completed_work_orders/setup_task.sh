#!/bin/bash
set -e
echo "=== Setting up archive_completed_work_orders task ==="

# 1. Kill any existing instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# 2. Prepare directories
PROJECTS_DIR="/home/ga/Projects"
SAMPLES_DIR="$PROJECTS_DIR/samples"
mkdir -p "$SAMPLES_DIR"
chown -R ga:ga "$PROJECTS_DIR"

DATA_FILE="$SAMPLES_DIR/maintenance_log.xml"

# 3. Generate the random maintenance log XML
# We use Python to generate a valid MSPDI XML with random completion statuses
python3 -c '
import random
import xml.etree.ElementTree as ET
from xml.dom import minidom

def generate_xml(filename):
    # Namespace for ProjectLibre/MSPDI
    ns = "http://schemas.microsoft.com/project"
    ET.register_namespace("", ns)
    
    project = ET.Element(f"{{{ns}}}Project")
    ET.SubElement(project, f"{{{ns}}}Name").text = "Maintenance Log"
    
    tasks = ET.SubElement(project, f"{{{ns}}}Tasks")
    
    # Root summary task (UID 0)
    t0 = ET.SubElement(tasks, f"{{{ns}}}Task")
    ET.SubElement(t0, f"{{{ns}}}UID").text = "0"
    ET.SubElement(t0, f"{{{ns}}}ID").text = "0"
    ET.SubElement(t0, f"{{{ns}}}Name").text = "Maintenance Log"
    ET.SubElement(t0, f"{{{ns}}}Summary").text = "1"
    
    locations = ["Lobby", "Room 101", "Room 102", "Cafeteria", "Hallway 2F", "Gym", "Office 305", "Parking Lot", "Server Room", "Roof"]
    actions = ["Replace Light", "Fix Door", "Paint Wall", "Repair Leak", "Check HVAC", "Replace Filter", "Clean Carpet", "Inspect Wiring", "Test Alarm"]
    
    count_total = 0
    count_100 = 0
    count_active = 0
    
    # Generate 30 tasks
    for i in range(1, 31):
        loc = random.choice(locations)
        act = random.choice(actions)
        name = f"{act} - {loc}"
        
        # 40% chance of being complete
        if random.random() < 0.4:
            pct = "100"
            count_100 += 1
        else:
            pct = str(random.choice([0, 0, 25, 50, 75]))
            count_active += 1
            
        count_total += 1
        
        t = ET.SubElement(tasks, f"{{{ns}}}Task")
        ET.SubElement(t, f"{{{ns}}}UID").text = str(i)
        ET.SubElement(t, f"{{{ns}}}ID").text = str(i)
        ET.SubElement(t, f"{{{ns}}}Name").text = name
        ET.SubElement(t, f"{{{ns}}}PercentComplete").text = pct
        ET.SubElement(t, f"{{{ns}}}Duration").text = "PT8H0M0S"
        ET.SubElement(t, f"{{{ns}}}Start").text = "2025-01-01T08:00:00"
        ET.SubElement(t, f"{{{ns}}}Finish").text = "2025-01-01T17:00:00"
        ET.SubElement(t, f"{{{ns}}}Summary").text = "0"

    # Save XML
    tree = ET.ElementTree(project)
    tree.write(filename, encoding="UTF-8", xml_declaration=True)
    
    # Save counts for verification
    import json
    with open("/tmp/initial_counts.json", "w") as f:
        json.dump({
            "total": count_total,
            "completed": count_100,
            "active": count_active
        }, f)
    
    print(f"Generated {filename}: Total={count_total}, Complete={count_100}, Active={count_active}")

generate_xml("'$DATA_FILE'")
'

# 4. Set permissions
chown ga:ga "$DATA_FILE"
chmod 666 "$DATA_FILE"
chown ga:ga /tmp/initial_counts.json
chmod 666 /tmp/initial_counts.json

# 5. Record start time
date +%s > /tmp/task_start_time.txt

# 6. Launch ProjectLibre and load data
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$DATA_FILE' > /tmp/projectlibre_task.log 2>&1 &"

# 7. Wait for window
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "projectlibre"; then
        echo "ProjectLibre window detected"
        break
    fi
    sleep 1
done
sleep 5

# 8. Maximize window
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 9. Dismiss potential dialogs (sometimes ProjectLibre shows a tip or welcome dialog)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 10. Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="