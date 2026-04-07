#!/bin/bash
echo "=== Setting up furniture_layout_planning task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_furnished.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create the design brief specification document on Desktop ──────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/furniture_brief.txt << 'SPECEOF'
INTERIOR DESIGN - FURNITURE SCHEDULE
====================================
Project: FZK-Haus Fit-out
Client: FZK Residential
Prepared by: Interior Design Team
Date: 2024-03-15

INSTRUCTIONS
------------
The architectural shell for FZK-Haus is currently open in BlenderBIM/Bonsai.
Your task is to model the proposed furniture and classify it correctly using
IFC standards so the Facilities Management team can generate asset registers.

FURNITURE REQUIREMENTS
----------------------
Please create at least 6 of the following items in the model:
  - Sofa (Living Room)
  - Coffee Table (Living Room)
  - Dining Table (Dining Area)
  - Dining Chair (Dining Area)
  - Bed (Bedroom)
  - Wardrobe (Bedroom)
  - Desk (Study)

BIM / IFC STANDARDS REQUIRED
----------------------------
1. IFC Class: All modeled furniture must be assigned the 'IfcFurniture' class.
2. IFC Types: Group your furniture using 'IfcFurnitureType' entities.
   You must define at least 3 distinct named types (e.g., "Dining Chair", "Sofa").
3. Materials: Assign a named material (e.g., "Wood", "Fabric", "Steel") to
   at least one of the furniture pieces using Bonsai's material tools.
4. Containment: All furniture must be spatially contained inside a Building Storey
   (e.g., Ground Floor or First Floor).

SAVE INSTRUCTIONS
-----------------
When the modeling and classification are complete, save the project as:
/home/ga/BIMProjects/fzk_furnished.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/furniture_brief.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_furniture.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for furniture layout task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_furniture.py > /tmp/blender_task.log 2>&1 &"

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

# Extra time for IFC to parse and load
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
echo "Design Brief: /home/ga/Desktop/furniture_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_furnished.ifc"