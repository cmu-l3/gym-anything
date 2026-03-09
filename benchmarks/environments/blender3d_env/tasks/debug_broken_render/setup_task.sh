#!/bin/bash
echo "=== Setting up debug_broken_render task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# ================================================================
# CONFIGURATION
# ================================================================
SOURCE_BLEND="/home/ga/BlenderProjects/baseline_scene.blend"
BROKEN_BLEND="/home/ga/BlenderProjects/broken_scene.blend"
EXPECTED_BLEND="/home/ga/BlenderProjects/fixed_scene.blend"
EXPECTED_RENDER="/home/ga/BlenderProjects/fixed_render.png"
PROJECTS_DIR="/home/ga/BlenderProjects"

# Record task start time
date +%s > /tmp/task_start_time

# Ensure projects directory exists
mkdir -p "$PROJECTS_DIR"
chown ga:ga "$PROJECTS_DIR"

# Remove any existing output files to ensure clean state
rm -f "$EXPECTED_BLEND" 2>/dev/null || true
rm -f "$EXPECTED_RENDER" 2>/dev/null || true
rm -f "$BROKEN_BLEND" 2>/dev/null || true

# ================================================================
# PLANT 5 BUGS USING BLENDER PYTHON (HEADLESS)
# ================================================================
echo "Planting 5 bugs in baseline scene..."

BREAK_SCRIPT=$(mktemp /tmp/break_scene.XXXXXX.py)
cat > "$BREAK_SCRIPT" << 'PYEOF'
import bpy
import json
import math
import mathutils

# Open the baseline scene
bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/baseline_scene.blend")

scene = bpy.context.scene
bugs_applied = []

# ================================================================
# BUG 1: Camera — remove Track To constraint, rotate to face away
# ================================================================
camera = bpy.data.objects.get('MainCamera')
if camera is None:
    # Try to find any camera
    for obj in bpy.data.objects:
        if obj.type == 'CAMERA':
            camera = obj
            break

if camera:
    # Record original state
    original_camera_rotation = list(camera.rotation_euler)
    original_constraints = [c.type for c in camera.constraints]

    # Remove all constraints (especially Track To)
    for constraint in list(camera.constraints):
        camera.constraints.remove(constraint)

    # Rotate camera to face completely away from the scene
    # The scene is roughly at the origin; point camera toward +Y away from it
    camera.rotation_euler = (0.0, 0.0, math.pi)  # Face away (180 degrees around Z)

    bugs_applied.append({
        "bug": "camera_facing_away",
        "description": "Track To constraint removed, camera rotated to face empty space",
        "original_rotation": [round(v, 4) for v in original_camera_rotation],
        "broken_rotation": [0.0, 0.0, round(math.pi, 4)],
        "constraints_removed": original_constraints
    })
else:
    bugs_applied.append({"bug": "camera_facing_away", "error": "No camera found"})

# ================================================================
# BUG 2: Light — set sun energy to 0.0
# ================================================================
sun_light = bpy.data.objects.get('SunLight')
if sun_light is None:
    # Try to find any light
    for obj in bpy.data.objects:
        if obj.type == 'LIGHT':
            sun_light = obj
            break

if sun_light and sun_light.data:
    original_energy = sun_light.data.energy
    sun_light.data.energy = 0.0

    bugs_applied.append({
        "bug": "light_energy_zero",
        "description": "Sun light energy set to 0.0 (completely dark)",
        "light_name": sun_light.name,
        "original_energy": original_energy,
        "broken_energy": 0.0
    })
else:
    bugs_applied.append({"bug": "light_energy_zero", "error": "No light found"})

# ================================================================
# BUG 3: Resolution — set to 10x10
# ================================================================
original_res_x = scene.render.resolution_x
original_res_y = scene.render.resolution_y
original_res_pct = scene.render.resolution_percentage

scene.render.resolution_x = 10
scene.render.resolution_y = 10
scene.render.resolution_percentage = 100

bugs_applied.append({
    "bug": "resolution_tiny",
    "description": "Render resolution set to 10x10 pixels",
    "original_resolution": [original_res_x, original_res_y],
    "original_percentage": original_res_pct,
    "broken_resolution": [10, 10],
    "broken_percentage": 100
})

# ================================================================
# BUG 4: Samples — set Cycles samples to 1
# ================================================================
original_samples = 32  # default
if scene.render.engine == 'CYCLES':
    original_samples = scene.cycles.samples
    scene.cycles.samples = 1
    bugs_applied.append({
        "bug": "samples_minimal",
        "description": "Cycles render samples set to 1 (extremely noisy)",
        "original_samples": original_samples,
        "broken_samples": 1
    })
else:
    # Force Cycles engine and set low samples
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 1
    bugs_applied.append({
        "bug": "samples_minimal",
        "description": "Engine set to CYCLES, samples set to 1",
        "original_engine": scene.render.engine,
        "broken_samples": 1
    })

