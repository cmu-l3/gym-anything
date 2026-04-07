#!/bin/bash
echo "=== Setting up procedural_terrain_scatter task ==="

# Source utilities
source /workspace/scripts/task_utils.sh
setup_houdini_env

# ================================================================
# DOWNLOAD HDRI
# ================================================================
HDRI_PATH="/home/ga/HoudiniProjects/data/meadow_1k.hdr"
if [ ! -f "$HDRI_PATH" ]; then
    echo "Downloading meadow HDRI from Poly Haven..."
    wget -q --timeout=60 "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/meadow_at_night_1k.hdr" -O "$HDRI_PATH" 2>/dev/null || \
        echo "WARNING: Could not download meadow HDRI"
    chown ga:ga "$HDRI_PATH" 2>/dev/null || true
fi

# Also ensure the venice HDRI is available as a fallback
VENICE_HDRI="/home/ga/HoudiniProjects/data/venice_sunset_1k.hdr"
if [ ! -f "$VENICE_HDRI" ]; then
    echo "Downloading Venice HDRI as fallback..."
    wget -q --timeout=60 "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/venice_sunset_1k.hdr" -O "$VENICE_HDRI" 2>/dev/null || \
        echo "WARNING: Could not download Venice HDRI"
    chown ga:ga "$VENICE_HDRI" 2>/dev/null || true
fi

# ================================================================
# VERIFY ROCK SOURCE (teapot.obj as rock scatter source)
# ================================================================
ROCK_SOURCE="/home/ga/HoudiniProjects/data/teapot.obj"
if [ ! -f "$ROCK_SOURCE" ]; then
    echo "WARNING: teapot.obj not found at $ROCK_SOURCE"
    echo "Agent will need to create rock geometry procedurally."
fi

# ================================================================
# CREATE OUTPUT DIRECTORIES AND CLEAN STALE FILES
# ================================================================
OUTPUT_SCENE="/home/ga/HoudiniProjects/terrain_environment.hipnc"
RENDER_PATH="/home/ga/HoudiniProjects/renders/terrain_render.png"

mkdir -p "$(dirname "$RENDER_PATH")"
rm -f "$OUTPUT_SCENE" "$RENDER_PATH"
rm -f /tmp/task_result.json

chown -R ga:ga /home/ga/HoudiniProjects/

# ================================================================
# RECORD INITIAL STATE
# ================================================================
cat > /tmp/initial_state.json << EOF
{
    "output_scene": "$OUTPUT_SCENE",
    "render_path": "$RENDER_PATH",
    "hdri_path": "$HDRI_PATH",
    "rock_source": "$ROCK_SOURCE",
    "rock_source_exists": $([ -f "$ROCK_SOURCE" ] && echo "true" || echo "false"),
    "hdri_exists": $([ -f "$HDRI_PATH" ] && echo "true" || echo "false"),
    "scene_type": "empty",
    "difficulty": "very_hard",
    "note": "No pre-built scene. Agent must build everything from scratch.",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state:"
cat /tmp/initial_state.json

# ================================================================
# LAUNCH HOUDINI WITH EMPTY SCENE
# ================================================================
kill_houdini

# Launch Houdini with no scene file (empty scene - agent builds from scratch)
launch_houdini
wait_for_houdini_window 60

# Focus and maximize
sleep 2
focus_houdini
sleep 1
maximize_houdini
sleep 1

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Build procedural terrain with erosion, scatter rocks, add HDRI lighting, render to $RENDER_PATH, save as $OUTPUT_SCENE"
echo "Difficulty: very_hard - No pre-built scene provided. Agent must build everything from scratch."
