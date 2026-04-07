#!/bin/bash
echo "=== Setting up temporary_scaffolding_modeling task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# 2. Remove any existing output file
rm -f /home/ga/BIMProjects/fzk_scaffold.ifc 2>/dev/null || true

# 3. Kill any existing Blender
kill_blender

# 4. Create scaffold specification document
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/scaffold_spec.txt << 'SPECEOF'
TEMPORARY WORKS - SCAFFOLD TOWER SPECIFICATION
===============================================
Project:    FZK-Haus Renovation
Role:       Temporary Works Engineer
Date:       2024-03-15

DELIVERABLE
-----------
Model a scaffold tower adjacent to the FZK-Haus for roof access.
Save the updated model to:
  /home/ga/BIMProjects/fzk_scaffold.ifc

REQUIREMENTS
------------
1. FRAMING (IfcMember):
   - Minimum 8 linear members (e.g., 4 vertical standards, 4 horizontal ledgers).
   - Classify all framing components as IfcMember.

2. PLATFORM (IfcPlate):
   - Minimum 1 flat platform component.
   - Classify as IfcPlate.

3. ASSEMBLY (IfcElementAssembly):
   - The entire scaffold must be grouped into a single assembly.
   - Create an IfcElementAssembly (e.g., an Empty object classified as such).
   - Parent/aggregate the members and plate under this assembly so that 
     an IfcRelAggregates relationship is created upon export.
SPECEOF
chown ga:ga /home/ga/Desktop/scaffold_spec.txt
echo "Project documentation placed on Desktop"

# 5. Record task start timestamp
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 6. Create Python startup script to pre-load FZK-Haus
cat > /tmp/load_fzk_scaffold.py << 'PYEOF'
import bpy
import sys

def load_fzk_haus():
    """Load FZK-Haus IFC into Bonsai after UI is ready."""
    try:
        bpy.ops.bim.load_project(filepath="/home/ga/IFCModels/fzk_haus.ifc")
        print("FZK-Haus IFC loaded successfully for scaffolding task")
    except Exception as e:
        print(f"Error loading FZK-Haus: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(load_fzk_haus, first_interval=4.0)
PYEOF

# 7. Launch Blender with startup script
echo "Launching Blender with FZK-Haus pre-load..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/load_fzk_scaffold.py > /tmp/blender_task.log 2>&1 &"

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

# 8. Focus, maximize, dismiss dialogs, screenshot
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="