#!/bin/bash
# Setup script for subcaliber_motor_adapter_retrofit task

echo "=== Setting up subcaliber_motor_adapter_retrofit task ==="
source /workspace/scripts/task_utils.sh || { echo "FATAL: Failed to source task_utils"; exit 1; }

TASK_ORK="$ROCKETS_DIR/dual_parachute_deployment.ork"
SOURCE_ORK="/workspace/data/rockets/dual_parachute_deployment.ork"

# Create required directories
mkdir -p "$ROCKETS_DIR" "$EXPORTS_DIR"
chown -R ga:ga "$ROCKETS_DIR" "$EXPORTS_DIR"

# Copy base .ork to task working file
cp "$SOURCE_ORK" "$TASK_ORK" || { echo "FATAL: Could not copy source .ork"; exit 1; }
chown ga:ga "$TASK_ORK"

# Remove possible previous outputs to ensure a clean state
rm -f "$ROCKETS_DIR/adapted_dual_deploy.ork" 2>/dev/null || true
rm -f "$EXPORTS_DIR/adapter_report.txt" 2>/dev/null || true

# Extract baseline centering ring count via Python to dynamically detect starting state
python3 -c "
import zipfile, xml.etree.ElementTree as ET
try:
    with zipfile.ZipFile('$TASK_ORK') as z:
        root = ET.fromstring(z.read('rocket.ork'))
        print(len(root.findall('.//centeringring')))
except Exception:
    print('2')
" > /tmp/baseline_rings.txt

# Record start time for anti-gaming (file mtime must be newer than this)
date +%s > /tmp/task_start_ts.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket with the source rocket
launch_openrocket "$TASK_ORK"
sleep 3

# Wait for UI to initialize
wait_for_openrocket 90
sleep 3
focus_openrocket_window
sleep 2
dismiss_dialogs 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_start.png 2>/dev/null || true
echo "Initial screenshot saved"

echo "=== subcaliber_motor_adapter_retrofit task setup complete ==="