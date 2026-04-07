#!/bin/bash
echo "=== Setting up accessibility_clearance_zone_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_accessibility.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create project brief specification document ────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/accessibility_brief.txt << 'SPECEOF'
ACCESSIBILITY CLEARANCE MODELING
================================
Project: FZK-Haus Residential Building
Task: ADA / Inclusive Design Clearance Zones

The FZK-Haus model is open in BlenderBIM. Your task is to model
accessibility clearance zones for wheelchairs to run clash detection.

REQUIREMENTS:
1. Create at least 3 new 3D mesh objects representing clearances
   (e.g., 1500mm cylinder for a turning circle, or boxes for door approaches).
   Place them on the ground floor.

2. Assign the IFC class `IfcVirtualElement` to each of these new objects.

3. Name each virtual element with a descriptive name containing
   at least one of these keywords (case-insensitive):
   - "Clearance"
   - "Turning"
   - "Wheelchair"
   - "Access"

4. Assign each virtual element to the Ground Floor spatial container
   using Bonsai's spatial assignment tool.

5. Save the IFC project to:
   /home/ga/BIMProjects/fzk_accessibility.ifc

NOTE: Do not delete the existing architectural elements (walls, doors, etc).
SPECEOF
chown ga:ga /home/ga/Desktop/accessibility_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_accessibility.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for accessibility task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_accessibility.py > /tmp/blender_task.log 2>&1 &"

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
echo "FZK-Haus should now be loaded in Bonsai"
echo "Spec document: /home/ga/Desktop/accessibility_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_accessibility.ifc"