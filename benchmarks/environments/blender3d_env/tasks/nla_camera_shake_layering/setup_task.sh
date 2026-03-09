#!/bin/bash
echo "=== Setting up NLA Camera Shake Layering task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Paths
PROJECTS_DIR="/home/ga/BlenderProjects"
SOURCE_BLEND="$PROJECTS_DIR/nla_setup.blend"
OUTPUT_BLEND="$PROJECTS_DIR/nla_camera_composite.blend"

mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Remove output if it exists
rm -f "$OUTPUT_BLEND"

# Record task start time
date +%s > /tmp/task_start_time.txt

# ================================================================
# GENERATE BASELINE FILE WITH ANIMATION ACTIONS
# ================================================================
# We create a file with two specific actions:
# 1. Dolly_Move: Smooth Y translation
# 2. Handheld_Shake: Noise modifier on Rotation
echo "Generating nla_setup.blend with animation data..."

GENERATOR_SCRIPT=$(mktemp /tmp/gen_nla_setup.XXXXXX.py)
cat > "$GENERATOR_SCRIPT" << 'PYEOF'
import bpy
import random

# Clear scene
bpy.ops.wm.read_homefile(use_empty=True)

# Create Camera
bpy.ops.object.camera_add(location=(0, 0, 1.6), rotation=(1.5708, 0, 0))
cam = bpy.context.active_object
cam.name = "Camera"
bpy.context.scene.camera = cam

# --- ACTION 1: DOLLY MOVE (Smooth movement) ---
# Create action
dolly_action = bpy.data.actions.new(name="Dolly_Move")
cam.animation_data_create()
cam.animation_data.action = dolly_action

# Add keyframes to Y location (index 1)
# Frame 1: Y=0
cam.location.y = 0
cam.keyframe_insert(data_path="location", index=1, frame=1)
# Frame 100: Y=10
cam.location.y = 10
cam.keyframe_insert(data_path="location", index=1, frame=100)

# Ensure linear interpolation for dolly
for fcurve in dolly_action.fcurves:
    for kp in fcurve.keyframe_points:
        kp.interpolation = 'LINEAR'

# --- ACTION 2: HANDHELD SHAKE (Noise) ---
# Create action but don't assign it yet (it stays in memory due to fake user or just being in bpy.data)
shake_action = bpy.data.actions.new(name="Handheld_Shake")
shake_action.use_fake_user = True  # Ensure it saves even if not active

# We need to add F-Curves for rotation
# Rotation X (index 0) and Z (index 2)
for index in [0, 2]:
    fc = shake_action.fcurves.new(data_path="rotation_euler", index=index)
    # Add a keyframe at frame 1 to establish the curve
    fc.keyframe_points.insert(frame=1, value=cam.rotation_euler[index])
    
    # Add Noise Modifier
    mod = fc.modifiers.new('NOISE')
    mod.scale = 10.0
    mod.strength = 0.15  # Visible shake
    mod.phase = random.random() * 100

# Reset active action to Dolly_Move so the agent starts with that
cam.animation_data.action = dolly_action

# Set timeline range
bpy.context.scene.frame_start = 1
bpy.context.scene.frame_end = 100

# Save
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/nla_setup.blend")
print("Setup complete.")
PYEOF

# Run generation script
su - ga -c "/opt/blender/blender --background --python '$GENERATOR_SCRIPT'"
rm -f "$GENERATOR_SCRIPT"

# Record initial state info
echo "Initial setup complete. File created at $SOURCE_BLEND"

# ================================================================
# LAUNCH BLENDER
# ================================================================
echo "Launching Blender..."
if ! pgrep -x "blender" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$SOURCE_BLEND' &"
    sleep 5
fi

# Maximize window
focus_blender
sleep 1
maximize_blender

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="