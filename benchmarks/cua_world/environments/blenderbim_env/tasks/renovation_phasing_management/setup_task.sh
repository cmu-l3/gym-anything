#!/bin/bash
echo "=== Setting up renovation_phasing_management task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_renovation_phased.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create brief document on desktop (optional reference) ──────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/renovation_brief.txt << 'SPECEOF'
RENOVATION PHASING SPECIFICATION
================================
Project: FZK-Haus Ground Floor Retrofit
Role:    Architectural Technologist

OVERVIEW
--------
We are preparing the phase plans (Demolition & Proposed) for the 
FZK-Haus residential project. The BIM model must contain the 
lifecycle status of all walls to generate accurate quantity take-offs.

INSTRUCTIONS
------------
1. Do not delete any existing walls from the scene. Demolished elements
   must be retained in the BIM model and tagged appropriately.
2. Tag Existing: Add Pset_WallCommon to at least 8 existing walls.
   Set the "Status" property to "EXISTING".
3. Tag Demolition: Select an internal partition you wish to remove.
   Add Pset_WallCommon and set the "Status" property to "DEMOLISH".
4. Model New: Create at least one new IfcWall in the scene. Add
   Pset_WallCommon and set the "Status" property to "NEW".

Save the resulting IFC project to:
/home/ga/BIMProjects/fzk_renovation_phased.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/renovation_brief.txt

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_renovation.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for the phasing task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded successfully.")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_renovation.py > /tmp/blender_task.log 2>&1 &"

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
sleep 10

# ── 8. Focus, maximize, screenshot ────────────────────────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should be loaded in Bonsai"
echo "Expected output: /home/ga/BIMProjects/fzk_renovation_phased.ifc"