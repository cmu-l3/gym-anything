#!/bin/bash
set -e
echo "=== Setting up Campfire Simulation Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

PROJECTS_DIR="/home/ga/BlenderProjects"
BASELINE_BLEND="$PROJECTS_DIR/baseline_scene.blend"
OUTPUT_BLEND="$PROJECTS_DIR/campfire_sim.blend"

mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# 1. Create Baseline Scene if it doesn't exist
# We create a simple scene with a ground plane, camera, light, and a base cube
if [ ! -f "$BASELINE_BLEND" ]; then
    echo "Generating baseline scene..."
    cat > /tmp/create_baseline.py << 'PYEOF'
import bpy
import os

# Reset
bpy.ops.wm.read_homefile(use_empty=True)

# 1. Ground Plane
bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
plane = bpy.context.active_object
plane.name = "Ground"

# 2. Base Cube (just visual anchor)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.5))
cube = bpy.context.active_object
cube.name = "BaseCube"
mat = bpy.data.materials.new(name="Charcoal")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
if bsdf:
    bsdf.inputs["Base Color"].default_value = (0.1, 0.1, 0.1, 1)
cube.data.materials.append(mat)

# 3. Camera
bpy.ops.object.camera_add(location=(5, -5, 3), rotation=(1.1, 0, 0.78))
cam = bpy.context.active_object
cam.name = "MainCamera"
bpy.context.scene.camera = cam

# 4. Light
bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
light = bpy.context.active_object
light.name = "Sun"
light.data.energy = 5.0

# Settings
bpy.context.scene.render.engine = 'CYCLES'
bpy.context.scene.cycles.samples = 32

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/baseline_scene.blend")
PYEOF

    su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/create_baseline.py" 2>/dev/null
fi

# 2. Record Initial State (to detect "Do Nothing")
cat > /tmp/record_initial.py << 'PYEOF'
import bpy
import json

bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/baseline_scene.blend")

state = {
    "object_count": len(bpy.data.objects),
    "objects": [o.name for o in bpy.data.objects],
    "has_fluid_modifier": False
}

for obj in bpy.data.objects:
    for mod in obj.modifiers:
        if mod.type == 'FLUID':
            state["has_fluid_modifier"] = True

print("INITIAL_JSON:" + json.dumps(state))
PYEOF

# Run analysis
INITIAL_JSON=$(su - ga -c "/opt/blender/blender --background --python /tmp/record_initial.py 2>/dev/null" | grep "^INITIAL_JSON:" | sed 's/^INITIAL_JSON://')
echo "$INITIAL_JSON" > /tmp/initial_state.json

# 3. Clean up previous results
rm -f "$OUTPUT_BLEND"
rm -f /tmp/task_result.json

# 4. Launch Blender
echo "Launching Blender..."
pkill -f "blender" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 /opt/blender/blender '$BASELINE_BLEND' &"

# 5. Wait for window and maximize
sleep 5
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Blender"; then
        echo "Blender window detected."
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# 6. Initial Screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="