#!/bin/bash
echo "=== Setting up procedural_building_hda task ==="

# Source utilities
source /workspace/scripts/task_utils.sh
setup_houdini_env

# ================================================================
# CREATE SPEC DOCUMENT ON DESKTOP
# ================================================================
SPEC_PATH="/home/ga/Desktop/building_hda_spec.txt"
mkdir -p "$(dirname "$SPEC_PATH")"

cat > "$SPEC_PATH" << 'SPECEOF'
PROCEDURAL BUILDING GENERATOR HDA SPECIFICATION
================================================

Create a Houdini Digital Asset (HDA) that procedurally generates a building.

REQUIRED PARAMETERS (must appear on the HDA's parameter interface):
- building_width (float, default 10.0, range 5-50): Width of the building base in meters
- building_height (float, default 30.0, range 10-200): Total height of the building
- num_floors (integer, default 5, range 1-40): Number of floors
- window_density (float, default 0.5, range 0-1): Controls window spacing per floor

GEOMETRY REQUIREMENTS:
- Building must have distinct floor plates (horizontal divisions)
- Each floor must have window cutouts or window geometry
- The building must have a ground floor that is taller than upper floors
- UVs must be generated for the building geometry
- Total polygon count must be between 500 and 50000

PARAMETER BEHAVIOR:
- Changing num_floors must change the number of visible floor divisions
- Changing building_width must change the building footprint
- Changing building_height must change the overall height
- Changing window_density must affect number/spacing of windows

OUTPUT:
- Save the HDA file to: /home/ga/HoudiniProjects/hda/procedural_building.hda
- The HDA operator name should be: procedural_building
- The HDA should be a SOP-level asset (inside Object-level container)

TEST SCENE:
- Create at least 3 instances of the HDA with different parameter values
- Instance 1: width=8, height=20, floors=4, windows=0.3
- Instance 2: width=15, height=50, floors=10, windows=0.7
- Instance 3: width=12, height=35, floors=7, windows=0.5
- Save as: /home/ga/HoudiniProjects/building_test.hipnc
SPECEOF

chown ga:ga "$SPEC_PATH" 2>/dev/null || true
echo "Spec document created at: $SPEC_PATH"

# ================================================================
# CREATE OUTPUT DIRECTORIES AND CLEAN STALE FILES
# ================================================================
HDA_DIR="/home/ga/HoudiniProjects/hda"
HDA_PATH="/home/ga/HoudiniProjects/hda/procedural_building.hda"
OUTPUT_SCENE="/home/ga/HoudiniProjects/building_test.hipnc"

mkdir -p "$HDA_DIR"
rm -f "$HDA_PATH" "$OUTPUT_SCENE"
rm -f /tmp/task_result.json

chown -R ga:ga /home/ga/HoudiniProjects/
chown -R ga:ga "$HDA_DIR"

# ================================================================
# RECORD INITIAL STATE
# ================================================================
cat > /tmp/initial_state.json << EOF
{
    "spec_path": "$SPEC_PATH",
    "expected_hda_path": "$HDA_PATH",
    "expected_output_scene": "$OUTPUT_SCENE",
    "hda_dir": "$HDA_DIR",
    "spec_exists": true,
    "hda_exists": false,
    "scene_exists": false,
    "difficulty": "very_hard",
    "note": "Spec-driven discovery: agent must read spec from Desktop and create HDA from scratch.",
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
echo "Task: Read spec at $SPEC_PATH, create procedural building HDA at $HDA_PATH, test scene at $OUTPUT_SCENE"
echo "Difficulty: very_hard - Specification-driven discovery pattern. Agent must build HDA from scratch."
