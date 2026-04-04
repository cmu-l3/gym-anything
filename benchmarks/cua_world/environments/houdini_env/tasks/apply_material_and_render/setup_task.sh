#!/bin/bash
echo "=== Setting up apply_material_and_render task ==="

# Source utilities
source /workspace/scripts/task_utils.sh
setup_houdini_env

# Verify source scene exists
SOURCE_SCENE="/home/ga/HoudiniProjects/bunny_scene.hipnc"
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found: $SOURCE_SCENE"
    echo "Attempting to recreate..."
    # Run the setup script snippet to create it
    HFS_DIR=$(get_hfs_dir)
    "$HFS_DIR/bin/hython" -c "
import hou
import os

geo = hou.node('/obj').createNode('geo', 'bunny')
bunny_path = '/home/ga/HoudiniProjects/data/bunny.obj'
if os.path.exists(bunny_path):
    file_sop = geo.createNode('file', 'import_bunny')
    file_sop.parm('file').set(bunny_path)
    xform = geo.createNode('xform', 'center_scale')
    xform.setInput(0, file_sop)
    xform.parm('scale').set(5.0)
    xform.setDisplayFlag(True)
    xform.setRenderFlag(True)
else:
    torus = geo.createNode('torus')
    torus.setDisplayFlag(True)
    torus.setRenderFlag(True)

cam = hou.node('/obj').createNode('cam', 'render_camera')
cam.parm('tx').set(3); cam.parm('ty').set(2); cam.parm('tz').set(3)
cam.parm('rx').set(-25); cam.parm('ry').set(45)

env_light = hou.node('/obj').createNode('envlight', 'env_light')
hdri_path = '/home/ga/HoudiniProjects/data/venice_sunset_1k.hdr'
if os.path.exists(hdri_path):
    env_light.parm('env_map').set(hdri_path)

key_light = hou.node('/obj').createNode('hlight', 'key_light')
key_light.parm('tx').set(4); key_light.parm('ty').set(6); key_light.parm('tz').set(2)

hou.node('/obj').layoutChildren()
geo.layoutChildren()
hou.hipFile.save('$SOURCE_SCENE')
print('Scene recreated')
" 2>/dev/null || echo "WARNING: Could not recreate scene"
fi

# Verify HDRI exists
HDRI_PATH="/home/ga/HoudiniProjects/data/venice_sunset_1k.hdr"
if [ ! -f "$HDRI_PATH" ]; then
    echo "Downloading HDRI..."
    wget -q --timeout=60 "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/venice_sunset_1k.hdr" -O "$HDRI_PATH" 2>/dev/null || \
    echo "WARNING: Could not download HDRI"
    chown ga:ga "$HDRI_PATH" 2>/dev/null || true
fi

# Record initial state
OUTPUT_SCENE="/home/ga/HoudiniProjects/bunny_material.hipnc"
RENDER_PATH="/home/ga/HoudiniProjects/renders/bunny_render.png"
rm -f "$OUTPUT_SCENE" "$RENDER_PATH"
mkdir -p "$(dirname "$RENDER_PATH")"
chown -R ga:ga /home/ga/HoudiniProjects/

# Get initial scene info
HFS_DIR=$(get_hfs_dir)
INITIAL_INFO=$("$HFS_DIR/bin/hython" -c "
import hou, json, os
hou.hipFile.load('$SOURCE_SCENE')
materials = [n.name() for n in hou.node('/mat').children()] if hou.node('/mat') else []
result = {
    'node_count': len(hou.node('/obj').children()),
    'material_count': len(materials),
    'materials': materials,
    'has_render_node': bool(hou.node('/out') and hou.node('/out').children()),
}
print(json.dumps(result))
" 2>/dev/null || echo '{"node_count": 0, "material_count": 0, "materials": [], "has_render_node": false}')

cat > /tmp/initial_state.json << EOF
{
    "source_scene": "$SOURCE_SCENE",
    "output_scene": "$OUTPUT_SCENE",
    "render_path": "$RENDER_PATH",
    "initial_scene_info": $INITIAL_INFO,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state:"
cat /tmp/initial_state.json

# Kill any existing Houdini instance
kill_houdini

# Launch Houdini with the bunny scene
launch_houdini "$SOURCE_SCENE"
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
echo "Task: Apply gold material to bunny, render to $RENDER_PATH, save as $OUTPUT_SCENE"
