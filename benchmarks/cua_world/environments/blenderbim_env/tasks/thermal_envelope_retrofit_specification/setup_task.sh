#!/bin/bash
echo "=== Setting up thermal_envelope_retrofit_specification task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file (BEFORE recording timestamp) ───────
rm -f /home/ga/BIMProjects/fzk_thermal_envelope.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender processes ────────────────────────────────
kill_blender

# ── 4. Create the retrofit specification document on Desktop ──────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/thermal_retrofit_spec.txt << 'SPECEOF'
BUILDING ENVELOPE THERMAL RETROFIT SPECIFICATION
=================================================
Project:     FZK-Haus Residential Building
Client:      KIT Energy Retrofit Programme
Reference:   FZK-RETRO-2024-001
Prepared by: Building Physics Consulting Group

PURPOSE
-------
Enrich the existing architectural IFC model with thermal
performance data required for energy retrofit compliance.
Three deliverables are required: wall construction layers,
glazing type specification, and thermal zoning.


SECTION A - WALL CONSTRUCTION
------------------------------
Create a material layer set and assign it to all walls.

  Material Layer Set Name: "Retrofit External Wall"

  Layers (from outside to inside):
    Layer 1:  Cement Render      -   15 mm
    Layer 2:  EPS Insulation     -  120 mm
    Layer 3:  Air Gap            -   25 mm
    Layer 4:  Concrete Block     -  200 mm
    Layer 5:  Gypsum Plaster     -   13 mm

  Application: ALL IfcWall elements in the model.


SECTION B - GLAZING SPECIFICATION
----------------------------------
Create a window type and assign it to all windows.

  Window Type Name: "Triple-Glazed TG-01"

  Property Set: Pset_WindowCommon
    ThermalTransmittance: 0.8  (W/m2K)

  Application: ALL IfcWindow instances.
  Assignment method: IfcRelDefinesByType


SECTION C - THERMAL ZONING
----------------------------
Create two thermal zones from the existing room spaces.

  Zone 1:  "Heated Envelope"
           Contains all IfcSpace elements on the Erdgeschoss
           (ground floor storey).

  Zone 2:  "Semi-Heated Envelope"
           Contains all IfcSpace elements on the Dachgeschoss
           (upper floor storey).


OUTPUT
------
Save the completed model to:
  /home/ga/BIMProjects/fzk_thermal_envelope.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/thermal_retrofit_spec.txt
echo "Retrofit specification placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_thermal_envelope.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for the thermal envelope task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for thermal envelope retrofit task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_thermal_envelope.py > /tmp/blender_task.log 2>&1 &"

# Wait for Blender window to appear
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

# Extra time for IFC model to fully load
sleep 10

# ── 8. Focus, maximize, dismiss dialogs, take initial screenshot ──────────
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "FZK-Haus should now be loaded in Bonsai"
echo "Spec document: /home/ga/Desktop/thermal_retrofit_spec.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_thermal_envelope.ifc"


<system-reminder>
Whenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.
</system-reminder>
