#!/bin/bash
echo "=== Setting up asset_append_scene_assembly task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Directory setup
PROJECTS_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# ================================================================
# 1. CREATE FURNITURE LIBRARY FILE
# ================================================================
echo "Generating furniture library..."
cat > /tmp/create_library.py << 'PYEOF'
import bpy

# Clear default scene
bpy.ops.wm.read_homefile(use_empty=True)

# Helper to create material
def create_mat(name, color):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    return mat

wood_mat = create_mat("Wood", (0.3, 0.2, 0.1, 1.0))
dark_mat = create_mat("DarkFabric", (0.1, 0.1, 0.1, 1.0))

# --- Create Table ---
# Tabletop
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.725))
table = bpy.context.active_object
table.name = "Table"
table.scale = (1.5, 0.8, 0.05)
table.data.materials.append(wood_mat)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

# Table Legs (joined to table for simplicity, or separate)
# For this task, we'll keep it as one object to make appending easier for the agent
for x in [-0.7, 0.7]:
    for y in [-0.35, 0.35]:
        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, 0.35))
        leg = bpy.context.active_object
        leg.scale = (0.05, 0.05, 0.7)
        leg.data.materials.append(wood_mat)
        bpy.ops.object.transform_apply(scale=True)
        # Join to table
        leg.select_set(True)
        table.select_set(True)
        bpy.context.view_layer.objects.active = table
        bpy.ops.object.join()

# --- Create Chair ---
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.45))
chair = bpy.context.active_object
chair.name = "Chair"
chair.scale = (0.45, 0.45, 0.05) # Seat
chair.data.materials.append(dark_mat)
bpy.ops.object.transform_apply(scale=True)

# Backrest
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.2, 0.9))
back = bpy.context.active_object
back.scale = (0.45, 0.05, 0.4)
back.data.materials.append(dark_mat)
bpy.ops.object.transform_apply(scale=True)
back.select_set(True)
chair.select_set(True)
bpy.context.view_layer.objects.active = chair
bpy.ops.object.join()

# Chair Legs
for x in [-0.2, 0.2]:
    for y in [-0.2, 0.2]:
        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, 0.21))
        leg = bpy.context.active_object
        leg.scale = (0.04, 0.04, 0.42)
        leg.data.materials.append(wood_mat)
        bpy.ops.object.transform_apply(scale=True)
        leg.select_set(True)
        chair.select_set(True)
        bpy.context.view_layer.objects.active = chair
        bpy.ops.object.join()

# Move chair away from origin in library so they don't spawn inside each other if appended together?
# Actually, keeping them at origin in library is standard.

# --- Create Bookshelf ---
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.9))
shelf = bpy.context.active_object
shelf.name = "Bookshelf"
shelf.scale = (0.8, 0.3, 1.8)
shelf.data.materials.append(wood_mat)
bpy.ops.object.transform_apply(scale=True)

# Save Library
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/furniture_library.blend")
PYEOF

su - ga -c "/opt/blender/blender --background --python /tmp/create_library.py" > /dev/null 2>&1

# ================================================================
# 2. CREATE ROOM SCENE FILE
# ================================================================
echo "Generating room scene..."
cat > /tmp/create_room.py << 'PYEOF'
import bpy

# Clear default scene
bpy.ops.wm.read_homefile(use_empty=True)

# Create Floor
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0))
floor = bpy.context.active_object
floor.name = "RoomFloor"
floor.scale = (8, 6, 1)
bpy.ops.object.transform_apply(scale=True)

mat_floor = bpy.data.materials.new(name="FloorMat")
mat_floor.use_nodes = True
mat_floor.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.8, 0.8, 0.8, 1.0)
floor.data.materials.append(mat_floor)

# Create Walls
def create_wall(name, loc, scale, rot_z=0):
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc)
    wall = bpy.context.active_object
    wall.name = name
    wall.rotation_euler[0] = 1.5708 # 90 deg X
    wall.rotation_euler[2] = rot_z
    wall.scale = scale
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    return wall

create_wall("Wall_Back", (0, 3, 1.5), (8, 3, 1))
create_wall("Wall_Front", (0, -3, 1.5), (8, 3, 1))
create_wall("Wall_Left", (-4, 0, 1.5), (6, 3, 1), 1.5708)
create_wall("Wall_Right", (4, 0, 1.5), (6, 3, 1), 1.5708)

# Camera
bpy.ops.object.camera_add(location=(5, -5, 4), rotation=(1.0, 0.0, 0.78))
cam = bpy.context.active_object
cam.name = "RoomCamera"
bpy.context.scene.camera = cam

# Light
bpy.ops.object.light_add(type='SUN', location=(0, 0, 5))
light = bpy.context.active_object
light.name = "RoomLight"
light.data.energy = 2.0

# Render Settings
bpy.context.scene.render.engine = 'CYCLES'
bpy.context.scene.cycles.samples = 16 # Fast render
bpy.context.scene.render.resolution_percentage = 50

# Save Room
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/room_scene.blend")
PYEOF

su - ga -c "/opt/blender/blender --background --python /tmp/create_room.py" > /dev/null 2>&1

# ================================================================
# 3. LAUNCH BLENDER
# ================================================================
echo "Launching Blender..."
if ! pgrep -x "blender" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender /home/ga/BlenderProjects/room_scene.blend &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Blender"; then
            break
        fi
        sleep 1
    done
fi

# Maximize
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="