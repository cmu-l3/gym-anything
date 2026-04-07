#!/bin/bash
# Setup script for transonic_drag_optimization task
# Copies a two-stage rocket, forces surface finishes to 'rough' and fin cross-sections to 'square'

echo "=== Setting up transonic_drag_optimization task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/transonic_rocket.ork"
# Attempt to use a multi-stage rocket. Fallback to simple if missing.
if [ -f "/workspace/data/rockets/two_stage_high_power_rocket.ork" ]; then
    SOURCE_ORK="/workspace/data/rockets/two_stage_high_power_rocket.ork"
elif [ -f "$ROCKETS_DIR/two_stage_high_power_rocket.ork" ]; then
    SOURCE_ORK="$ROCKETS_DIR/two_stage_high_power_rocket.ork"
else
    SOURCE_ORK="$ROCKETS_DIR/simple_model_rocket.ork"
fi

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove previous output files
rm -f "$ROCKETS_DIR/transonic_rocket_optimized.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/aerodynamic_report.txt" 2>/dev/null || true

# Inject suboptimal aerodynamics: all external components rough, all fins square
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/transonic_rocket.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

ext_tags = ['nosecone', 'bodytube', 'transition', 'trapezoidfinset', 'ellipticalfinset', 'freeformfinset']
fin_tags = ['trapezoidfinset', 'ellipticalfinset', 'freeformfinset']

modified_finishes = 0
modified_crosssections = 0

# Set finishes to rough
for tag in ext_tags:
    for elem in root.iter(tag):
        finish = elem.find('finish')
        if finish is None:
            finish = ET.SubElement(elem, 'finish')
        finish.text = 'rough'
        modified_finishes += 1

# Set cross-sections to square
for tag in fin_tags:
    for elem in root.iter(tag):
        cs = elem.find('crosssection')
        if cs is None:
            cs = ET.SubElement(elem, 'crosssection')
        cs.text = 'square'
        modified_crosssections += 1

# Reset all simulations to outdated
sims_elem = root.find('simulations')
sim_count = 0
if sims_elem is not None:
    for sim in sims_elem.findall('simulation'):
        sim.set('status', 'outdated')
        fd = sim.find('flightdata')
        if fd is not None:
            sim.remove(fd)
        sim_count += 1

print(f"Forced {modified_finishes} finishes to rough")
print(f"Forced {modified_crosssections} fin sets to square cross-section")
print(f"Reset {sim_count} simulations to outdated")

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
echo "task_start_ts=$(date +%s)" > /tmp/transonic_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the modified rocket
launch_openrocket "$TASK_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/transonic_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== transonic_drag_optimization task setup complete ==="