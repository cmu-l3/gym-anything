#!/bin/bash
echo "=== Setting up fm_document_linking task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_fm_handover.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create the FM handover document schedule ───────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/fm_handover_schedule.txt << 'SPECEOF'
FM HANDOVER DOCUMENT SCHEDULE
===============================
Project:    FZK-Haus Residential Building
Phase:      Pre-Handover (Soft Landings)
Date:       2024-05-20

INSTRUCTIONS
------------
Using BlenderBIM/Bonsai, create document references in the open FZK-Haus
model and associate them with the specified building elements.

For each document below, create an IfcDocumentInformation (or Reference)
with the given Name and Location/URI, then link it to ALL instances of
the target element type using IfcRelAssociatesDocument.

DOCUMENT 1
----------
Name:        Fire Safety Certificate
Description: Annual fire safety compliance certificate
Location:    https://docs.fzkfm.example.com/fire-cert-2024.pdf
Assign to:   All IfcWall elements (External and Internal Walls)

DOCUMENT 2
----------
Name:        Door Maintenance Manual
Description: Manufacturer O&M manual for door hardware
Location:    https://docs.fzkfm.example.com/door-maintenance-v3.pdf
Assign to:   All IfcDoor elements

DOCUMENT 3
----------
Name:        Window Warranty Documentation
Description: 10-year glazing unit warranty
Location:    https://docs.fzkfm.example.com/window-warranty.pdf
Assign to:   All IfcWindow elements

DOCUMENT 4
----------
Name:        Structural Inspection Report
Description: Biennial structural survey report
Location:    https://docs.fzkfm.example.com/structural-report-2024.pdf
Assign to:   All IfcSlab elements (Floors and slabs)

OUTPUT
------
Save the modified IFC project using Bonsai's Save IFC Project As to:
/home/ga/BIMProjects/fzk_fm_handover.ifc

NOTE: There are 13 walls, 5 doors, 11 windows, and 4 slabs in the FZK-Haus model.
SPECEOF
chown ga:ga /home/ga/Desktop/fm_handover_schedule.txt
echo "FM Document Schedule placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_docs.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for FM document task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_docs.py > /tmp/blender_task.log 2>&1 &"

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
echo "Spec document: /home/ga/Desktop/fm_handover_schedule.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_fm_handover.ifc"