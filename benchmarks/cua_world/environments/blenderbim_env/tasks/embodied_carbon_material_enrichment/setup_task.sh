#!/bin/bash
echo "=== Setting up embodied_carbon_material_enrichment task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_embodied_carbon.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create LCA brief specification document ────────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/lca_spec.txt << 'SPECEOF'
LIFE CYCLE ASSESSMENT (LCA) SPECIFICATION
=========================================
Project: FZK-Haus Residential Building
Phase:   Detailed Design Embodied Carbon Assessment
Date:    2024-03-15

SCOPE
-----
The baseline architectural model (FZK-Haus) currently lacks 
environmental data on its materials. For the LCA software 
(e.g., One Click LCA) to automatically calculate the carbon 
footprint, the model must contain explicit material definitions 
with their Global Warming Potential (GWP) embedded.

TASK INSTRUCTIONS
-----------------
Using Bonsai (BlenderBIM), you must enrich the open IFC model:

1. CREATE MATERIALS:
   Create two new IFC materials:
   - "C30/37 Concrete"
   - "Structural Timber"

2. ADD ENVIRONMENTAL PROPERTIES:
   Add the standard IFC environmental property set to BOTH materials.
   - Property Set Name: Pset_EnvironmentalImpactIndicators
   - Property Name:     GlobalWarmingPotential
   - Property Value:    0.15  (for Concrete)
   - Property Value:    -0.65 (for Timber - sequestering carbon)

   *Note: These properties must be assigned to the MATERIALS themselves
    (IfcMaterialProperties), not the building elements.*

3. ASSIGN MATERIALS TO GEOMETRY:
   - Assign the "C30/37 Concrete" material to at least 2 Floor Slabs (IfcSlab).
   - Assign the "Structural Timber" material to at least 6 Walls (IfcWall).

4. SAVE:
   Save the enriched IFC project to:
   /home/ga/BIMProjects/fzk_embodied_carbon.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/lca_spec.txt
echo "LCA specification placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_lca.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for Embodied Carbon task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None  # Do not repeat timer

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_lca.py > /tmp/blender_task.log 2>&1 &"

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
echo "Spec document: /home/ga/Desktop/lca_spec.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_embodied_carbon.ifc"