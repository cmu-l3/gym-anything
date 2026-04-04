#!/bin/bash
echo "=== Setting up render_basic_scene task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for render time estimation)
date +%s > /tmp/task_start_time

# Record initial state - check if output file exists
OUTPUT_PATH="/home/ga/BlenderProjects/rendered_output.png"
if [ -f "$OUTPUT_PATH" ]; then
    INITIAL_EXISTS="true"
    INITIAL_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    INITIAL_EXISTS="false"
    INITIAL_SIZE="0"
    INITIAL_MTIME="0"
fi

# Save initial state
cat > /tmp/initial_state.json << EOF
{
    "output_exists": $INITIAL_EXISTS,
    "output_size": $INITIAL_SIZE,
    "output_mtime": $INITIAL_MTIME,
    "task_start_time": $(date +%s),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Determine which blend file to use (official demo files preferred)
BLEND_FILE=""
if [ -f "/home/ga/BlenderProjects/render_scene.blend" ]; then
    BLEND_FILE="/home/ga/BlenderProjects/render_scene.blend"
    echo "Using official demo scene: render_scene.blend"
elif [ -f "/home/ga/BlenderDemos/BMW27.blend" ]; then
    BLEND_FILE="/home/ga/BlenderDemos/BMW27.blend"
    echo "Using BMW benchmark scene"
elif [ -f "/home/ga/BlenderProjects/baseline_scene.blend" ]; then
    BLEND_FILE="/home/ga/BlenderProjects/baseline_scene.blend"
    echo "Using baseline scene"
else
    echo "WARNING: No scene file found!"
fi

# Make sure Blender is running with the scene
echo "Checking Blender status..."
if ! pgrep -x "blender" > /dev/null 2>&1; then
    echo "Starting Blender with scene..."
    if [ -n "$BLEND_FILE" ]; then
        su - ga -c "DISPLAY=:1 /opt/blender/blender '$BLEND_FILE' &"
    else
        su - ga -c "DISPLAY=:1 /opt/blender/blender &"
    fi
    sleep 5
else
    echo "Blender is already running"
fi

# Focus and maximize Blender window
focus_blender 2>/dev/null || true
sleep 1
maximize_blender 2>/dev/null || true
sleep 1

# Clear any previous render log
rm -f /tmp/blender_render.log 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Render the scene and save output to $OUTPUT_PATH"
echo "Scene file: $BLEND_FILE"
echo "Instructions:"
echo "  1. Press F12 to render the scene"
echo "  2. In the render window, go to Image > Save As"
echo "  3. Save to: $OUTPUT_PATH"
