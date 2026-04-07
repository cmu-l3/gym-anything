#!/bin/bash
echo "=== Setting up project_stakeholder_actor_assignment task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_stakeholders.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create Stakeholder Brief document ──────────────────────────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/stakeholder_brief.txt << 'SPECEOF'
PROJECT STAKEHOLDER & ACTOR ASSIGNMENT BRIEF
============================================
Project: FZK-Haus
Phase: Pre-Tender
Date: 2024-04-10

INSTRUCTIONS:
The project's BIM Execution Plan (aligned with ISO 19650) requires the model
to explicitly list key project participants in the IFC Project Directory.

STEP 1: ADD ORGANIZATIONS
Using Bonsai's Project Directory tools, add the following three (3)
organizations to the project:

  1. Client:       "Karlsruhe Institute of Technology"
  2. Architect:    "ArchitekturBuro FZK"
  3. Manufacturer: "KlarGlas GmbH"

STEP 2: ASSIGN ACTORS TO ELEMENTS
We have finalized the window supplier. You must assign the manufacturer 
to all the windows in the model so that COBie exports are correct.

  - Target Elements: All Windows (IfcWindow) in the model (there are 11)
  - Assigned Actor: "KlarGlas GmbH"

STEP 3: SAVE MODEL
Save the enriched model (using Bonsai's Save IFC Project) to:
  /home/ga/BIMProjects/fzk_stakeholders.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/stakeholder_brief.txt
echo "Brief documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_stakeholders.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai for stakeholder task."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus loaded for stakeholder task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_stakeholders.py > /tmp/blender_task.log 2>&1 &"

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
echo "Brief: /home/ga/Desktop/stakeholder_brief.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_stakeholders.ifc"