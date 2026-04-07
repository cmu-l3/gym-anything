#!/bin/bash
echo "=== Setting up openvsp_catapult_hook_cg_alignment ==="

source /workspace/scripts/task_utils.sh

# Ensure directories
mkdir -p "$MODELS_DIR"
chown -R ga:ga "$MODELS_DIR"

# Copy base model (using eCRM-001 as tactical UAV proxy)
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/tactical_uav.vsp3"
chmod 644 "$MODELS_DIR/tactical_uav.vsp3"

# Randomize geometry to shift CG
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import random
import re
import os

filepath = '/home/ga/Documents/OpenVSP/tactical_uav.vsp3'
if os.path.exists(filepath):
    try:
        with open(filepath, 'r') as f:
            content = f.read()

        # Shift all X_Rel_Location by the same random amount
        shift = random.uniform(-3.0, 3.0)
        
        def replacer(match):
            val = float(match.group(1))
            return f'<X_Rel_Location Value="{val + shift:.18e}"'

        new_content = re.sub(r'<X_Rel_Location Value="([^"]+)"', replacer, content)
        
        with open(filepath, 'w') as f:
            f.write(new_content)
        print(f"Successfully shifted model by {shift:.3f} to randomize CG.")
    except Exception as e:
        print(f"Error modifying XML: {e}")
PYEOF

# Clean up any stale files
rm -f "$MODELS_DIR/uav_launch_ready.vsp3"
rm -f "$MODELS_DIR/tactical_uav_MassProps.txt"
rm -f /tmp/task_result.json

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch OpenVSP
launch_openvsp "$MODELS_DIR/tactical_uav.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="