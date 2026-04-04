#!/bin/bash
echo "=== Setting up import_obj_model task ==="

# Source utilities
source /workspace/scripts/task_utils.sh
setup_houdini_env

# Verify real data exists
OBJ_PATH="/home/ga/HoudiniProjects/data/bunny.obj"
if [ ! -f "$OBJ_PATH" ]; then
    echo "ERROR: Stanford Bunny OBJ not found at $OBJ_PATH"
    echo "Attempting to download..."
    mkdir -p "$(dirname "$OBJ_PATH")"
    wget -q --timeout=30 "https://graphics.stanford.edu/~mdfisher/Data/Meshes/bunny.obj" -O "$OBJ_PATH" 2>/dev/null || \
    wget -q --timeout=30 "https://raw.githubusercontent.com/alecjacobson/common-3d-test-models/master/data/stanford-bunny.obj" -O "$OBJ_PATH" 2>/dev/null || {
        echo "ERROR: Could not download Stanford Bunny OBJ"
        exit 1
    }
    chown ga:ga "$OBJ_PATH"
fi

echo "OBJ file ready: $(du -h "$OBJ_PATH" | cut -f1)"

# Record initial state
OUTPUT_HIPNC="/home/ga/HoudiniProjects/imported_bunny.hipnc"
rm -f "$OUTPUT_HIPNC"

cat > /tmp/initial_state.json << EOF
{
    "source_obj": "$OBJ_PATH",
    "output_hipnc": "$OUTPUT_HIPNC",
    "obj_exists": true,
    "obj_size": $(stat -c%s "$OBJ_PATH" 2>/dev/null || echo 0),
    "timestamp": "$(date -Iseconds)"
}
EOF
echo "Initial state saved to /tmp/initial_state.json"

# Kill any existing Houdini instance
kill_houdini

# Launch Houdini with a fresh empty scene
HFS_DIR=$(get_hfs_dir)
launch_houdini
wait_for_houdini_window 60

# Focus and maximize
sleep 2
focus_houdini
sleep 1
maximize_houdini
sleep 1

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Import $OBJ_PATH into Houdini and save as $OUTPUT_HIPNC"
