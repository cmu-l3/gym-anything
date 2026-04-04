#!/bin/bash
set -e
echo "=== Setting up VSE Rough Cut Assembly task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

PROJECTS_DIR="/home/ga/BlenderProjects"
FOOTAGE_DIR="$PROJECTS_DIR/footage"
mkdir -p "$FOOTAGE_DIR"
chown -R ga:ga "$PROJECTS_DIR"

# Clean up any previous task artifacts
rm -f "$PROJECTS_DIR/video_edit.blend"
rm -f "$PROJECTS_DIR/final_edit.mp4"
rm -f /tmp/task_result.json

# ================================================================
# CREATE SOURCE VIDEO CLIPS USING FFMPEG
# ================================================================
echo "Creating source video clips..."

# Helper function to generate test clips
generate_clip() {
    local filename=$1
    local color_hex=$2
    local text_label=$3
    local text_sub=$4
    
    # 2 seconds (48 frames) at 24fps, 960x540
    ffmpeg -y -f lavfi -i "color=c=${color_hex}:size=960x540:d=2:rate=24" \
      -vf "drawtext=text='${text_label}':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2-30,
           drawtext=text='${text_sub}':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2+40,
           drawtext=text='%{frame_num}':fontcolor=white:fontsize=18:x=20:y=h-30" \
      -c:v libx264 -preset fast -crf 23 -pix_fmt yuv420p -frames:v 48 \
      "$FOOTAGE_DIR/$filename" 2>/dev/null
}

# Clip A: Blue-tinted exterior shot
generate_clip "clip_A.mp4" "#1a3a5c" "Exterior Shot" "Clip A" || echo "Failed to create clip A"

# Clip B: Amber-tinted detail shot
generate_clip "clip_B.mp4" "#5c3a1a" "Detail Shot" "Clip B" || echo "Failed to create clip B"

# Clip C: Green-tinted interior shot
generate_clip "clip_C.mp4" "#1a5c2a" "Interior Shot" "Clip C" || echo "Failed to create clip C"

# Set ownership
chown -R ga:ga "$FOOTAGE_DIR"

# Verify clips were created
echo "Verifying source clips..."
for clip in clip_A.mp4 clip_B.mp4 clip_C.mp4; do
    if [ -f "$FOOTAGE_DIR/$clip" ]; then
        echo "  $clip: Created successfully"
    else
        echo "  WARNING: $clip was not created!"
    fi
done

# ================================================================
# LAUNCH BLENDER IN VIDEO EDITING WORKSPACE
# ================================================================
echo "Launching Blender in Video Editing workspace..."

# Create a Python script to set up Blender in Video Editing workspace
cat > /tmp/setup_vse_workspace.py << 'PYEOF'
import bpy
import sys

# Start with a fresh file
bpy.ops.wm.read_homefile(use_empty=False)

# Set render settings to match source footage
scene = bpy.context.scene
scene.render.resolution_x = 960
scene.render.resolution_y = 540
scene.render.resolution_percentage = 100
scene.render.fps = 24
scene.frame_start = 1
scene.frame_end = 250

# Try to switch to Video Editing workspace
workspace_found = False
for ws in bpy.data.workspaces:
    if 'video' in ws.name.lower() or 'editing' in ws.name.lower():
        bpy.context.window.workspace = ws
        workspace_found = True
        break

# Save as a temporary startup file
bpy.ops.wm.save_as_mainfile(filepath="/tmp/vse_startup.blend")
PYEOF

# Prepare the startup file
su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/setup_vse_workspace.py" 2>/dev/null || true

# Kill any existing Blender instances
pkill -f blender 2>/dev/null || true
sleep 1

# Launch Blender
su - ga -c "DISPLAY=:1 /opt/blender/blender /tmp/vse_startup.blend &"

# Wait for Blender window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "blender"; then
        echo "Blender window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
sleep 2
maximize_blender
focus_blender

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== VSE Rough Cut Assembly setup complete ==="