#!/bin/bash
echo "=== Setting up structural_grid_definition task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure output directory exists and is clean
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects
rm -f /home/ga/BIMProjects/warehouse_grid.ifc 2>/dev/null || true

# 2. Kill any existing Blender instances
kill_blender

# 3. Create structural grid specification document on the desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/grid_specification.txt << 'SPECEOF'
STRUCTURAL GRID SPECIFICATION
===============================
Project: Single-Storey Warehouse
Phase:   Early Design Setup
Date:    2024-03-20

TASK
----
Create the primary structural reference grid for the warehouse.
Initialize a new IFC4 project in Bonsai and create an IfcGrid.

GRID AXES REQUIRED
------------------
You must define a grid with the following axes. The U-axes represent
the primary structural bays, and the V-axes represent the cross-bays.

U-Axes (Lettered):
  - Axis Tag: A    (Offset: 0 mm)
  - Axis Tag: B    (Offset: 6000 mm)
  - Axis Tag: C    (Offset: 12000 mm)
  - Axis Tag: D    (Offset: 18000 mm)

V-Axes (Numbered):
  - Axis Tag: 1    (Offset: 0 mm)
  - Axis Tag: 2    (Offset: 8000 mm)
  - Axis Tag: 3    (Offset: 16000 mm)

DELIVERABLE
-----------
Save the IFC model containing the grid to:
/home/ga/BIMProjects/warehouse_grid.ifc

Note: Ensure you use the exact axis tags specified above.
SPECEOF
chown ga:ga /home/ga/Desktop/grid_specification.txt
echo "Grid specification document placed on Desktop"

# 4. Record task start timestamp (for anti-gaming)
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# 5. Launch Blender (empty session for a new project)
echo "Launching Blender (empty session)..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender > /tmp/blender_task.log 2>&1 &"

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
sleep 3

# 6. Focus, maximize, and dismiss dialogs
focus_blender
maximize_blender
sleep 1
dismiss_blender_dialogs
sleep 1

# Take initial screenshot as proof of starting state
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Blender launched with empty session"
echo "Spec: /home/ga/Desktop/grid_specification.txt"
echo "Expected output: /home/ga/BIMProjects/warehouse_grid.ifc"