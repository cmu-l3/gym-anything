#!/bin/bash
echo "=== Setting up Dual-Deploy Conversion Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure working directories exist
mkdir -p /home/ga/Documents/rockets
mkdir -p /home/ga/Documents/exports

ROCKET_FILE="/home/ga/Documents/rockets/simple_model_rocket.ork"

# Ensure the source file is copied and clean
if [ ! -f "$ROCKET_FILE" ]; then
    cp /workspace/data/rockets/simple_model_rocket.ork "$ROCKET_FILE" 2>/dev/null || \
    wget -q "https://raw.githubusercontent.com/openrocket/openrocket/master/core/src/main/resources/datafiles/examples/A%20simple%20model%20rocket.ork" -O "$ROCKET_FILE"
fi

# Reset simulations to outdated to ensure the agent actually runs one
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/simple_model_rocket.ork'
if not os.path.exists(ork_path):
    print("Rocket file not found, skipping sim reset.")
    exit(0)

tmp_path = ork_path + '.tmp'

try:
    with zipfile.ZipFile(ork_path, 'r') as zin:
        xml_bytes = zin.read('rocket.ork')
    
    root = ET.fromstring(xml_bytes.decode('utf-8'))
    
    # Mark all simulations as outdated and remove cached flight data
    sims_elem = root.find('simulations')
    if sims_elem is not None:
        for sim in sims_elem.findall('simulation'):
            sim.set('status', 'outdated')
            fd = sim.find('flightdata')
            if fd is not None:
                sim.remove(fd)
                
    modified_xml = ET.tostring(root, encoding='unicode', xml_declaration=False)
    modified_xml_bytes = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + modified_xml).encode('utf-8')
    
    with zipfile.ZipFile(ork_path, 'r') as zin:
        with zipfile.ZipFile(tmp_path, 'w', zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                if item.filename == 'rocket.ork':
                    zout.writestr(item, modified_xml_bytes)
                else:
                    zout.writestr(item, zin.read(item.filename))
                    
    os.replace(tmp_path, ork_path)
    print("Simulations reset.")
except Exception as e:
    print(f"Error resetting sims: {e}")
PYEOF

# Ensure permissions
chown -R ga:ga /home/ga/Documents/

# Record original file hash for anti-gaming (to detect do-nothing)
md5sum "$ROCKET_FILE" | awk '{print $1}' > /tmp/original_ork_hash.txt

# Start OpenRocket
if ! pgrep -f "OpenRocket.jar" > /dev/null 2>&1; then
    echo "Starting OpenRocket..."
    su - ga -c "export DISPLAY=:1; export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; java -Xms512m -Xmx2048m -jar /opt/openrocket/OpenRocket.jar '$ROCKET_FILE' > /tmp/or.log 2>&1 &"
fi

# Wait for window to appear
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "openrocket\|rocket"; then
        break
    fi
    sleep 1
done

sleep 3

# Maximize and focus OpenRocket
WID=$(DISPLAY=:1 wmctrl -l | grep -i "openrocket\|rocket" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any automatic update checks/startup dialogs
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="