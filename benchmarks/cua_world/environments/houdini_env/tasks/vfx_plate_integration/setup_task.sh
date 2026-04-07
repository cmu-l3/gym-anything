#!/bin/bash
echo "=== Setting up vfx_plate_integration task ==="

# Source utilities
source /workspace/scripts/task_utils.sh
setup_houdini_env

# ================================================================
# ENSURE DATA FILES EXIST
# ================================================================

# Verify Venice Sunset HDRI
HDRI_PATH="/home/ga/HoudiniProjects/data/venice_sunset_1k.hdr"
if [ ! -f "$HDRI_PATH" ]; then
    echo "Downloading Venice Sunset HDRI..."
    wget -q --timeout=60 "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/venice_sunset_1k.hdr" -O "$HDRI_PATH" 2>/dev/null || \
        echo "WARNING: Could not download Venice HDRI"
    chown ga:ga "$HDRI_PATH" 2>/dev/null || true
fi

# Download an extra HDRI (may be useful for lighting reference)
EXTRA_HDRI="/home/ga/HoudiniProjects/data/sunset_puresky_1k.hdr"
if [ ! -f "$EXTRA_HDRI" ]; then
    echo "Downloading supplementary HDRI..."
    wget -q --timeout=60 "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/industrial_sunset_02_puresky_1k.hdr" -O "$EXTRA_HDRI" 2>/dev/null || true
    chown ga:ga "$EXTRA_HDRI" 2>/dev/null || true
fi

# Create background plate from Venice Sunset HDRI (real data, not synthetic)
BG_PLATE="/home/ga/HoudiniProjects/data/bg_plate.jpg"
if [ ! -f "$BG_PLATE" ]; then
    echo "Generating background plate from Venice Sunset HDRI..."
    # Convert the real HDRI to a tonemapped JPG background plate using Python/OpenImageIO or PIL
    python3 -c "
import sys, os
hdri_path = '/home/ga/HoudiniProjects/data/venice_sunset_1k.hdr'
out_path = '$BG_PLATE'
try:
    import numpy as np
    # Read HDR using imageio (supports .hdr format)
    import imageio
    hdr = imageio.imread(hdri_path, format='HDR-FI')
    # Simple Reinhard tonemap
    hdr_clipped = np.maximum(hdr, 0.0)
    lum = 0.2126 * hdr_clipped[:,:,0] + 0.7152 * hdr_clipped[:,:,1] + 0.0722 * hdr_clipped[:,:,2]
    lum_avg = np.exp(np.mean(np.log(lum + 1e-6)))
    scaled = hdr_clipped * (0.18 / (lum_avg + 1e-6))
    tonemapped = scaled / (1.0 + scaled)
    # Gamma correction
    tonemapped = np.power(np.clip(tonemapped, 0, 1), 1.0/2.2)
    ldr = (tonemapped * 255).astype(np.uint8)
    # Resize to 1920x1080
    from PIL import Image
    img = Image.fromarray(ldr)
    img = img.resize((1920, 1080), Image.LANCZOS)
    img.save(out_path, quality=95)
    print('Background plate created from HDRI')
except Exception as e:
    # Fallback: use convert to tonemap the HDRI
    print(f'Python tonemap failed: {e}', file=sys.stderr)
    os.system(f'convert \"{hdri_path}\" -resize 1920x1080! -depth 8 \"{out_path}\" 2>/dev/null')
    if not os.path.exists(out_path):
        # Last resort: download a real backplate from Poly Haven
        os.system('wget -q --timeout=60 \"https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped/venice_sunset/venice_sunset_1k.jpg\" -O \"' + out_path + '\"')
" 2>/dev/null || true
    chown ga:ga "$BG_PLATE" 2>/dev/null || true
fi

# Verify bunny model exists
BUNNY_PATH="/home/ga/HoudiniProjects/data/bunny.obj"
if [ ! -f "$BUNNY_PATH" ]; then
    echo "WARNING: bunny.obj not found at $BUNNY_PATH"
fi

# ================================================================
# CREATE OUTPUT DIRECTORIES AND CLEAN STALE FILES
# ================================================================
OUTPUT_SCENE="/home/ga/HoudiniProjects/vfx_integration.hipnc"
SOURCE_SCENE="/home/ga/HoudiniProjects/integration_base.hipnc"
RENDER_DIR="/home/ga/HoudiniProjects/renders/integration"

