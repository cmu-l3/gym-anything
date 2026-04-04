#!/bin/bash
echo "=== Setting up displacement_terrain_generation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure project directory exists
PROJECTS_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Clean previous outputs
rm -f "$PROJECTS_DIR/terrain_scene.blend"
rm -f "$PROJECTS_DIR/terrain_render.png"

# We use the baseline scene (Cube, Camera, Light, Plane) as the starting point
BASELINE_BLEND="/home/ga/BlenderProjects/baseline_scene.blend"
START_SCENE="/home/ga/BlenderProjects/start_terrain.blend"

# Ensure baseline exists, otherwise create a minimal one
if [ ! -f "$BASELINE_BLEND" ]; then
    echo "Creating minimal baseline scene..."
    /opt/blender/blender --background --python-expr "
import bpy
bpy.ops.wm.read_homefile(use_empty=True)
bpy.ops.mesh.primitive_cube_add(location=(0,0,1))
bpy.ops.mesh.primitive_plane_add(size=10, location=(0,0,0))
bpy.ops.object.camera_add(location=(7,-7,5), rotation=(1.1, 0, 0.8))
bpy.ops.object.light_add(type='SUN', location=(5,5,10))
bpy.ops.wm.save_as_mainfile(filepath='$BASELINE_BLEND')
" > /dev/null 2>&1
fi

# Copy baseline to start scene to work on
cp "$BASELINE_BLEND" "$START_SCENE"
chown ga:ga "$START_SCENE"

# Record initial vertex count (to prove agent subdivided)
# Run python script in background to get stats
INITIAL_VERTS=$(/opt/blender/blender --background "$START_SCENE" --python-expr "
import bpy
total_verts = sum(len(o.data.vertices) for o in bpy.data.objects if o.type == 'MESH')
print(f'VERTS:{total_verts}')
" 2>/dev/null | grep "VERTS:" | cut -d':' -f2)

echo "$INITIAL_VERTS" > /tmp/initial_verts.txt
echo "Initial vertex count: $INITIAL_VERTS"

# Launch Blender
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$START_SCENE' &"

# Wait for window and maximize
sleep 5
maximize_blender

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="