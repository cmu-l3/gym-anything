#!/bin/bash
echo "=== Setting up cost_schedule_from_takeoff task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/fzk_cost_schedule.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Create the cost rates specification document on Desktop ────────────
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/cost_rates_spec.txt << 'SPECEOF'
PRE-TENDER COST RATES SPECIFICATION
=====================================
Project: FZK-Haus Residential Building
Client: FZK Institute
Prepared by: Cost Management Group
Date: 2024-03-15
Reference: CMG-SPEC-2024-FZK-001

INSTRUCTIONS
------------
Using BlenderBIM/Bonsai, create a cost schedule for the FZK-Haus
model currently open in the application.

STEP 1: Create a Cost Schedule
  - Navigate to Bonsai cost management tools
  - Create a new cost schedule
  - Name it EXACTLY: Pre-Tender Estimate
  - Status: DRAFT

STEP 2: Create Four Cost Items within the schedule:

  ITEM 1: External Walls
    Unit: m2
    Unit Rate: 285.00
    Currency: GBP
    Description: External cavity wall construction incl. insulation

  ITEM 2: Internal Walls
    Unit: m2
    Unit Rate: 125.00
    Currency: GBP
    Description: Internal partition wall construction

  ITEM 3: Doors
    Unit: nr
    Unit Rate: 750.00
    Currency: GBP
    Description: Standard door set supply and fix

  ITEM 4: Windows
    Unit: nr
    Unit Rate: 650.00
    Currency: GBP
    Description: Double-glazed window unit supply and fix

STEP 3: Save the project
  Save the complete IFC file (with embedded cost schedule) to:
  /home/ga/BIMProjects/fzk_cost_schedule.ifc

NOTE: All rates are exclusive of VAT. The FZK-Haus model has
13 walls, 5 doors, and 11 windows for reference.
SPECEOF
chown ga:ga /home/ga/Desktop/cost_rates_spec.txt
echo "Project documentation placed on Desktop"

# ── 5. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 6. Create Python startup script to pre-load FZK-Haus ──────────────────
cat > /tmp/load_fzk_cost.py << 'PYEOF'
import bpy
import sys


def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for cost schedule task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None  # Do not repeat timer


bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# ── 7. Launch Blender with startup script ─────────────────────────────────
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_cost.py > /tmp/blender_task.log 2>&1 &"

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
echo "Spec document: /home/ga/Desktop/cost_rates_spec.txt"
echo "Expected output: /home/ga/BIMProjects/fzk_cost_schedule.ifc"
