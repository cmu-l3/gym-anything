#!/bin/bash
set -e
echo "=== Setting up apply_multirate_resource_costing task ==="

# 1. Kill any existing ProjectLibre instances
pkill -f "projectlibre" 2>/dev/null || true
sleep 2

# 2. Prepare the project file
# We use the sample project but ensure specific initial state
SAMPLE_PROJECT="/home/ga/Projects/samples/sample_project.xml"
TASK_PROJECT="/home/ga/Projects/multirate_task.xml"

if [ ! -f "$SAMPLE_PROJECT" ]; then
    echo "ERROR: Sample project not found at $SAMPLE_PROJECT"
    # Try to find it in assets or fallback
    if [ -f "/workspace/assets/sample_project.xml" ]; then
        cp "/workspace/assets/sample_project.xml" "$SAMPLE_PROJECT"
    else
        echo "FATAL: Could not locate sample_project.xml"
        exit 1
    fi
fi

cp "$SAMPLE_PROJECT" "$TASK_PROJECT"
chown ga:ga "$TASK_PROJECT"

# 3. Clean up the project file state using Python
# Ensure Alice Johnson is NOT assigned to Security Audit initially
# Ensure Alice Johnson does NOT have Rate Table B defined initially
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import sys

ns = "http://schemas.microsoft.com/project"
ET.register_namespace('', ns)
file_path = "/home/ga/Projects/multirate_task.xml"

try:
    tree = ET.parse(file_path)
    root = tree.getroot()
    
    # 1. Find Resource UIDs
    alice_uid = None
    resources = root.find(f'{{{ns}}}Resources')
    if resources is not None:
        for res in resources.findall(f'{{{ns}}}Resource'):
            name = res.findtext(f'{{{ns}}}Name', '')
            if 'Alice Johnson' in name:
                alice_uid = res.findtext(f'{{{ns}}}UID')
                # Ensure only Rate Table A exists (remove others if present)
                rates = res.findall(f'{{{ns}}}Rate')
                for rate in rates:
                    table_idx = rate.findtext(f'{{{ns}}}RateTable')
                    if table_idx != '0':
                        res.remove(rate)
                break
    
    # 2. Find Task UIDs
    audit_task_uid = None
    tasks = root.find(f'{{{ns}}}Tasks')
    if tasks is not None:
        for task in tasks.findall(f'{{{ns}}}Task'):
            name = task.findtext(f'{{{ns}}}Name', '')
            if 'Security Audit' in name:
                audit_task_uid = task.findtext(f'{{{ns}}}UID')
                break

    # 3. Remove Assignment if it exists
    if alice_uid and audit_task_uid:
        assignments = root.find(f'{{{ns}}}Assignments')
        if assignments is not None:
            to_remove = []
            for asn in assignments.findall(f'{{{ns}}}Assignment'):
                t_uid = asn.findtext(f'{{{ns}}}TaskUID')
                r_uid = asn.findtext(f'{{{ns}}}ResourceUID')
                if t_uid == audit_task_uid and r_uid == alice_uid:
                    to_remove.append(asn)
            
            for item in to_remove:
                assignments.remove(item)
                print(f"Removed existing assignment of Alice to Security Audit")

    tree.write(file_path, encoding='unicode', xml_declaration=True)
    print("Project file cleaned successfully")

except Exception as e:
    print(f"Error modifying XML: {e}")
    sys.exit(1)
PYEOF

# 4. Record anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# 5. Launch ProjectLibre
echo "Launching ProjectLibre..."
su - ga -c "DISPLAY=:1 setsid projectlibre '$TASK_PROJECT' > /tmp/projectlibre.log 2>&1 &"

# 6. Wait for window
echo "Waiting for ProjectLibre window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "projectlibre"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5

# 7. Dismiss dialogs and maximize
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "ProjectLibre" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ProjectLibre" 2>/dev/null || true

# 8. Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="