# ================================================================
# BUG 5: Visibility — hide BaseCube from render
# ================================================================
base_cube = bpy.data.objects.get('BaseCube')
if base_cube is None:
    # Try to find a mesh object that could be the main subject
    for obj in bpy.data.objects:
        if obj.type == 'MESH' and 'cube' in obj.name.lower():
            base_cube = obj
            break

if base_cube:
    original_hide_render = base_cube.hide_render
    base_cube.hide_render = True

    bugs_applied.append({
        "bug": "object_hidden_in_render",
        "description": "BaseCube hide_render set to True (invisible in renders)",
        "object_name": base_cube.name,
        "original_hide_render": original_hide_render,
        "broken_hide_render": True
    })
else:
    bugs_applied.append({"bug": "object_hidden_in_render", "error": "No BaseCube found"})

# ================================================================
# RECORD FULL INITIAL (BROKEN) STATE
# ================================================================
objects_list = []
for obj in bpy.data.objects:
    obj_info = {
        "name": obj.name,
        "type": obj.type,
        "location": [round(v, 3) for v in obj.location],
        "hide_render": obj.hide_render,
        "hide_viewport": obj.hide_viewport
    }
    if obj.type == 'CAMERA':
        obj_info["rotation_euler"] = [round(v, 4) for v in obj.rotation_euler]
        obj_info["constraints"] = [c.type for c in obj.constraints]
    if obj.type == 'LIGHT' and obj.data:
        obj_info["light_type"] = obj.data.type
        obj_info["energy"] = obj.data.energy
    objects_list.append(obj_info)

initial_state = {
    "bugs_planted": len(bugs_applied),
    "bugs": bugs_applied,
    "render_engine": scene.render.engine,
    "resolution_x": scene.render.resolution_x,
    "resolution_y": scene.render.resolution_y,
    "resolution_percentage": scene.render.resolution_percentage,
    "cycles_samples": scene.cycles.samples if scene.render.engine == 'CYCLES' else 0,
    "object_count": len(bpy.data.objects),
    "objects": objects_list
}

# Save the broken scene
bpy.ops.wm.save_as_mainfile(filepath="/home/ga/BlenderProjects/broken_scene.blend")

# Output initial state as JSON
print("INITIAL_STATE_JSON:" + json.dumps(initial_state))
PYEOF

# Run the break script headlessly
BREAK_OUTPUT=$(/opt/blender/blender --background --python "$BREAK_SCRIPT" 2>/dev/null)
INITIAL_STATE_LINE=$(echo "$BREAK_OUTPUT" | grep '^INITIAL_STATE_JSON:' | head -1)

if [ -n "$INITIAL_STATE_LINE" ]; then
    INITIAL_STATE="${INITIAL_STATE_LINE#INITIAL_STATE_JSON:}"
else
    echo "WARNING: Could not extract initial state from Blender output"
    INITIAL_STATE='{"bugs_planted": 5, "bugs": [], "objects": []}'
fi

rm -f "$BREAK_SCRIPT"

# ================================================================
# SAVE INITIAL STATE
# ================================================================
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(date +%s),
    "timestamp": "$(date -Iseconds)",
    "source_blend": "$SOURCE_BLEND",
    "broken_blend": "$BROKEN_BLEND",
    "expected_blend": "$EXPECTED_BLEND",
    "expected_render": "$EXPECTED_RENDER",
    "blend_output_exists": false,
    "render_output_exists": false,
    "initial_scene": $INITIAL_STATE
}
EOF

chmod 666 /tmp/initial_state.json 2>/dev/null || true

echo "Initial state recorded:"
cat /tmp/initial_state.json

# ================================================================
# KILL EXISTING BLENDER AND LAUNCH WITH BROKEN SCENE
# ================================================================
echo "Stopping any existing Blender instances..."
pkill -9 -x blender 2>/dev/null || true
sleep 2

echo "Launching Blender with broken scene (5 bugs planted)..."
if [ -f "$BROKEN_BLEND" ]; then
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$BROKEN_BLEND' &"
else
    echo "ERROR: Broken blend file not created! Using source..."
    su - ga -c "DISPLAY=:1 /opt/blender/blender '$SOURCE_BLEND' &"
fi
sleep 5

# Focus and maximize Blender window
focus_blender 2>/dev/null || true
sleep 1
maximize_blender 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Scene: broken_scene.blend loaded with 5 intentional bugs:"
echo "  Bug 1: Camera rotated to face away from scene (constraint removed)"
echo "  Bug 2: Sun light energy = 0.0 (completely dark)"
echo "  Bug 3: Render resolution = 10x10 pixels"
echo "  Bug 4: Cycles samples = 1 (extremely noisy)"
echo "  Bug 5: BaseCube hide_render = True (invisible in render)"
echo "Expected blend output: $EXPECTED_BLEND"
echo "Expected render output: $EXPECTED_RENDER"
