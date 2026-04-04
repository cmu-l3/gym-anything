#!/bin/bash
set -euo pipefail

echo "=== Setting up create_placemark task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 1

# =============================================================================
# SAVE BASELINE STATE FOR VERIFICATION
# =============================================================================
# This is critical for detecting NEW placemarks created during the task
echo "Saving baseline state for verification..."

BASELINE_FILE="/tmp/ge_baseline_state.json"
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"

# Backup existing myplaces.kml
if [ -f "$MYPLACES_FILE" ]; then
    cp "$MYPLACES_FILE" "${MYPLACES_FILE}.bak" 2>/dev/null || true
fi

# Create baseline JSON using Python
python3 << 'PYTHON_SCRIPT'
import json
import hashlib
import time
import os

baseline = {
    'timestamp': time.time(),
    'myplaces_hash': None,
    'myplaces_exists': False,
    'myplaces_content': None,
}

myplaces_path = '/home/ga/.googleearth/myplaces.kml'
if os.path.exists(myplaces_path):
    baseline['myplaces_exists'] = True
    with open(myplaces_path, 'rb') as f:
        content = f.read()
        baseline['myplaces_hash'] = hashlib.sha256(content).hexdigest()
    with open(myplaces_path, 'r') as f:
        baseline['myplaces_content'] = f.read()

with open('/tmp/ge_baseline_state.json', 'w') as f:
    json.dump(baseline, f, indent=2)

print(f"Baseline saved: myplaces_exists={baseline['myplaces_exists']}")
PYTHON_SCRIPT

echo "Baseline state saved to $BASELINE_FILE"

# =============================================================================
# START GOOGLE EARTH
# =============================================================================
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth.log 2>&1 &
sleep 5

# Wait for window to appear
for i in {1..30}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected"
        break
    fi
    sleep 1
done

echo "Window ID: $(wmctrl -l | grep -i 'Google Earth' | awk '{print $1}')"

# Full screen the window
wmctrl -r "Google Earth" -b add,fullscreen 2>/dev/null || true

# Focus the Google Earth window
wmctrl -a "Google Earth" 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Task: Create a placemark named 'Golden Gate Bridge' at the Golden Gate Bridge in San Francisco"
echo ""
echo "Steps:"
echo "  1. Use the search bar (Ctrl+F) to navigate to 'Golden Gate Bridge, San Francisco'"
echo "  2. Once viewing the bridge, click Add → Placemark (or press Ctrl+Shift+P)"
echo "  3. Name the placemark 'Golden Gate Bridge'"
echo "  4. Click OK to save the placemark"
echo ""
echo "NOTE: The verifier will check that:"
echo "  - A NEW placemark was created (not pre-existing)"
echo "  - The placemark name is 'Golden Gate Bridge'"
echo "  - The placemark coordinates are at the actual Golden Gate Bridge location"
