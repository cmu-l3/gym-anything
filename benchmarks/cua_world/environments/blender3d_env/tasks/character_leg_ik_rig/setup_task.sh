#!/bin/bash
set -e
echo "=== Setting up Character Leg IK Rig task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Directories
PROJECTS_DIR="/home/ga/BlenderProjects"
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

STARTER_FILE="$PROJECTS_DIR/leg_rig_starter.blend"
OUTPUT_FILE="$PROJECTS_DIR/leg_rig_completed.blend"

# Remove any previous output
rm -f "$OUTPUT_FILE"

# ==============================================================================
# GENERATE STARTER BLEND FILE
# We use Python to programmatically create a clean armature with proper bone rolls
# ==============================================================================
echo "Generating starter rig file..."

cat > /tmp/gen_rig.py << 'PYEOF'
import bpy
import math

# Clear existing objects
bpy.ops.wm.read_homefile(use_empty=True)

# Create Armature
bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
arm_obj = bpy.context.active_object
arm_obj.name = "LegRig"
arm = arm_obj.data
arm.name = "LegRigData"

# We are in Edit Mode. The default bone is 'Bone'. Rename and position it.
# Bone layout: Left Leg
# Thigh: Hip to Knee
# Shin: Knee to Ankle
# Foot: Ankle to Toe

# Remove default bone
bpy.ops.armature.select_all(action='SELECT')
bpy.ops.armature.delete()

# Helper to create bone
def create_bone(name, head, tail, parent=None, roll=0):
    bone = arm.edit_bones.new(name)
    bone.head = head
    bone.tail = tail
    bone.roll = roll
    if parent:
        bone.parent = parent
        bone.use_connect = True
    return bone

# 1. Thigh.L (Hip -> Knee)
# Hip at 1m high, Knee at 0.5m high. Offset slightly in X for "Left" side.
thigh = create_bone("Thigh.L", (0.2, 0.1, 1.0), (0.2, 0.1, 0.5))

# 2. Shin.L (Knee -> Ankle)
# Slight bend forward in Y to help IK direction, but we rely on Pole Target.
# Keeping it straight vertical to force user to set Pole Angle correctly?
# Actually, slight pre-bend is standard practice. Let's make knee slightly forward.
thigh.tail = (0.2, 0.05, 0.5) # Knee slightly forward
shin = create_bone("Shin.L", (0.2, 0.05, 0.5), (0.2, 0.1, 0.1), parent=thigh)

# 3. Foot.L (Ankle -> Toe)
foot = create_bone("Foot.L", (0.2, 0.1, 0.1), (0.2, -0.15, 0.0), parent=shin)

# 4. Foot_IK.L (Control Bone)
# Should be at the ankle/heel. No parent (root level control).
ik_ctrl = create_bone("Foot_IK.L", (0.2, 0.1, 0.1), (0.2, 0.1, 0.0))
ik_ctrl.use_connect = False

# 5. Knee_Target.L (Pole Vector)
# Placed in front of the knee.
pole = create_bone("Knee_Target.L", (0.2, -0.5, 0.5), (0.2, -0.6, 0.5))
pole.use_connect = False

# Switch to Pose Mode to set custom shapes (optional, skipping for simplicity)
bpy.ops.object.mode_set(mode='OBJECT')

# Add a ground plane for visual context
bpy.ops.mesh.primitive_plane_add(size=2, location=(0,0,0))
plane = bpy.context.active_object
plane.name = "Ground"

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/leg_rig_starter.blend")
print("Rig generated successfully.")
PYEOF

# Run generation script
su - ga -c "/opt/blender/blender --background --python /tmp/gen_rig.py"

# ==============================================================================
# LAUNCH BLENDER
# ==============================================================================
echo "Launching Blender with starter file..."
if ! pgrep -x "blender" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$STARTER_FILE' &"
    sleep 5
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="