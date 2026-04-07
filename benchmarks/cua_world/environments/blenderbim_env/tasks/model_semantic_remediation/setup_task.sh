#!/bin/bash
echo "=== Setting up model_semantic_remediation task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects /home/ga/IFCModels
chown ga:ga /home/ga/BIMProjects /home/ga/IFCModels

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_remediated.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Programmatically Corrupt the FZK-Haus Model ────────────────────────
echo "Generating proxy-corrupted IFC model from FZK-Haus..."

cat > /tmp/create_corrupted_model.py << 'PYEOF'
import sys
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

import ifcopenshell
import ifcopenshell.api as api

input_path = "/home/ga/IFCModels/fzk_haus.ifc"
output_path = "/home/ga/IFCModels/fzk_proxy_corrupted.ifc"

try:
    if not os.path.exists(input_path):
        print(f"RESULT: ERROR - input file {input_path} not found.")
        sys.exit(1)
        
    ifc = ifcopenshell.open(input_path)
    
    # Collect all native building elements that should be proxies
    elements = (
        list(ifc.by_type("IfcWall")) + 
        list(ifc.by_type("IfcWindow")) + 
        list(ifc.by_type("IfcDoor")) + 
        list(ifc.by_type("IfcSlab"))
    )
    
    count = 0
    for element in elements:
        # Reassign class to IfcBuildingElementProxy while preserving geometry and name
        api.run("root.reassign_class", ifc, product=element, ifc_class="IfcBuildingElementProxy")
        count += 1
        
    ifc.write(output_path)
    print(f"RESULT: Corrupted model created successfully. Converted {count} elements to proxies.")
except Exception as e:
    print(f"RESULT: Error during model corruption - {e}")
PYEOF

# Run the python script using Blender's bundled python
/opt/blender/blender --background --python /tmp/create_corrupted_model.py 2>&1 | grep 'RESULT:'

if [ ! -f /home/ga/IFCModels/fzk_proxy_corrupted.ifc ]; then
    echo "ERROR: Failed to create the corrupted IFC model."
    exit 1
fi

chown ga:ga /home/ga/IFCModels/fzk_proxy_corrupted.ifc
echo "Corrupted model ready: /home/ga/IFCModels/fzk_proxy_corrupted.ifc"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load the corrupted model ───────
cat > /tmp/load_corrupted_model.py << 'PYEOF'
import bpy
import sys

def load_proxy_model():
    """Load the proxy-corrupted IFC into Bonsai."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_proxy_corrupted.ifc")
        print("Corrupted Proxy IFC loaded successfully for remediation task")
    except Exception as e:
        print(f"Error loading proxy model: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_proxy_model, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with Corrupted Model pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_corrupted_model.py > /tmp/blender_task.log 2>&1 &"

# Wait for Blender window
WAIT_COUNT=0
while [ $WAIT_COUNT -lt 15 ]; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "blender" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Blender window detected: $WID"
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

# Extra time for IFC to load
sleep 10

# ── 8. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Corrupted FZK-Haus proxy model loaded in Bonsai."
echo "Expected output: /home/ga/BIMProjects/fzk_remediated.ifc"