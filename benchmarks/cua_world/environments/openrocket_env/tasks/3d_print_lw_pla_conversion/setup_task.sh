#!/bin/bash
# Setup script for 3d_print_lw_pla_conversion task

echo "=== Setting up 3d_print_lw_pla_conversion task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="/home/ga/Documents/rockets/janus_29mm.ork"
OUTPUT_ORK="/home/ga/Documents/rockets/janus_lw_pla.ork"
REPORT_FILE="/home/ga/Documents/exports/lw_pla_report.txt"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure the source file exists (download if missing from workspace data)
if [ ! -f "$SOURCE_ORK" ]; then
    echo "Downloading janus_29mm.ork..."
    wget -q "https://raw.githubusercontent.com/3dp-rocket/rockets/master/janus/OpenRocket-29mm.ork" -O "$SOURCE_ORK"
fi
chown ga:ga "$SOURCE_ORK"

# Remove any previous output files
rm -f "$OUTPUT_ORK" 2>/dev/null || true
rm -f "$REPORT_FILE" 2>/dev/null || true

# Reset simulations in the base file so the agent must re-run them
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/janus_29mm.ork'
if not os.path.exists(ork_path):
    exit(0)
tmp_path = ork_path + '.tmp'

with zipfile.ZipFile(ork_path, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

# Reset all simulations to outdated
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
PYEOF

# Record ground truth timestamps
echo "task_start_ts=$(date +%s)" > /tmp/lw_pla_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the source rocket
launch_openrocket "$SOURCE_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot to document starting state
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== 3d_print_lw_pla_conversion task setup complete ==="