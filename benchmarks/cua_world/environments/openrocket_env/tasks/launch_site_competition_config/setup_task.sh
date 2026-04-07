#!/bin/bash
echo "=== Setting up launch_site_competition_config task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

ROCKETS_DIR="/home/ga/Documents/rockets"
EXPORTS_DIR="/home/ga/Documents/exports"
SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"
STARTING_ORK="$ROCKETS_DIR/dual_parachute_deployment.ork"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure clean state (remove any artifacts from previous runs)
rm -f "$ROCKETS_DIR/competition_ready.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/pre_launch_briefing.txt" 2>/dev/null || true

# Copy source .ork and forcefully reset all simulation parameters to defaults
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

source_ork = '/workspace/data/rockets/dual_parachute_deployment.ork'
dest_ork = '/home/ga/Documents/rockets/dual_parachute_deployment.ork'

# Fallback to alternative source if workspace is not mounted
if not os.path.exists(source_ork):
    source_ork = '/home/ga/Documents/rockets/dual_parachute_deployment.ork'
    if not os.path.exists(source_ork):
        # We need this file, try to download if missing
        os.system('wget -q "https://raw.githubusercontent.com/openrocket/openrocket/master/core/src/main/resources/datafiles/examples/Dual%20parachute%20deployment.ork" -O ' + source_ork)

tmp_path = dest_ork + '.tmp'

# Read source
with zipfile.ZipFile(source_ork, 'r') as zin:
    xml_bytes = zin.read('rocket.ork')

root = ET.fromstring(xml_bytes.decode('utf-8'))

sims_elem = root.find('simulations')
if sims_elem is not None:
    for sim in sims_elem.findall('simulation'):
        sim.set('status', 'outdated')
        conds = sim.find('conditions')
        if conds is None:
            conds = ET.SubElement(sim, 'conditions')
            
        # Clear existing specific tags
        for tag in ['launchaltitude', 'launchrodlength', 'launchrodangle', 
                    'launchlatitude', 'launchlongitude', 'windaverage', 'windturbulence']:
            el = conds.find(tag)
            if el is not None:
                conds.remove(el)
        
        # Inject standard sea-level / zeroed defaults
        ET.SubElement(conds, 'launchaltitude').text = '0.0'
        ET.SubElement(conds, 'launchrodlength').text = '1.0'
        ET.SubElement(conds, 'launchrodangle').text = '0.0'
        ET.SubElement(conds, 'launchlatitude').text = '0.0'
        ET.SubElement(conds, 'launchlongitude').text = '0.0'
        ET.SubElement(conds, 'windaverage').text = '2.0'
        ET.SubElement(conds, 'windturbulence').text = '0.1'

        # Remove existing flight data to force re-simulation
        fd = sim.find('flightdata')
        if fd is not None:
            sim.remove(fd)

modified_xml = ET.tostring(root, encoding='unicode', xml_declaration=False)
modified_xml_bytes = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + modified_xml).encode('utf-8')

with zipfile.ZipFile(source_ork, 'r') as zin:
    with zipfile.ZipFile(tmp_path, 'w', zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            if item.filename == 'rocket.ork':
                zout.writestr(item, modified_xml_bytes)
            else:
                zout.writestr(item, zin.read(item.filename))

os.replace(tmp_path, dest_ork)
PYEOF

chown ga:ga "$STARTING_ORK"

# Save the MD5 hash of the starting file to detect if the agent just copies it directly
md5sum "$STARTING_ORK" | awk '{print $1}' > /tmp/starting_ork_md5.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the default-configured rocket
launch_openrocket "$STARTING_ORK"
sleep 3

# Wait for application to be ready
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot for reference
take_screenshot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== Setup complete ==="