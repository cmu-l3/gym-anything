#!/bin/bash
echo "=== Setting up structural_reinforcement_detailing task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# 2. Remove any existing output file to prevent gaming
rm -f /home/ga/BIMProjects/column_reinforcement.ifc 2>/dev/null || true

# 3. Kill any existing Blender instances
kill_blender

# 4. Create a structural detailing brief document
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/detailing_brief.txt << 'SPECEOF'
STRUCTURAL DETAILING BRIEF
==========================
Project: Industrial Facility Alpha
Element: Column C1 (Ground Floor)
Date: 2024-03-15

INSTRUCTIONS:
Please create a standalone 3D IFC model for a typical reinforced concrete column using BlenderBIM/Bonsai.

1. Model the Host Element:
   - Create a column (e.g., 400x400mm, 3000mm high)
   - Assign IFC Class: IfcColumn
   - Assign Material: "Concrete" (must contain this word)

2. Model the Reinforcement:
   - Create at least 4 longitudinal (vertical) bars
   - Create at least 2 transverse ties/stirrups (horizontal loops)
   - Total rebar count must be >= 6
   - Assign IFC Class: IfcReinforcingBar to all rebars
   - Assign Material: "Steel" or "Rebar" (must contain one of these words)

3. Deliverable:
   - Save the IFC project to: /home/ga/BIMProjects/column_reinforcement.ifc
SPECEOF
chown ga:ga /home/ga/Desktop/detailing_brief.txt
echo "Detailing brief placed on Desktop."

# 5. Record task start timestamp (crucial for anti-gaming)
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 6. Launch Blender (empty session)
echo "Launching Blender (empty session for new project authoring)..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender > /tmp/blender_task.log 2>&1 &"

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
sleep 3

# 7. Focus, maximize, dismiss dialogs, screenshot
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Expected output: /home/ga/BIMProjects/column_reinforcement.ifc"