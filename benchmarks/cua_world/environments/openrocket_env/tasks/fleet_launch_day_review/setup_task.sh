#!/bin/bash
echo "=== Setting up fleet_launch_day_review task ==="

source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

LAUNCH_DAY_DIR="/home/ga/Documents/rockets/launch_day"
EXPORTS_DIR="/home/ga/Documents/exports"

# Create directories
mkdir -p "$LAUNCH_DAY_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$LAUNCH_DAY_DIR" "$EXPORTS_DIR"

# Copy source .ork files to task working directory
cp "$ROCKETS_DIR/simple_model_rocket.ork" "$LAUNCH_DAY_DIR/" || true
cp "$ROCKETS_DIR/dual_parachute_deployment.ork" "$LAUNCH_DAY_DIR/" || true
cp "$ROCKETS_DIR/clustered_motors.ork" "$LAUNCH_DAY_DIR/" || true
chown -R ga:ga "$LAUNCH_DAY_DIR"

# Remove previous output files
rm -f "$EXPORTS_DIR/fleet_summary.csv" 2>/dev/null || true
rm -f "$EXPORTS_DIR/launch_day_briefing.txt" 2>/dev/null || true

# Inject fault into dual_deploy and reset all simulations
python3 << 'PYEOF'
import zipfile, os
import xml.etree.ElementTree as ET

def process_rocket(path, is_dual=False):
    if not os.path.exists(path):
        print(f"Skipping {path}, not found.")
        return

    tmp_path = path + '.tmp'
    with zipfile.ZipFile(path, 'r') as zin:
        xml_bytes = zin.read('rocket.ork')
    
    root = ET.fromstring(xml_bytes.decode('utf-8'))
    
    # Inject fault: shrink main parachute
    if is_dual:
        for para in root.iter('parachute'):
            name_el = para.find('name')
            name = name_el.text.lower() if name_el is not None and name_el.text else ''
            # If it's not the drogue, it's the main parachute
            if 'drogue' not in name and 'drouge' not in name:
                diam_el = para.find('diameter')
                if diam_el is not None:
                    diam_el.text = '0.254' # 10 inches -> dangerous descent
                    print(f"Shrunk main parachute in {os.path.basename(path)}")
                    
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
    
    with zipfile.ZipFile(path, 'r') as zin:
        with zipfile.ZipFile(tmp_path, 'w', zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                if item.filename == 'rocket.ork':
                    zout.writestr(item, modified_xml_bytes)
                else:
                    zout.writestr(item, zin.read(item.filename))
                    
    os.replace(tmp_path, path)

base_dir = '/home/ga/Documents/rockets/launch_day'
process_rocket(os.path.join(base_dir, 'simple_model_rocket.ork'))
process_rocket(os.path.join(base_dir, 'clustered_motors.ork'))
process_rocket(os.path.join(base_dir, 'dual_parachute_deployment.ork'), is_dual=True)
PYEOF

if [ $? -ne 0 ]; then
    echo "FATAL: Python setup failed"
    exit 1
fi

# Record ground truth
echo "task_start_ts=$(date +%s)" > /tmp/fleet_review_gt.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket empty
launch_openrocket
sleep 3

wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot
take_screenshot /tmp/fleet_review_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== fleet_launch_day_review task setup complete ==="