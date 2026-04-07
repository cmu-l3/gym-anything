#!/bin/bash
echo "=== Setting up single_storey_retail_unit_authoring task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file (BEFORE recording timestamp) ───────
rm -f /home/ga/BIMProjects/retail_unit.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender processes ────────────────────────────────
kill_blender

# ── 4. Record task start timestamp ────────────────────────────────────────
date +%s.%N > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── 5. Create Python startup script to create IFC4 project ───────────────
cat > /tmp/setup_retail_unit.py << 'PYEOF'
import bpy
import sys

status_file = '/tmp/retail_unit_setup_status'

def create_ifc_project():
    """Create a new IFC4 project with spatial hierarchy."""
    try:
        bpy.ops.bim.create_project()
        with open(status_file, 'w') as f:
            f.write('SUCCESS')
        print("IFC4 project created successfully for retail unit task")
    except Exception as e:
        with open(status_file, 'w') as f:
            f.write(f'FAILED: {e}')
        print(f"Error creating IFC project: {e}", file=sys.stderr)
    return None

bpy.app.timers.register(create_ifc_project, first_interval=3.0)
PYEOF

# ── 6. Remove old status file ─────────────────────────────────────────────
rm -f /tmp/retail_unit_setup_status

# ── 7. Launch Blender with the setup script ───────────────────────────────
echo "Launching Blender with IFC project creation script..."
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/setup_retail_unit.py > /tmp/blender_retail_setup.log 2>&1 &"

# Wait for Blender window to appear
WAIT_COUNT=0
while [ $WAIT_COUNT -lt 20 ]; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "blender" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Blender window detected: $WID"
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

# Extra time for IFC project creation via timer
sleep 10

# ── 8. Verify the project was created ─────────────────────────────────────
if [ -f /tmp/retail_unit_setup_status ]; then
    CREATE_STATUS=$(cat /tmp/retail_unit_setup_status)
    if [[ "$CREATE_STATUS" != "SUCCESS" ]]; then
        echo "WARNING: IFC project creation reported: $CREATE_STATUS"
        echo "Check /tmp/blender_retail_setup.log for details"
    else
        echo "IFC project created successfully"
    fi
else
    echo "WARNING: Setup status file not found — Blender may still be loading"
    echo "Check /tmp/blender_retail_setup.log for details"
fi

# ── 9. Save initial state ─────────────────────────────────────────────────
cat > /tmp/initial_state.json << EOF
{
    "output_file": "/home/ga/BIMProjects/retail_unit.ifc",
    "output_exists": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

# ── 10. Dismiss any dialogs, focus, maximize ──────────────────────────────
dismiss_blender_dialogs
sleep 1
focus_blender
maximize_blender
sleep 1

# ── 11. Take initial screenshot ───────────────────────────────────────────
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "BlenderBIM is open with a new IFC4 project."
echo "Spatial hierarchy: IfcProject > IfcSite > IfcBuilding > IfcBuildingStorey"
echo "Agent must model a 12m x 8m retail unit with walls, slabs, doors, spaces."
echo "Save the final model as /home/ga/BIMProjects/retail_unit.ifc"
