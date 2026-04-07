#!/bin/bash
echo "=== Setting up ifc_uniclass_classification_commissioning task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file (BEFORE recording timestamp) ───────
rm -f /home/ga/BIMProjects/fzk_classified.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender processes ────────────────────────────────
kill_blender

# ── 4. Create the Uniclass 2015 classification specification ──────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/uniclass_spec.txt << 'SPECEOF'
UNICLASS 2015 CLASSIFICATION COMMISSIONING SPECIFICATION
=========================================================
Project:     FZK-Haus Residential Building
Client:      Homes England
Reference:   BIM-HANDOVER-UK-2024-003
Prepared by: Digital BIM Coordination Team
Standard:    Uniclass 2015 (NBS, UK BIM Framework)

PURPOSE
-------
Apply Uniclass 2015 classification codes to all building
elements in the FZK-Haus IFC model to enable UK-compliant
asset register extraction at project handover.

CLASSIFICATION SYSTEM
---------------------
Classification System Name: Uniclass 2015
Source: https://www.thenbs.com/our-tools/uniclass-2015
Table: Systems (Ss)

ELEMENT CLASSIFICATION REQUIREMENTS
------------------------------------
ALL elements must be classified via IfcClassificationReference
attached using IfcRelAssociatesClassification.

  Element Type    | Uniclass Code  | Uniclass Title
  ----------------|----------------|------------------------
  IfcWall         | Ss_25_16_94    | Wall systems
  IfcWindow       | Ss_25_96_57    | Window systems
  IfcDoor         | Ss_25_32_33    | Door systems
  IfcSlab         | Ss_25_56_95    | Slab systems

MANDATORY ATTRIBUTES FOR IfcClassificationReference
------------------------------------------------------
  ReferencedSource.Name:        "Uniclass 2015"
  ReferencedSource.Source:      "NBS"
  ReferencedSource.Edition:     "2015"
  Identification (code):        As specified per element type above
  Name (title):                 As specified per element type above

SCOPE
------
  - ALL 13 IfcWall instances must receive Ss_25_16_94
  - ALL 11 IfcWindow instances must receive Ss_25_96_57
  - ALL 5 IfcDoor instances must receive Ss_25_32_33
  - ALL 4 IfcSlab instances must receive Ss_25_56_95

VALIDATION
----------
The asset register will be extracted automatically.
Missing or incorrect codes will fail the handover gate.
Do NOT apply codes to element types not listed above.

OUTPUT
------
Save the classified model to:
  /home/ga/BIMProjects/fzk_classified.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/uniclass_spec.txt
echo "Uniclass specification placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_uniclass.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for the Uniclass classification task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for Uniclass classification commissioning task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_uniclass.py > /tmp/blender_task.log 2>&1 &"

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
echo "FZK-Haus loaded in Bonsai for Uniclass classification"
echo "Spec document: /home/ga/Desktop/uniclass_spec.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_classified.ifc"
