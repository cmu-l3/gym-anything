#!/bin/bash
echo "=== Setting up Soft Body Jello Simulation ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create projects directory
mkdir -p /home/ga/BlenderProjects
chown ga:ga /home/ga/BlenderProjects

# Remove any previous output
rm -f /home/ga/BlenderProjects/jelly_sim.blend

# ------------------------------------------------------------------
# GENERATE STARTING SCENE (Headless Blender)
# ------------------------------------------------------------------
# We create a clean scene with Suzanne and a Plate, materials applied,
# but NO physics modifiers.
# ------------------------------------------------------------------
cat > /tmp/create_start_scene.py << 'PYEOF'
import bpy
import math

# Clear default scene
bpy.ops.wm.read_homefile(use_empty=True)

# 1. Create the "Plate" (Collider)
bpy.ops.mesh.primitive_cylinder_add(
    radius=2.0, 
    depth=0.2, 
    location=(0, 0, -0.1)
)
plate = bpy.context.active_object
plate.name = "Plate"

# Plate Material (Ceramic)
mat_plate = bpy.data.materials.new(name="CeramicWhite")
mat_plate.use_nodes = True
nodes = mat_plate.node_tree.nodes
nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.9, 0.9, 0.9, 1)
nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.1
plate.data.materials.append(mat_plate)

# 2. Create "JellySuzanne" (The Soft Body Subject)
bpy.ops.mesh.primitive_monkey_add(
    size=1.0, 
    location=(0, 0, 3.0)
)
jelly = bpy.context.active_object
jelly.name = "JellySuzanne"

# Rotate it slightly so it lands interestingly
jelly.rotation_euler = (math.radians(45), math.radians(15), 0)

# Subdivide it slightly so it has geometry to deform
bpy.ops.object.modifier_add(type='SUBSURF')
jelly.modifiers["Subdivision"].levels = 1
# Apply modifier to bake geometry for physics
bpy.ops.object.modifier_apply(modifier="Subdivision")
bpy.ops.object.shade_smooth()

# Jelly Material (Red, Translucent)
mat_jelly = bpy.data.materials.new(name="StrawberryJelly")
mat_jelly.use_nodes = True
nodes = mat_jelly.node_tree.nodes
bsdf = nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.8, 0.05, 0.05, 1)
bsdf.inputs["Roughness"].default_value = 0.05
# Handle different Blender versions for Transmission
if "Transmission Weight" in bsdf.inputs:
    bsdf.inputs["Transmission Weight"].default_value = 0.8
elif "Transmission" in bsdf.inputs:
    bsdf.inputs["Transmission"].default_value = 0.8
jelly.data.materials.append(mat_jelly)

# 3. Setup Camera and Light
bpy.ops.object.camera_add(location=(0, -7, 3), rotation=(math.radians(80), 0, 0))
cam = bpy.context.active_object
cam.name = "MainCamera"
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))
light = bpy.context.active_object
light.data.energy = 5.0

# 4. Timeline Settings
bpy.context.scene.frame_start = 1
bpy.context.scene.frame_end = 100

# Save
output_path = "/home/ga/BlenderProjects/soft_body_start.blend"
bpy.ops.wm.save_as_mainfile(filepath=output_path)
print(f"Scene saved to {output_path}")
PYEOF

echo "Generating starting scene..."
su - ga -c "/opt/blender/blender --background --python /tmp/create_start_scene.py" > /dev/null 2>&1

# ------------------------------------------------------------------
# LAUNCH BLENDER
# ------------------------------------------------------------------
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender /home/ga/BlenderProjects/soft_body_start.blend &"

# Wait for Blender
sleep 5
focus_blender
maximize_blender
sleep 2

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="