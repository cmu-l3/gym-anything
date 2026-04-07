#!/bin/bash
echo "=== Setting up fire_compartment_zone_definition task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure directories exist ───────────────────────────────────────────
mkdir -p /home/ga/BIMProjects
mkdir -p /home/ga/IFCModels
chown -R ga:ga /home/ga/BIMProjects /home/ga/IFCModels

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_fire_compartments.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create Fire Strategy Brief on Desktop ──────────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/fire_strategy_brief.txt << 'SPECEOF'
FIRE STRATEGY BRIEF - COMPARTMENTATION
======================================
Project:    FZK-Haus Residential Building
Discipline: Fire Safety Engineering
Date:       2024-03-15
Ref:        FS-COMP-001

REQUIREMENT
-----------
The architectural IFC model contains spatial elements (IfcSpace)
representing the rooms. However, the model lacks fire compartmentation
data required for Building Regulations (Approved Document B) checks.

TASK INSTRUCTIONS
-----------------
Using BlenderBIM/Bonsai:

1. CREATE FIRE ZONES
   Create two new IfcZone entities to represent the fire compartments:
   - "Ground Floor Compartment"
   - "First Floor Compartment"

2. ASSIGN SPACES TO ZONES
   Assign the existing IfcSpace (room) entities to their respective
   fire compartment zones based on their storey location.

3. DEFINE FIRE RESISTANCE
   Add fire resistance property data to the zones. 
   Create a Property Set on the zones (e.g., "Pset_ZoneFireSafety") 
   and add a property indicating the fire rating (e.g., Property Name: 
   "FireResistanceRating", Value: "REI 30").
   (Note: Any property set or property name containing the word "fire" 
   will satisfy the compliance check).

4. SAVE THE MODEL
   Save the updated IFC project to:
   /home/ga/BIMProjects/fzk_fire_compartments.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/fire_strategy_brief.txt
echo "Fire Strategy Brief placed on Desktop"

# ── 5. Prepare the input model ────────────────────────────────────────────
# The standard FZK-Haus contains IfcSpace elements, but we create a clean copy
# to ensure the agent works on the correct base file.
if [ -f "/home/ga/IFCModels/fzk_haus.ifc" ]; then
    cp "/home/ga/IFCModels/fzk_haus.ifc" "/home/ga/IFCModels/fzk_fire_prep.ifc"
    chown ga:ga "/home/ga/IFCModels/fzk_fire_prep.ifc"
else
    echo "ERROR: Base FZK-Haus model not found in /home/ga/IFCModels/"
    exit 1
fi

# ── 6. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 7. Create Python startup script to pre-load the model ─────────────────
cat > /tmp/load_fzk_fire.py << 'PYEOF'
import bpy
import sys

def load_fire_prep_model():
    """Load the prepared IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_fire_prep.ifc")
        print("Model loaded successfully for fire compartmentation task")
    except Exception as e:
        print(f"Error loading model: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fire_prep_model, first_interval=4.0)
PYEOF

# ── 8. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with model pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_fire.py > /tmp/blender_task.log 2>&1 &"

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

# ── 9. Focus, maximize, dismiss dialogs, screenshot ───────────────────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Expected output: /home/ga/BIMProjects/fzk_fire_compartments.ifc"