mkdir -p "$RENDER_DIR"
rm -f "$OUTPUT_SCENE"
rm -f "$RENDER_DIR"/* 2>/dev/null || true
rm -f /tmp/task_result.json

# ================================================================
# CREATE BASE SCENE WITH HYTHON
# ================================================================
echo "Creating base scene with hython..."
HFS_DIR=$(get_hfs_dir)
"$HFS_DIR/bin/hython" -c "
import hou
import os

# ----------------------------------------------------------
# 1. Import bunny.obj into /obj/bunny geo node
# ----------------------------------------------------------
bunny_geo = hou.node('/obj').createNode('geo', 'bunny')
bunny_path = '/home/ga/HoudiniProjects/data/bunny.obj'
if os.path.exists(bunny_path):
    file_sop = bunny_geo.createNode('file', 'import_bunny')
    file_sop.parm('file').set(bunny_path)
    xform = bunny_geo.createNode('xform', 'center_scale')
    xform.setInput(0, file_sop)
    xform.parm('scale').set(5.0)
    xform.setDisplayFlag(True)
    xform.setRenderFlag(True)
else:
    # Fallback: create a simple sphere as stand-in
    sphere = bunny_geo.createNode('sphere', 'bunny_standin')
    sphere.setDisplayFlag(True)
    sphere.setRenderFlag(True)
bunny_geo.layoutChildren()

# ----------------------------------------------------------
# 2. Set up environment light with Venice Sunset HDRI
# ----------------------------------------------------------
env_light = hou.node('/obj').createNode('envlight', 'env_light')
hdri_path = '/home/ga/HoudiniProjects/data/venice_sunset_1k.hdr'
if os.path.exists(hdri_path):
    env_light.parm('env_map').set(hdri_path)

# ----------------------------------------------------------
# 3. Create camera at (3, 2, 3) looking at origin
# ----------------------------------------------------------
cam = hou.node('/obj').createNode('cam', 'render_camera')
cam.parm('tx').set(3)
cam.parm('ty').set(2)
cam.parm('tz').set(3)
cam.parm('rx').set(-25)
cam.parm('ry').set(45)

# ----------------------------------------------------------
# 4. Basic Mantra render node (no separate passes)
# ----------------------------------------------------------
mantra = hou.node('/out').createNode('ifd', 'mantra_render')
mantra.parm('camera').set('/obj/render_camera')
mantra.parm('vm_picture').set('/home/ga/HoudiniProjects/renders/integration/beauty.\$F4.exr')

# ----------------------------------------------------------
# Layout and save
# ----------------------------------------------------------
hou.node('/obj').layoutChildren()
hou.hipFile.save('$SOURCE_SCENE')
print('Base scene created successfully: $SOURCE_SCENE')
" 2>/dev/null || echo "WARNING: Could not create base scene with hython"

# ================================================================
# FIX OWNERSHIP
# ================================================================
chown -R ga:ga /home/ga/HoudiniProjects/

# ================================================================
# RECORD INITIAL STATE
# ================================================================
INITIAL_INFO=$("$HFS_DIR/bin/hython" -c "
import hou, json, os
hou.hipFile.load('$SOURCE_SCENE')

obj_children = [n.name() for n in hou.node('/obj').children()]
mat_children = [n.name() for n in hou.node('/mat').children()] if hou.node('/mat') else []
out_children = [n.name() for n in hou.node('/out').children()] if hou.node('/out') else []

# Check for COP network
has_cop = bool(hou.node('/img') and hou.node('/img').children())

result = {
    'obj_nodes': obj_children,
    'material_count': len(mat_children),
    'materials': mat_children,
    'out_nodes': out_children,
    'has_cop_network': has_cop,
    'note': 'No shadow catcher, no chrome material, no COP network - agent must create all'
}
print(json.dumps(result))
" 2>/dev/null || echo '{"obj_nodes": [], "material_count": 0, "materials": [], "out_nodes": [], "has_cop_network": false}')

cat > /tmp/initial_state.json << EOF
{
    "source_scene": "$SOURCE_SCENE",
    "output_scene": "$OUTPUT_SCENE",
    "render_dir": "$RENDER_DIR",
    "bg_plate_path": "$BG_PLATE",
    "initial_scene_info": $INITIAL_INFO,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state:"
cat /tmp/initial_state.json

# ================================================================
# LAUNCH HOUDINI WITH THE BASE SCENE
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
echo "Task: Set up VFX plate integration with shadow catcher, chrome material, multipass render, and COP2 compositing"
echo "Difficulty: very_hard"
echo "Source scene: $SOURCE_SCENE"
echo "Expected output: $OUTPUT_SCENE"
echo "Expected composite: $RENDER_DIR/final_comp.exr"
