#!/bin/bash
set -e
echo "=== Setting up Summit Identification Denali Task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create required directories
mkdir -p /home/ga/.googleearth
chown -R ga:ga /home/ga/.googleearth 2>/dev/null || true

# Backup existing myplaces.kml and record initial state
MYPLACES="/home/ga/.googleearth/myplaces.kml"
if [ -f "$MYPLACES" ]; then
    cp "$MYPLACES" "$MYPLACES.backup.$(date +%s)"
    
    # Remove any existing Denali-related placemarks to ensure clean state
    python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import os
import re

kml_path = "/home/ga/.googleearth/myplaces.kml"
if os.path.exists(kml_path):
    try:
        ET.register_namespace('', 'http://www.opengis.net/kml/2.2')
        ET.register_namespace('gx', 'http://www.google.com/kml/ext/2.2')
        ET.register_namespace('atom', 'http://www.w3.org/2005/Atom')
        
        tree = ET.parse(kml_path)
        root = tree.getroot()
        
        # Find and remove Denali/summit placemarks
        ns = {'kml': 'http://www.opengis.net/kml/2.2'}
        removed_count = 0
        
        def remove_denali_placemarks(element):
            global removed_count
            for child in list(element):
                if child.tag.endswith('Placemark'):
                    name_elem = child.find('.//{http://www.opengis.net/kml/2.2}name')
                    if name_elem is not None and name_elem.text:
                        name_lower = name_elem.text.lower()
                        if 'denali' in name_lower or 'summit' in name_lower:
                            element.remove(child)
                            removed_count += 1
                            continue
                remove_denali_placemarks(child)
        
        remove_denali_placemarks(root)
        
        if removed_count > 0:
            tree.write(kml_path, xml_declaration=True, encoding='UTF-8')
            print(f"Removed {removed_count} existing Denali-related placemark(s)")
    except Exception as e:
        print(f"Warning: Could not clean existing placemarks: {e}")
PYEOF
fi

# Record initial KML hash for anti-gaming verification
if [ -f "$MYPLACES" ]; then
    md5sum "$MYPLACES" > /tmp/initial_kml_hash.txt 2>/dev/null || echo "none" > /tmp/initial_kml_hash.txt
    INITIAL_SIZE=$(stat -c %s "$MYPLACES" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c %Y "$MYPLACES" 2>/dev/null || echo "0")
else
    echo "none" > /tmp/initial_kml_hash.txt
    INITIAL_SIZE="0"
    INITIAL_MTIME="0"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "kml_exists": $([ -f "$MYPLACES" ] && echo "true" || echo "false"),
    "kml_size": $INITIAL_SIZE,
    "kml_mtime": $INITIAL_MTIME,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_denali.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth Pro window detected"
        break
    fi
    sleep 2
done

# Give it more time to fully load
sleep 5

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Try to dismiss any startup dialogs or tips
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "============================================================"
echo "TASK: Identify and Mark Highest Elevation Point"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to Denali National Park, Alaska"
echo "2. Find the highest peak (Mount Denali)"
echo "3. Create a placemark named 'Denali Summit' at the summit"
echo "4. Include the elevation in the description (~20,310 ft)"
echo "5. Save the placemark to My Places"
echo ""
echo "Tip: The summit is at approximately 63.07°N, 151.01°W"
echo "============================================================"
echo ""
echo "=== Task setup complete ==="