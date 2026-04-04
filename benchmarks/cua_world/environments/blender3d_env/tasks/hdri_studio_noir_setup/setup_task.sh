#!/bin/bash
echo "=== Setting up HDRI Studio Noir task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ================================================================
# 1. PREPARE ASSETS (Real Data)
# ================================================================
ASSETS_DIR="/home/ga/assets"
mkdir -p "$ASSETS_DIR"
chown ga:ga "$ASSETS_DIR"

HDRI_URL="https://dl.polyhaven.org/file/ph-assets/HDRIs/exr/1k/studio_small_09_1k.exr"
HDRI_FILE="$ASSETS_DIR/studio_small_09_1k.exr"

if [ ! -f "$HDRI_FILE" ]; then
    echo "Downloading studio HDRI..."
    wget -q --show-progress "$HDRI_URL" -O "$HDRI_FILE" || {
        echo "Failed to download HDRI, creating placeholder for fallback (not ideal but safe)"
        # Fallback only if network fails - creates a valid tiny EXR header if possible, 
        # or just a dummy file to prevent File Not Found errors in Blender UI
        touch "$HDRI_FILE"
    }
    chown ga:ga "$HDRI_FILE"
fi

# ================================================================
# 2. PREPARE STARTING SCENE
# ================================================================
# We need a clean scene with a subject but NO lights and default world
START_BLEND="/home/ga/BlenderProjects/noir_start.blend"
mkdir -p "/home/ga/BlenderProjects"
chown ga:ga "/home/ga/BlenderProjects"

# Python script to generate the starting state
cat > /tmp/prepare_scene.py << 'PYEOF'
import bpy

# Start fresh
bpy.ops.wm.read_homefile(use_empty=True)

# Add a subject (Rounded Cube/Chamfer Box style)
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 1))
cube = bpy.context.active_object
cube.name = "Subject"
# Add a bevel modifier to make it look nicer for lighting
mod = cube.modifiers.new(name="Bevel", type='BEVEL')
mod.width = 0.1
mod.segments = 3
bpy.ops.object.shade_smooth()

# Add a ground plane
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"

# Add a Camera
bpy.ops.object.camera_add(location=(5, -5, 3))
cam = bpy.context.active_object
cam.rotation_euler = (1.1, 0, 0.785) # Roughly looking at cube
bpy.context.scene.camera = cam

# Ensure NO LIGHTS exist
for obj in bpy.data.objects:
    if obj.type == 'LIGHT':
        bpy.data.objects.remove(obj, do_unlink=True)

# Reset World to basic grey, Use Nodes = False initially
world = bpy.data.worlds.new("NoirWorld")
bpy.context.scene.world = world
world.use_nodes = False
world.color = (0.05, 0.05, 0.05) # Start very dark so they HAVE to add light

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/noir_start.blend")
PYEOF

# Run generation script
/opt/blender/blender --background --python /tmp/prepare_scene.py > /dev/null 2>&1

# ================================================================
# 3. LAUNCH BLENDER
# ================================================================
echo "Launching Blender..."
pkill -x blender 2>/dev/null || true
su - ga -c "DISPLAY=:1 /opt/blender/blender '$START_BLEND' &"

# Wait for Blender to be ready
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Blender"; then
        break
    fi
    sleep 1
done

# Focus and maximize
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
echo "Capturing initial screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="