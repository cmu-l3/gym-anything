#!/bin/bash
# Setup script for parasitic_drag_aerodynamic_optimization task

echo "=== Setting up parasitic_drag_aerodynamic_optimization task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

START_ORK="/home/ga/Documents/rockets/drag_heavy_rocket.ork"
SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"
# Fallback to home dir if workspace data doesn't exist
if [ ! -f "$SOURCE_ORK" ]; then
    SOURCE_ORK="/home/ga/Documents/rockets/simple_model_rocket.ork"
fi

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$START_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$START_ORK"

# Remove previous output files
rm -f "$EXPORTS_DIR/aerodynamic_report.txt" 2>/dev/null || true
rm -f "$ROCKETS_DIR/optimized_rocket.ork" 2>/dev/null || true

# Inject "dirty" aerodynamics: Unfinished surfaces, Square fins, G80 motor, remove existing sims
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/drag_heavy_rocket.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Set all structural external components to 'unfinished'
for comp in ['nosecone', 'bodytube', 'trapezoidfinset', 'freeformfinset', 'transition']:
    for elem in root.iter(comp):
        finish = elem.find('finish')
        if finish is None:
            finish = ET.SubElement(elem, 'finish')
        finish.text = 'unfinished'

# Set fin cross sections to 'square'
for elem in root.iter('trapezoidfinset'):
    cs = elem.find('crosssection')
    if cs is None:
        cs = ET.SubElement(elem, 'crosssection')
    cs.text = 'square'

# Change motor to G80 to make it go fast (exaggerates drag effects)
for motor in root.iter('motor'):
    desig = motor.find('designation')
    if desig is not None:
        desig.text = 'G80'

# Ensure launch lug exists (simple_model_rocket usually has one, but let's make sure it's prominent)
# If missing, we won't manually add XML here to avoid breaking schema, simple_model_rocket has it.

# Remove all existing simulations so agent starts fresh
sims = root.find('simulations')
if sims is not None:
    for sim in list(sims.findall('simulation')):
        sims.remove(sim)

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
print("Injected sub-optimal aerodynamics into starting design.")
PYEOF

if [ $? -ne 0 ]; then
    echo "FATAL: Python setup failed"
    exit 1
fi

# Record ground truth timestamps
echo "task_start_ts=$(date +%s)" > /tmp/aerodynamic_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the modified rocket
launch_openrocket "$START_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== parasitic_drag_aerodynamic_optimization task setup complete ==="