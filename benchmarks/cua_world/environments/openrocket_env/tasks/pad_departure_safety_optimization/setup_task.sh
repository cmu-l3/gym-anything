#!/bin/bash
echo "=== Setting up pad_departure_safety_optimization task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

SOURCE_ORK="$ROCKETS_DIR/janus_38mm.ork"
TARGET_ORK="$ROCKETS_DIR/safe_janus.ork"
MEMO_PATH="$EXPORTS_DIR/pad_safety_memo.txt"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Ensure the source rocket file is available (download if not present from environment)
if [ ! -f "$SOURCE_ORK" ]; then
    echo "Base rocket file missing! Attempting to download..."
    wget -q "https://raw.githubusercontent.com/3dp-rocket/rockets/master/janus/OpenRocket-38mm.ork" -O "$SOURCE_ORK" || true
fi

# Remove target and memo if they exist to prevent gaming
rm -f "$TARGET_ORK" 2>/dev/null || true
rm -f "$MEMO_PATH" 2>/dev/null || true

# Strip existing simulations and motor configs from the source ORK to ensure a clean slate
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/janus_38mm.ork'
if not os.path.exists(ork_path):
    print(f"File {ork_path} not found, skipping Python modification.")
    exit(0)

tmp_path = ork_path + '.tmp'

try:
    with zipfile.ZipFile(ork_path, 'r') as zin:
        xml_bytes = zin.read('rocket.ork')
    
    root = ET.fromstring(xml_bytes.decode('utf-8'))
    
    # Remove all simulations
    sims_elem = root.find('simulations')
    removed_sims = 0
    if sims_elem is not None:
        for sim in list(sims_elem.findall('simulation')):
            sims_elem.remove(sim)
            removed_sims += 1
            
    # Remove all motor configurations from motormount
    for mm in root.iter('motormount'):
        for motor in list(mm.findall('motor')):
            mm.remove(motor)
        for ic in list(mm.findall('ignitionconfiguration')):
            mm.remove(ic)
            
    print(f"Cleared {removed_sims} simulations and all motor configs.")
    
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
except Exception as e:
    print(f"Error modifying ORK file: {e}")
PYEOF

chown ga:ga "$SOURCE_ORK"

# Record ground truth and timestamp (for anti-gaming checks)
echo "task_start_ts=$(date +%s)" > /tmp/pad_safety_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the cleaned source rocket
launch_openrocket "$SOURCE_ORK"
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/pad_safety_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== pad_departure_safety_optimization task setup complete ==="