#!/bin/bash
echo "=== Setting up Linked Rig Animation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Directories
ASSETS_DIR="/home/ga/BlenderProjects/assets"
PROJECT_DIR="/home/ga/BlenderProjects"
mkdir -p "$ASSETS_DIR"
chown -R ga:ga "$PROJECT_DIR"

# Clean up previous runs
rm -f "$PROJECT_DIR/shot_01_animated.blend" 2>/dev/null
rm -f "$PROJECT_DIR/shot_scenefile.blend" 2>/dev/null
rm -f "$ASSETS_DIR/master_rig.blend" 2>/dev/null

# ================================================================
# 1. GENERATE MASTER RIG FILE (The Asset)
# ================================================================
echo "Generating master rig asset..."
cat > /tmp/gen_rig.py << 'PYEOF'
import bpy
import math

# Clear scene
bpy.ops.wm.read_homefile(use_empty=True)

# Create Collection
rig_col = bpy.data.collections.new("RoboArm_Collection")
bpy.context.scene.collection.children.link(rig_col)

# Create Armature
bpy.ops.object.armature_add(enter_editmode=True, location=(0,0,0))
amt_obj = bpy.context.active_object
amt_obj.name = "RoboArm_Rig"
amt_obj.data.name = "RoboArm_Data"
rig_col.objects.link(amt_obj)
bpy.context.scene.collection.objects.unlink(amt_obj) # Remove from default col

# Edit Bones
amt = amt_obj.data
bones = amt.edit_bones

# Rename default bone to Root
root = bones["Bone"]
root.name = "Root"
root.head = (0, 0, 0)
root.tail = (0, 0, 1)

# Add UpperArm
upper = bones.new("UpperArm")
upper.head = (0, 0, 1)
upper.tail = (0, 0, 3)
upper.parent = root
upper.use_connect = True

# Add Forearm
fore = bones.new("Forearm")
fore.head = (0, 0, 3)
fore.tail = (2, 0, 3) # Pointing sideways initially
fore.parent = upper
fore.use_connect = True

# Exit edit mode
bpy.ops.object.mode_set(mode='OBJECT')

# Create Mesh geometry to make it visible
bpy.ops.mesh.primitive_cube_add(size=0.5)
mesh_obj = bpy.context.active_object
mesh_obj.name = "Arm_Geo"
rig_col.objects.link(mesh_obj)
bpy.context.scene.collection.objects.unlink(mesh_obj)

# Parent mesh to bone
mesh_obj.parent = amt_obj
mesh_obj.parent_type = 'BONE'
mesh_obj.parent_bone = "Forearm"
mesh_obj.location = (1, 0, 3) # Local coords relative to bone

# Save Master File
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/assets/master_rig.blend")
PYEOF

/opt/blender/blender --background --python /tmp/gen_rig.py > /dev/null 2>&1

# ================================================================
# 2. GENERATE SHOT SCENE (The Task Start)
# ================================================================
echo "Generating shot scene..."
cat > /tmp/gen_shot.py << 'PYEOF'
import bpy

# Clear scene
bpy.ops.wm.read_homefile(use_empty=True)

# Add Target Object (Sphere)
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.5, location=(2.0, 0.0, 1.0))
target = bpy.context.active_object
target.name = "TargetObject"

# Add yellow material
mat = bpy.data.materials.new(name="TargetMat")
mat.use_nodes = True
bsdf = mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (1.0, 0.8, 0.0, 1.0)
target.data.materials.append(mat)

# Add Camera
bpy.ops.object.camera_add(location=(0, -8, 4), rotation=(1.1, 0, 0))
cam = bpy.context.active_object
bpy.context.scene.camera = cam

# Add Light
bpy.ops.object.light_add(type='SUN', location=(5, 5, 10))

# Save Shot File
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/shot_scenefile.blend")
PYEOF

/opt/blender/blender --background --python /tmp/gen_shot.py > /dev/null 2>&1

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Launch Blender with the shot file
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender /home/ga/BlenderProjects/shot_scenefile.blend &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Blender"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="