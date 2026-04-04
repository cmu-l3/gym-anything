#!/bin/bash
set -e
echo "=== Setting up earthquake_network_link task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Define paths
GE_DIR="/home/ga/.googleearth"
GE_CONFIG_DIR="/home/ga/.config/Google/GoogleEarthPro"

# ============================================================
# Record initial state of myplaces.kml files
# ============================================================
echo "Recording initial state..."

# Create directories if they don't exist
mkdir -p "$GE_DIR" 2>/dev/null || true
mkdir -p "$GE_CONFIG_DIR" 2>/dev/null || true
chown -R ga:ga "$GE_DIR" 2>/dev/null || true
chown -R ga:ga "$GE_CONFIG_DIR" 2>/dev/null || true

# Record initial state for each possible myplaces.kml location
INITIAL_STATE_FILE="/tmp/initial_network_links.json"
python3 << 'PYTHON_EOF'
import json
import os
import xml.etree.ElementTree as ET
from datetime import datetime

def count_network_links(kml_path):
    """Count NetworkLink elements in a KML file."""
    if not os.path.exists(kml_path):
        return {"exists": False, "count": 0, "usgs_present": False, "mtime": 0}
    
    try:
        mtime = os.path.getmtime(kml_path)
        tree = ET.parse(kml_path)
        root = tree.getroot()
        
        count = 0
        usgs_present = False
        
        for elem in root.iter():
            if 'NetworkLink' in elem.tag:
                count += 1
                for child in elem.iter():
                    if 'href' in child.tag and child.text:
                        if 'earthquake.usgs.gov' in child.text:
                            usgs_present = True
        
        return {
            "exists": True,
            "count": count,
            "usgs_present": usgs_present,
            "mtime": mtime
        }
    except Exception as e:
        return {"exists": True, "count": -1, "usgs_present": False, "mtime": 0, "error": str(e)}

paths = [
    "/home/ga/.googleearth/myplaces.kml",
    "/home/ga/.config/Google/GoogleEarthPro/myplaces.kml"
]

initial_state = {
    "timestamp": datetime.now().isoformat(),
    "paths": {}
}

for path in paths:
    initial_state["paths"][path] = count_network_links(path)

with open("/tmp/initial_network_links.json", "w") as f:
    json.dump(initial_state, f, indent=2)

print("Initial state recorded:")
print(json.dumps(initial_state, indent=2))
PYTHON_EOF

# ============================================================
# Remove any existing USGS earthquake network links (clean slate)
# ============================================================
echo "Cleaning up any existing earthquake network links..."

python3 << 'PYTHON_EOF'
import xml.etree.ElementTree as ET
import os
import shutil

paths = [
    "/home/ga/.googleearth/myplaces.kml",
    "/home/ga/.config/Google/GoogleEarthPro/myplaces.kml"
]

for kml_path in paths:
    if not os.path.exists(kml_path):
        continue
    
    try:
        # Backup original
        backup_path = kml_path + ".task_backup"
        shutil.copy2(kml_path, backup_path)
        
        tree = ET.parse(kml_path)
        root = tree.getroot()
        
        # Find and remove NetworkLinks with USGS earthquake URLs
        removed = False
        for parent in root.iter():
            children_to_remove = []
            for child in parent:
                if 'NetworkLink' in child.tag:
                    for descendant in child.iter():
                        if 'href' in descendant.tag and descendant.text:
                            if 'earthquake.usgs.gov' in descendant.text:
                                children_to_remove.append(child)
                                break
            
            for child in children_to_remove:
                parent.remove(child)
                removed = True
                print(f"Removed existing earthquake NetworkLink from {kml_path}")
        
        if removed:
            tree.write(kml_path)
            
    except Exception as e:
        print(f"Note: Could not process {kml_path}: {e}")
PYTHON_EOF

# ============================================================
# Kill any existing Google Earth instances for clean start
# ============================================================
echo "Stopping any existing Google Earth instances..."
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# ============================================================
# Start Google Earth Pro
# ============================================================
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &

# Wait for window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after $i seconds"
        break
    fi
    sleep 1
done

# Give additional time for full initialization
sleep 5

# ============================================================
# Maximize and focus window
# ============================================================
echo "Maximizing Google Earth window..."
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs/tips by pressing Escape
xdotool key Escape 2>/dev/null || true
sleep 0.5
xdotool key Escape 2>/dev/null || true
sleep 0.5

# ============================================================
# Take initial screenshot for evidence
# ============================================================
echo "Capturing initial state screenshot..."
scrot /tmp/task_initial_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_initial_screenshot.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_screenshot.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Add a USGS Earthquake Network Link"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Go to Add → Network Link in the menu bar"
echo "2. Enter the following settings:"
echo "   Name: USGS Earthquakes M2.5+ Past Day"
echo "   Link: https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.kml"
echo "3. Click OK to create the Network Link"
echo "4. Wait for earthquake markers to appear on the globe"
echo ""
echo "The Network Link should appear in the Places panel (left side)"
echo "and earthquake markers should display on the globe."
echo "============================================================"