#!/bin/bash
echo "=== Setting up av_it_infrastructure_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_smart_home.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create project brief specification document ────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/smart_home_brief.txt << 'SPECEOF'
SMART HOME AV/IT RETROFIT BRIEF
================================
Project: FZK-Haus Residential Building
Role:    AV/IT Systems Designer
Date:    2024-03-15

DELIVERABLE
-----------
The FZK-Haus IFC model is currently open. You must add the following
equipment to the model to prepare it for the Smart Home demonstration:

1. DISPLAYS (Minimum 2)
   - Model 2x flat-screen displays (simple flat boxes are acceptable).
   - IFC Class: IfcAudioVisualAppliance
   - PredefinedType: DISPLAY
   - Name: Must contain "Display" or "TV"

2. ROUTERS (Minimum 2)
   - Model 2x Wi-Fi routers / Access Points (small boxes).
   - IFC Class: IfcCommunicationsAppliance
   - PredefinedType: ROUTER (or NETWORKAPPLIANCE)
   - Name: Must contain "Router" or "AP"

REQUIREMENTS
------------
- Geometry: All items must have physical 3D geometry in the model.
- Spatial Containment: Assign all new appliances to an existing
  IfcBuildingStorey (e.g., "Erdgeschoss" / Ground Floor, or "Obergeschoss").
- Save: Save the enriched IFC file to:
  /home/ga/BIMProjects/fzk_smart_home.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/smart_home_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_avit.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for AV/IT task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_avit.py > /tmp/blender_task.log 2>&1 &"

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

# Extra time for IFC to load completely
sleep 10

# ── 8. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should now be loaded in Bonsai"
echo "Expected output: /home/ga/BIMProjects/fzk_smart_home.ifc"