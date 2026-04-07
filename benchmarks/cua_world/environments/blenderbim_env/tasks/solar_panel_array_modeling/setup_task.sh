#!/bin/bash
echo "=== Setting up solar_panel_array_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# 2. Remove any existing output file to prevent false positives
rm -f /home/ga/BIMProjects/fzk_solar_retrofit.ifc 2>/dev/null || true

# 3. Kill any existing Blender processes
kill_blender

# 4. Create a specification brief for the user on the Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/solar_retrofit_brief.txt << 'SPECEOF'
SUSTAINABILITY RETROFIT BRIEF
=============================
Project: FZK-Haus Residential Building
Role:    Sustainability Engineer
Date:    2026-03-11

OBJECTIVE:
Design and model a rooftop solar PV array for the existing FZK-Haus building.

REQUIREMENTS:
1. Geometry & Classification:
   - Model at least 6 solar panels on the roof.
   - Classify all panels strictly as `IfcSolarDevice`.

2. Logical System:
   - Create an electrical generation system (`IfcSystem`).
   - The system name must include "Solar" or "PV".
   - Assign all modelled solar panels to this system.

3. Performance Properties:
   - Add a property indicating the capacity.
   - The property name must include "Power", "Watt", or "Capacity".
   - You can add this to the individual panels or to the system itself.

DELIVERABLE:
Save the updated IFC model to:
/home/ga/BIMProjects/fzk_solar_retrofit.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/solar_retrofit_brief.txt
echo "Project brief placed on Desktop"

# 5. Record task start timestamp for anti-gaming (verifying file creation)
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 6. Create Python startup script to pre-load FZK-Haus in BlenderBIM
cat > /tmp/load_fzk_solar.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for the solar modeling task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for Solar Retrofit task")
        
        # Switch to 3D Viewport and set shading to material/solid for better visibility
        for area in bpy.context.screen.areas:
            if area.type == 'VIEW_3D':
                for space in area.spaces:
                    if space.type == 'VIEW_3D':
                        space.shading.type = 'SOLID'
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

# Register the load to happen slightly after UI initialization
bpy.app.timers.register(load_fzk_haus, first_interval=3.0)
PYEOF

# 7. Launch Blender with the startup script
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_solar.py > /tmp/blender_task.log 2>&1 &"

# Wait for the Blender window to appear
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

# Extra wait for the IFC project to fully load into memory
sleep 10

# 8. Focus window, maximize, and take initial screenshot
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should be loaded in Bonsai."
echo "Brief: /home/ga/Desktop/solar_retrofit_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_solar_retrofit.ifc"