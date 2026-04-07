#!/bin/bash
# Setup script for material_upgrade_for_hpr task

echo "=== Setting up material_upgrade_for_hpr task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

BASE_ORK="$ROCKETS_DIR/hpr_upgrade_base.ork"
SOURCE_ORK="/workspace/data/rockets/simple_model_rocket.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$BASE_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$BASE_ORK"

# Remove any previous output files
rm -f "$ROCKETS_DIR/upgraded_rocket.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/material_upgrade_report.txt" 2>/dev/null || true

# Inject deterministic starting materials (Cardboard, Polystyrene, Balsa)
# and set simulations to outdated.
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/hpr_upgrade_base.ork'
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

def set_material(element, mat_type, density, name):
    mat = element.find('material')
    if mat is None:
        mat = ET.SubElement(element, 'material')
    mat.set('type', mat_type)
    mat.set('density', str(density))
    mat.text = name

# Set body tube to Cardboard
for bt in root.iter('bodytube'):
    set_material(bt, 'bulk', 680.0, 'Cardboard')

# Set nose cone to Polystyrene
for nc in root.iter('nosecone'):
    set_material(nc, 'bulk', 1050.0, 'Polystyrene PS')

# Set fins to Balsa (handle multiple fin types just in case)
for fin_tag in ['trapezoidfinset', 'ellipticalfinset', 'freeformfinset']:
    for fin in root.iter(fin_tag):
        set_material(fin, 'bulk', 130.0, 'Balsa')

# Reset all simulations to outdated
sims_elem = root.find('simulations')
if sims_elem is not None:
    for sim in sims_elem.findall('simulation'):
        sim.set('status', 'outdated')
        fd = sim.find('flightdata')
        if fd is not None:
            sim.remove(fd)

print("Injected baseline materials: Cardboard, Polystyrene, Balsa")

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
echo "task_start_ts=$(date +%s)" > /tmp/material_upgrade_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the baseline rocket
launch_openrocket "$BASE_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot to document starting state
take_screenshot /tmp/material_upgrade_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== material_upgrade_for_hpr task setup complete ==="