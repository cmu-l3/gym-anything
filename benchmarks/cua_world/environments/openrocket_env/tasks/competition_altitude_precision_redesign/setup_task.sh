#!/bin/bash
# Setup script for competition_altitude_precision_redesign task
#
# Creates a deliberately deficient rocket design from dual_parachute_deployment.ork:
# - Fins shrunk to 15mm height (stability below 1.0 cal — unstable)
# - Main parachute shrunk to 150mm diameter (ground hit velocity > 15 m/s — unsafe)
# - Drogue parachute shrunk to 50mm diameter
# - All motor configurations cleared (no motor installed)
# - All simulations cleared
#
# The agent must fix all deficiencies and meet multiple simultaneous constraints.

echo "=== Setting up competition_altitude_precision_redesign task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/competition_rocket.ork"
SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"

# Create directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy source .ork to task working file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove any pre-existing output files BEFORE recording timestamp
rm -f "$ROCKETS_DIR/competition_final.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/flight_data.csv" 2>/dev/null || true
rm -f "$EXPORTS_DIR/design_report.txt" 2>/dev/null || true

# Inject design deficiencies via Python XML manipulation
python3 << 'PYEOF'
import zipfile, os, sys
import xml.etree.ElementTree as ET

ork_path = '/home/ga/Documents/rockets/competition_rocket.ork'
tmp_path = ork_path + '.tmp'

try:
    with zipfile.ZipFile(ork_path, 'r') as zin:
        xml_bytes = zin.read('rocket.ork')

    root = ET.fromstring(xml_bytes.decode('utf-8'))

    # 1. Shrink ALL fin sets to 15mm height (causes instability)
    fins_modified = 0
    for finset in root.iter('trapezoidfinset'):
        height_elem = finset.find('height')
        if height_elem is not None:
            height_elem.text = '0.015'
            fins_modified += 1
    for finset in root.iter('ellipticalfinset'):
        height_elem = finset.find('height')
        if height_elem is not None:
            height_elem.text = '0.015'
            fins_modified += 1
    for finset in root.iter('freeformfinset'):
        height_elem = finset.find('height')
        if height_elem is not None:
            height_elem.text = '0.015'
            fins_modified += 1
    print(f"Shrunk {fins_modified} fin set(s) to 15mm height")

    # 2. Shrink parachutes (causes dangerous descent velocity)
    parachutes_modified = 0
    for para in root.iter('parachute'):
        name_elem = para.find('name')
        name = name_elem.text.lower() if name_elem is not None and name_elem.text else ''
        diam_elem = para.find('diameter')
        if diam_elem is not None:
            if 'drogue' in name or 'drouge' in name:
                diam_elem.text = '0.050'   # 50mm drogue
            else:
                diam_elem.text = '0.150'   # 150mm main
            parachutes_modified += 1
    print(f"Shrunk {parachutes_modified} parachute(s)")

    # 3. Clear ALL motor configurations from motor mounts
    motors_removed = 0
    for mm in root.iter('motormount'):
        for motor in list(mm.findall('motor')):
            mm.remove(motor)
            motors_removed += 1
        for ic in list(mm.findall('ignitionconfiguration')):
            mm.remove(ic)
    print(f"Removed {motors_removed} motor configuration(s)")

    # 4. Remove mass override on sustainer stage so ballast tuning works
    for stage in root.iter('stage'):
        om = stage.find('overridemass')
        if om is not None:
            stage.remove(om)
        osm = stage.find('overridesubcomponentsmass')
        if osm is not None:
            stage.remove(osm)
    print("Removed sustainer mass override (enables ballast tuning)")

    # 5. Clear ALL simulations
    sims_elem = root.find('simulations')
    sims_removed = 0
    if sims_elem is not None:
        for sim in list(sims_elem.findall('simulation')):
            sims_elem.remove(sim)
            sims_removed += 1
    print(f"Removed {sims_removed} simulation(s)")

    # Write modified XML back to ZIP
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
    print("Design deficiencies injected successfully.")

except Exception as e:
    print(f"FATAL: Python setup failed: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

if [ $? -ne 0 ]; then
    echo "FATAL: Python setup failed"
    exit 1
fi

# Fix ownership after Python script (which runs as root)
chown ga:ga "$TASK_ORK"

# Record task start timestamp for anti-gaming checks
echo "task_start_ts=$(date +%s)" > /tmp/competition_redesign_gt.txt

# Record the MD5 of the starting .ork for change detection
file_md5 "$TASK_ORK" > /tmp/competition_redesign_start_md5.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the deficient rocket design
launch_openrocket "$TASK_ORK"
sleep 3

# Wait for UI to initialize
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot documenting starting state
take_screenshot /tmp/competition_redesign_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== competition_altitude_precision_redesign task setup complete ==="
