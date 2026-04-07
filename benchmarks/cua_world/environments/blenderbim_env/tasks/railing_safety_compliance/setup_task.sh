#!/bin/bash
echo "=== Setting up railing_safety_compliance task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_railing_compliant.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create building safety compliance brief ────────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/railing_compliance_brief.txt << 'SPECEOF'
BUILDING SAFETY COMPLIANCE REPORT
==================================
Project:    FZK-Haus Residential Building
Client:     FZK Institute
Date:       2024-03-15
Auditor:    Safety Consulting Group

ISSUE IDENTIFIED
----------------
The current FZK-Haus IFC model lacks fall protection. The upper floor
balcony, roof terrace, and stairwells have no guard rails or balustrades,
which violates EN 1991 / BS 6180 safety requirements.

REQUIRED REMEDIATION
--------------------
Using Bonsai (BlenderBIM), add new railing elements to the model
to document the required safety barriers before the model goes out
for building control review.

1. RAILING ELEMENTS
   - Model at least 3 railing elements in appropriate locations
     (e.g., balcony, stairs, roof edge).
   - Assign the IFC class: IfcRailing.

2. PREDEFINED TYPE
   - At least 1 railing must have its PredefinedType set to:
     GUARDRAIL or HANDRAIL

3. HEIGHT PROPERTY
   - Code requires minimum heights (e.g., 1100mm for balconies).
   - Add a Property Set to at least 1 railing (Pset_RailingCommon).
   - Ensure the property set contains a property named exactly: Height
     (You may enter the value as 1100 mm or 1.1 m).

4. MATERIAL SPECIFICATION
   - Railings must be constructed from metal.
   - Create a material with a name containing "Steel", "Metal", or "Aluminium".
   - Assign this material to at least 1 railing using Bonsai's material tools.

DELIVERABLE
-----------
Save the updated, compliant model using "Save IFC Project As" to:
  /home/ga/BIMProjects/fzk_railing_compliant.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/railing_compliance_brief.txt
echo "Compliance brief placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_railings.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for safety compliance task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for railing compliance task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_railings.py > /tmp/blender_task.log 2>&1 &"

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
echo "Brief: /home/ga/Desktop/railing_compliance_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_railing_compliant.ifc"