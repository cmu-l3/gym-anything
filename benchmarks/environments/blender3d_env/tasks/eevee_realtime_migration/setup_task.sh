#!/bin/bash
set -e
echo "=== Setting up EEVEE Real-Time Migration task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

PROJECTS_DIR="/home/ga/BlenderProjects"
DEMOS_DIR="/home/ga/BlenderDemos"
TASK_BLEND="$PROJECTS_DIR/bmw_cycles.blend"

# Ensure directories exist
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Clean any previous task artifacts
rm -f "$PROJECTS_DIR/eevee_render.png"
rm -f "$PROJECTS_DIR/eevee_scene.blend"
rm -f /tmp/task_result.json

# Ensure source BMW scene exists (download if missing)
if [ ! -f "$DEMOS_DIR/BMW27.blend" ]; then
    echo "BMW27.blend not found, downloading..."
    mkdir -p "$DEMOS_DIR"
    wget -q "https://download.blender.org/demo/test/BMW27.blend.zip" -O /tmp/BMW27.zip
    unzip -q -o /tmp/BMW27.zip -d "$DEMOS_DIR"
    # Handle if unzip creates a subdir
    if [ -f "$DEMOS_DIR/BMW27/BMW27.blend" ]; then
        mv "$DEMOS_DIR/BMW27/BMW27.blend" "$DEMOS_DIR/"
    fi
    rm -f /tmp/BMW27.zip
    chown -R ga:ga "$DEMOS_DIR"
fi

# Create the task scene: Copy BMW and force it to Cycles/Defaults
# We use Blender python to programmatically set the initial bad state
cat > /tmp/setup_cycles_scene.py << 'SETUP_EOF'
import bpy
import json
import os

# Open the source BMW scene
source_path = "/home/ga/BlenderDemos/BMW27.blend"
if not os.path.exists(source_path):
    print(f"Error: Source file {source_path} not found")
    # Fallback to create a dummy file if source missing (should not happen in correct env)
    bpy.ops.wm.read_homefile(use_empty=True)
else:
    bpy.ops.wm.open_mainfile(filepath=source_path)

scene = bpy.context.scene

# 1. Force Cycles Engine
scene.render.engine = 'CYCLES'
scene.cycles.samples = 128
scene.cycles.use_denoising = True

# 2. Reset EEVEE settings to "bad" defaults (so agent must change them)
# Note: Property names differ slightly between Blender versions, trying to be robust
try:
    scene.eevee.taa_render_samples = 16
    scene.eevee.taa_samples = 16
    scene.eevee.use_gtao = False       # Disable Ambient Occlusion
    scene.eevee.gtao_distance = 0.2
    scene.eevee.use_raytracing = False # Disable Ray Tracing
    scene.eevee.use_ssr = False        # Disable SSR (older versions)
except:
    pass

# 3. Set non-standard resolution
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.render.resolution_percentage = 50

# 4. Clear output path
scene.render.filepath = "/tmp/render_output"

# Save as the task blend file
output_path = "/home/ga/BlenderProjects/bmw_cycles.blend"
bpy.ops.wm.save_as_mainfile(filepath=output_path)
print(f"Task scene saved to {output_path}")
SETUP_EOF

# Run the setup script headlessly
echo "Generating task file..."
su - ga -c "DISPLAY=:1 /opt/blender/blender --background --python /tmp/setup_cycles_scene.py" > /tmp/setup_log.txt 2>&1

# Kill any existing Blender instances
pkill -f blender 2>/dev/null || true
sleep 1

# Launch Blender with the prepared task scene
echo "Launching Blender..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$TASK_BLEND' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "blender"; then
        echo "Blender window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "Blender" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Blender" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="