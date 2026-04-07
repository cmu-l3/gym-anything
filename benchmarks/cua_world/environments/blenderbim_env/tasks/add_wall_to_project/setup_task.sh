#!/bin/bash
echo "=== Setting up add_wall_to_project task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# ── 1. Ensure output directory exists ─────────────────────────────────────
mkdir -p /home/ga/BIMProjects
chown ga:ga /home/ga/BIMProjects

# ── 2. Remove any existing output file ────────────────────────────────────
rm -f /home/ga/BIMProjects/wall_test.ifc 2>/dev/null || true

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Launch Blender and create an empty IFC project via Bonsai ──────────
echo "Creating empty IFC project in BlenderBIM..."

cat > /tmp/create_project.py << 'PYEOF'
import bpy
import sys

status_file = '/tmp/project_create_status'

try:
    bpy.ops.bim.create_project()
    with open(status_file, 'w') as f:
        f.write('SUCCESS')
    print('Empty IFC project created successfully')
except Exception as e:
    with open(status_file, 'w') as f:
        f.write(f'FAILED: {e}')
    print(f'ERROR: Failed to create IFC project: {e}', file=sys.stderr)
    sys.exit(1)
PYEOF

rm -f /tmp/project_create_status
su - ga -c "DISPLAY=:1 setsid /opt/blender/blender --python /tmp/create_project.py > /tmp/blender_project.log 2>&1 &"

sleep 10

# Verify the project was created
if [ -f /tmp/project_create_status ]; then
    CREATE_STATUS=$(cat /tmp/project_create_status)
    if [[ "$CREATE_STATUS" != "SUCCESS" ]]; then
        echo "ERROR: IFC project creation failed: $CREATE_STATUS"
        echo "Check /tmp/blender_project.log for details"
        exit 1
    fi
    echo "IFC project created successfully"
else
    echo "ERROR: Project create status file not found — Blender may have crashed or timed out"
    echo "Check /tmp/blender_project.log for details"
    exit 1
fi

# ── 5. Save initial state ────────────────────────────────────────────────
cat > /tmp/initial_state.json << EOF
{
    "output_file": "/home/ga/BIMProjects/wall_test.ifc",
    "output_exists": false,
    "timestamp": "$(date -Iseconds)"
}
EOF

# ── 6. Dismiss any dialogs ───────────────────────────────────────────────
dismiss_blender_dialogs
sleep 1

# ── 7. Focus and maximize Blender window ─────────────────────────────────
focus_blender
maximize_blender
sleep 1

# ── 8. Take initial screenshot ───────────────────────────────────────────
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should see: Blender with empty IFC project (IfcProject > IfcSite > IfcBuilding > IfcBuildingStorey)"
echo "Agent must: Add a wall element, then save as /home/ga/BIMProjects/wall_test.ifc"
