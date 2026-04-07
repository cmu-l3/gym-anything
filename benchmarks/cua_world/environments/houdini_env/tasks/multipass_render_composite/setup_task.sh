#!/bin/bash
echo "=== Setting up multipass_render_composite task ==="

# Source utilities
source /workspace/scripts/task_utils.sh
setup_houdini_env

HFS_DIR=$(get_hfs_dir)

# ================================================================
# CREATE PRE-LIT SCENE WITH HYTHON
# ================================================================
SOURCE_SCENE="/home/ga/HoudiniProjects/lit_scene.hipnc"
echo "Creating pre-lit scene: $SOURCE_SCENE"

"$HFS_DIR/bin/hython" -c "
import hou
import os

# -----------------------------------------------------------
# Geometry: teapot (fall back to torus if obj missing)
# -----------------------------------------------------------
geo = hou.node('/obj').createNode('geo', 'teapot')
teapot_path = '/home/ga/HoudiniProjects/data/teapot.obj'
if os.path.exists(teapot_path):
    file_sop = geo.createNode('file', 'import_teapot')
    file_sop.parm('file').set(teapot_path)
    xform = geo.createNode('xform', 'center_scale')
    xform.setInput(0, file_sop)
    xform.parm('scale').set(1.0)
    xform.setDisplayFlag(True)
    xform.setRenderFlag(True)
else:
    print('WARNING: teapot.obj not found, creating torus instead')
    torus = geo.createNode('torus')
    torus.setDisplayFlag(True)
    torus.setRenderFlag(True)

geo.layoutChildren()

# -----------------------------------------------------------
# Material: blue ceramic principled shader
# -----------------------------------------------------------
mat_net = hou.node('/mat')
if not mat_net:
    mat_net = hou.node('/').createNode('matnet', 'mat')
shader = mat_net.createNode('principledshader::2.0', 'blue_ceramic')
shader.parm('basecolorr').set(0.1)
shader.parm('basecolorg').set(0.2)
shader.parm('basecolorb').set(0.6)
shader.parm('metallic').set(0.0)
shader.parm('rough').set(0.3)

# Assign material to teapot
geo.parm('shop_materialpath').set(shader.path())

# -----------------------------------------------------------
# Lighting
# -----------------------------------------------------------
# Key light
key_light = hou.node('/obj').createNode('hlight', 'key_light')
key_light.parm('tx').set(5)
key_light.parm('ty').set(8)
key_light.parm('tz').set(4)
key_light.parm('light_intensity').set(1.0)

# Fill light (lower intensity)
fill_light = hou.node('/obj').createNode('hlight', 'fill_light')
fill_light.parm('tx').set(-3)
fill_light.parm('ty').set(4)
fill_light.parm('tz').set(-2)
fill_light.parm('light_intensity').set(0.4)

# Environment light with Venice HDRI
env_light = hou.node('/obj').createNode('envlight', 'env_light')
hdri_path = '/home/ga/HoudiniProjects/data/venice_sunset_1k.hdr'
if os.path.exists(hdri_path):
    env_light.parm('env_map').set(hdri_path)
else:
    print('WARNING: HDRI not found at ' + hdri_path)

# -----------------------------------------------------------
# Camera
# -----------------------------------------------------------
cam = hou.node('/obj').createNode('cam', 'render_camera')
cam.parm('tx').set(4)
cam.parm('ty').set(3)
cam.parm('tz').set(4)
# Point camera at origin
import math
dx, dy, dz = -4.0, -3.0, -4.0
dist_xz = math.sqrt(dx*dx + dz*dz)
ry = math.degrees(math.atan2(dx, dz))
rx = math.degrees(math.atan2(-dy, dist_xz))
cam.parm('rx').set(rx)
cam.parm('ry').set(ry)
cam.parm('rz').set(0)

# -----------------------------------------------------------
# Basic Mantra node (NO extra image planes -- agent must add)
# -----------------------------------------------------------
out_node = hou.node('/out')
if not out_node:
    out_node = hou.node('/').createNode('ropnet', 'out')
mantra = out_node.createNode('ifd', 'mantra_render')
mantra.parm('camera').set('/obj/render_camera')
mantra.parm('vm_picture').set('/home/ga/HoudiniProjects/renders/passes/beauty.\$F4.exr')
mantra.parm('vm_resolution_x').set(960)
mantra.parm('vm_resolution_y').set(540)

# -----------------------------------------------------------
# NO COP network -- agent must create it
# -----------------------------------------------------------

# Layout and save
hou.node('/obj').layoutChildren()
hou.hipFile.save('$SOURCE_SCENE')
print('Pre-lit scene saved to $SOURCE_SCENE')
" 2>&1

if [ $? -ne 0 ]; then
    echo "ERROR: hython scene creation failed"
fi

# ================================================================
# VERIFY SOURCE SCENE
# ================================================================
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found: $SOURCE_SCENE"
    exit 1
fi
echo "Source scene verified: $SOURCE_SCENE ($(stat -c%s "$SOURCE_SCENE" 2>/dev/null || echo 0) bytes)"

# ================================================================
# PREPARE RENDER DIRECTORIES AND CLEAN STALE OUTPUTS
# ================================================================
OUTPUT_SCENE="/home/ga/HoudiniProjects/multipass_composite.hipnc"
RENDER_DIR="/home/ga/HoudiniProjects/renders/passes"
COMPOSITE_PATH="/home/ga/HoudiniProjects/renders/final_composite.exr"

mkdir -p "$RENDER_DIR"
rm -f "$OUTPUT_SCENE"
rm -f "$COMPOSITE_PATH"
rm -f "$RENDER_DIR"/*.exr 2>/dev/null || true
chown -R ga:ga /home/ga/HoudiniProjects/

# ================================================================
# RECORD INITIAL STATE
# ================================================================
INITIAL_INFO=$("$HFS_DIR/bin/hython" -c "
import hou, json
hou.hipFile.load('$SOURCE_SCENE')

# Count nodes
obj_children = [n.name() for n in hou.node('/obj').children()]
mat_children = [n.name() for n in hou.node('/mat').children()] if hou.node('/mat') else []

# Check mantra for extra image planes
mantra_planes = 0
out = hou.node('/out')
if out:
    for child in out.children():
        if child.type().name() == 'ifd':
            p = child.parm('vm_numaux')
            if p:
                mantra_planes = p.eval()

# Check for COP network
has_cop = hou.node('/img') is not None

result = {
    'obj_nodes': obj_children,
    'materials': mat_children,
    'mantra_extra_planes': mantra_planes,
    'has_cop_network': has_cop,
}
print(json.dumps(result))
" 2>/dev/null || echo '{"obj_nodes": [], "materials": [], "mantra_extra_planes": 0, "has_cop_network": false}')

cat > /tmp/initial_state.json << EOF
{
    "source_scene": "$SOURCE_SCENE",
    "output_scene": "$OUTPUT_SCENE",
    "render_dir": "$RENDER_DIR",
    "composite_path": "$COMPOSITE_PATH",
    "initial_scene_info": $INITIAL_INFO,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state:"
cat /tmp/initial_state.json

# ================================================================
# LAUNCH HOUDINI
# ================================================================
kill_houdini
launch_houdini "$SOURCE_SCENE"
wait_for_houdini_window 60

# Focus and maximize
sleep 2
focus_houdini
sleep 1
maximize_houdini
sleep 1

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Set up multi-pass Mantra rendering with AOVs, build COP compositing network,"
echo "       render passes to $RENDER_DIR, composite to $COMPOSITE_PATH,"
echo "       save scene as $OUTPUT_SCENE"
