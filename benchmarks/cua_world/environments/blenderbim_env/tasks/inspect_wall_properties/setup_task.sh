#!/bin/bash
echo "=== Setting up inspect_wall_properties task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

IFC_FILE="/home/ga/IFCModels/fzk_haus.ifc"

# ── 1. Verify IFC model exists ────────────────────────────────────────────
if [ ! -f "$IFC_FILE" ]; then
    echo "ERROR: IFC model not found at $IFC_FILE"
    exit 1
fi

# ── 2. Save initial state with IFC element counts ─────────────────────────
WALL_COUNT=$(/opt/blender/blender --background --python-expr "
import sys
sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')
try:
    import ifcopenshell
    ifc = ifcopenshell.open('${IFC_FILE}')
    walls = ifc.by_type('IfcWall') + ifc.by_type('IfcWallStandardCase')
    print(len(walls))
except:
    print('0')
" 2>/dev/null | tail -1)

cat > /tmp/initial_state.json << EOF
{
    "ifc_file": "$IFC_FILE",
    "wall_count": ${WALL_COUNT:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "IFC model has ${WALL_COUNT:-unknown} walls"

# ── 3. Kill any existing Blender ──────────────────────────────────────────
kill_blender

# ── 4. Launch Blender and open the IFC file via Bonsai ────────────────────
echo "Opening IFC file in BlenderBIM..."

cat > /tmp/load_ifc.py << 'PYEOF'
import bpy
import sys
import os

ifc_file = os.environ.get('IFC_FILE_PATH', '')
status_file = '/tmp/ifc_load_status'

try:
    bpy.ops.bim.load_project(filepath=ifc_file)
    with open(status_file, 'w') as f:
        f.write('SUCCESS')
    print('IFC project loaded successfully via bpy.ops.bim.load_project')
except Exception as e:
    with open(status_file, 'w') as f:
        f.write(f'FAILED: {e}')
    print(f'ERROR: Failed to load IFC project: {e}', file=sys.stderr)
    sys.exit(1)
PYEOF

rm -f /tmp/ifc_load_status
su - ga -c "DISPLAY=:1 IFC_FILE_PATH='${IFC_FILE}' setsid /opt/blender/blender --python /tmp/load_ifc.py > /tmp/blender_ifc_open.log 2>&1 &"

# Wait for Blender to start and load the model
sleep 15

# Verify the IFC model was actually loaded
if [ -f /tmp/ifc_load_status ]; then
    LOAD_STATUS=$(cat /tmp/ifc_load_status)
    if [[ "$LOAD_STATUS" != "SUCCESS" ]]; then
        echo "ERROR: IFC model failed to load: $LOAD_STATUS"
        echo "Check /tmp/blender_ifc_open.log for details"
        exit 1
    fi
    echo "IFC model loaded successfully"
else
    echo "ERROR: IFC load status file not found — Blender may have crashed or timed out"
    echo "Check /tmp/blender_ifc_open.log for details"
    exit 1
fi

# ── 5. Dismiss any dialogs ───────────────────────────────────────────────
dismiss_blender_dialogs
sleep 1

# ── 6. Focus and maximize Blender window ─────────────────────────────────
focus_blender
maximize_blender
sleep 1

# ── 7. Zoom to fit the model in view ─────────────────────────────────────
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Home 2>/dev/null || true
sleep 1

# ── 8. Take initial screenshot ───────────────────────────────────────────
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should see: Blender with FZK-Haus IFC model loaded"
echo "Agent must: Select a wall, then inspect its IFC properties"
