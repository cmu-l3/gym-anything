#!/bin/bash
# Setup script for internal_fin_can_structural_modeling task
# Creates a "hollow airframe" by stripping internals from simple_model_rocket.ork

echo "=== Setting up internal_fin_can_structural_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/hollow_airframe.ork"
SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"

if [ ! -f "$SOURCE_ORK" ]; then
    SOURCE_ORK="$ROCKETS_DIR/simple_model_rocket.ork"
fi

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove previous output files
rm -f "$ROCKETS_DIR/fin_can_upgrade.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/fin_can_report.txt" 2>/dev/null || true

# Inject "hollow airframe" state: strip out inner tube, engine block, centering rings, fin tabs
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/hollow_airframe.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

removed_components = 0

# Function to recursively remove targeted elements
def remove_internals(parent):
    global removed_components
    for child in list(parent):
        # Remove structural internals
        if child.tag in ['innertube', 'engineblock', 'centeringring']:
            parent.remove(child)
            removed_components += 1
            continue
        
        # Remove fin tabs
        if child.tag == 'trapezoidfinset' or child.tag == 'freeformfinset' or child.tag == 'ellipticalfinset':
            for fchild in list(child):
                if fchild.tag == 'fintabs':
                    child.remove(fchild)
                    removed_components += 1
        
        # Recurse
        remove_internals(child)

remove_internals(root)

# Reset simulations to outdated since the design mass/aerodynamics changed
sims_elem = root.find('simulations')
if sims_elem is not None:
    for sim in sims_elem.findall('simulation'):
        sim.set('status', 'outdated')

print(f"Stripped {removed_components} internal components to create hollow airframe.")

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
PYEOF

if [ $? -ne 0 ]; then
    echo "FATAL: Python setup failed"
    exit 1
fi

# Record ground truth and timestamp
echo "task_start_ts=$(date +%s)" > /tmp/task_start_time.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the hollow rocket
launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== internal_fin_can_structural_modeling task setup complete ==="