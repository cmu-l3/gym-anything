#!/bin/bash
echo "=== Exporting classroom_material_overhaul result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# ================================================================
# READ INITIAL STATE (recorded by setup_task.sh)
# ================================================================
FLOOR_MAT="unknown"
WALL_MAT="unknown"
DESK_MAT="unknown"
GLASS_MAT="unknown"

if [ -f /tmp/initial_state.json ]; then
    FLOOR_MAT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('floor_material','unknown'))" 2>/dev/null || echo "unknown")
    WALL_MAT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('wall_material','unknown'))" 2>/dev/null || echo "unknown")
    DESK_MAT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('desk_material','unknown'))" 2>/dev/null || echo "unknown")
    GLASS_MAT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('glass_material','unknown'))" 2>/dev/null || echo "unknown")
fi

echo "Target materials:"
echo "  Floor: $FLOOR_MAT"
echo "  Wall:  $WALL_MAT"
echo "  Desk:  $DESK_MAT"
echo "  Glass: $GLASS_MAT"

# ================================================================
# CHECK OUTPUT FILE
# ================================================================
OUTPUT_BLEND="/home/ga/BlenderProjects/classroom_fixed.blend"

OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
IS_VALID_BLEND="false"
FILE_CREATED="false"

if [ -f "$OUTPUT_BLEND" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_BLEND" 2>/dev/null || echo "0")

    # Check magic bytes
    MAGIC=$(head -c 7 "$OUTPUT_BLEND" 2>/dev/null | tr -d '\0')
    if [ "$MAGIC" = "BLENDER" ]; then
        IS_VALID_BLEND="true"
    fi

    FILE_CREATED="true"
    echo "Output file found: $OUTPUT_BLEND ($OUTPUT_SIZE bytes, valid=$IS_VALID_BLEND)"
else
    echo "WARNING: Output file NOT found at $OUTPUT_BLEND"
fi

# ================================================================
# ANALYZE MATERIALS IN THE SAVED FILE VIA BLENDER PYTHON
# ================================================================
# Clean up any previous analysis
rm -f /tmp/materials_analysis.json 2>/dev/null

if [ "$IS_VALID_BLEND" = "true" ]; then
    echo "Analyzing materials in saved blend file..."

    # Write analysis script — note: uses 'PYEOF' (quoted) so no shell expansion
    cat > /tmp/analyze_materials.py << 'PYEOF'
import bpy
import json

# Open the saved blend file
bpy.ops.wm.open_mainfile(filepath="OUTPUT_BLEND_PLACEHOLDER")

# Material names to check — read from initial_state.json
target_names = {}
try:
    with open("/tmp/initial_state.json", "r") as f:
        state = json.load(f)
        target_names = state.get("matched_materials", {})
except Exception as e:
    print(f"Warning: Could not read initial_state.json: {e}")

def get_principled_bsdf(mat):
    """Find the Principled BSDF node in a material's node tree."""
    if not mat.use_nodes or not mat.node_tree:
        return None
    for node in mat.node_tree.nodes:
        if node.type == 'BSDF_PRINCIPLED':
            return node
    return None

def analyze_material(mat):
    """Extract key properties from a material for verification."""
    props = {
        "name": mat.name,
        "use_nodes": mat.use_nodes,
        "base_color": [0.5, 0.5, 0.5, 1.0],
        "roughness": 0.5,
        "metallic": 0.0,
        "transmission": 0.0,
        "ior": 1.45,
        "specular": 0.5,
        "base_color_linked": False,
        "has_texture": False,
        "node_count": 0
    }

    if not mat.use_nodes or not mat.node_tree:
        return props

    props["node_count"] = len(mat.node_tree.nodes)

    bsdf = get_principled_bsdf(mat)
    if bsdf is None:
        props["no_principled_bsdf"] = True
        return props

    # Base Color
    bc_input = bsdf.inputs.get("Base Color")
    if bc_input:
        props["base_color"] = list(bc_input.default_value)
        props["base_color_linked"] = bc_input.is_linked
        if bc_input.is_linked:
            props["has_texture"] = True
            for link in bc_input.links:
                from_node = link.from_node
                props["base_color_source_type"] = from_node.type
                props["base_color_source_name"] = from_node.name

    # Roughness
    rough_input = bsdf.inputs.get("Roughness")
    if rough_input:
        props["roughness"] = rough_input.default_value
        props["roughness_linked"] = rough_input.is_linked

    # Metallic
    metal_input = bsdf.inputs.get("Metallic")
    if metal_input:
        props["metallic"] = metal_input.default_value
        props["metallic_linked"] = metal_input.is_linked

    # Transmission — Blender 4.x uses "Transmission Weight"
    trans_input = bsdf.inputs.get("Transmission Weight") or bsdf.inputs.get("Transmission")
    if trans_input:
        props["transmission"] = trans_input.default_value
        props["transmission_linked"] = trans_input.is_linked

    # IOR
    ior_input = bsdf.inputs.get("IOR")
    if ior_input:
        props["ior"] = ior_input.default_value

    # Specular
    spec_input = bsdf.inputs.get("Specular IOR Level") or bsdf.inputs.get("Specular")
    if spec_input:
        props["specular"] = spec_input.default_value

    return props

# Analyze each target material
results = {}
for cat, mat_name in target_names.items():
    mat = bpy.data.materials.get(mat_name)
    if mat:
        results[cat] = analyze_material(mat)
        print(f"Analyzed {cat} ({mat_name}): base_color={results[cat]['base_color'][:3]}, "
              f"roughness={results[cat]['roughness']:.3f}, "
              f"transmission={results[cat]['transmission']:.3f}, "
              f"linked={results[cat]['base_color_linked']}")
    else:
        results[cat] = {"name": mat_name, "error": "Material not found in saved file"}
        print(f"WARNING: Material '{mat_name}' not found for category '{cat}'")

# Count how many materials changed from grey
grey_bc = [0.5, 0.5, 0.5, 1.0]
changed_count = 0
for cat, props in results.items():
    bc = props.get("base_color", grey_bc)
    trans = props.get("transmission", 0.0)
    is_linked = props.get("base_color_linked", False)
    bc_diff = any(abs(bc[i] - grey_bc[i]) > 0.05 for i in range(3))
    if bc_diff or is_linked or trans > 0.1:
        changed_count += 1

results["_summary"] = {
    "materials_changed": changed_count,
    "total_targets": len(target_names)
}

# Write results to file so the shell script can read them
with open("/tmp/materials_analysis.json", "w") as f:
    json.dump(results, f, indent=2, default=str)

print("Materials analysis written to /tmp/materials_analysis.json")
PYEOF

    # Replace placeholder with actual path
    sed -i "s|OUTPUT_BLEND_PLACEHOLDER|$OUTPUT_BLEND|g" /tmp/analyze_materials.py

    ANALYSIS_OUTPUT=$(/opt/blender/blender --background --python /tmp/analyze_materials.py 2>&1)
    echo "$ANALYSIS_OUTPUT" | tail -20
fi

# ================================================================
# CHECK BLENDER STATE
# ================================================================
BLENDER_RUNNING="false"
BLENDER_WINDOW_TITLE=""

if pgrep -x "blender" > /dev/null 2>&1; then
    BLENDER_RUNNING="true"
fi

BLENDER_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "blender" || echo "")
if [ -n "$BLENDER_WINDOWS" ]; then
    BLENDER_WINDOW_TITLE=$(echo "$BLENDER_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# ================================================================
# BUILD RESULT JSON (using Python for safe serialization)
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 - "$OUTPUT_EXISTS" "$OUTPUT_SIZE" "$OUTPUT_BLEND" "$IS_VALID_BLEND" \
          "$FILE_CREATED" "$FLOOR_MAT" "$WALL_MAT" "$DESK_MAT" "$GLASS_MAT" \
          "$BLENDER_RUNNING" "$BLENDER_WINDOW_TITLE" << 'PYEOF' > "$TEMP_JSON"
import json
import sys
from datetime import datetime

args = sys.argv[1:]

# Read materials analysis from file
materials = {}
try:
    with open("/tmp/materials_analysis.json", "r") as f:
        materials = json.load(f)
except Exception:
    pass

# Read matched materials from initial state
matched = {}
try:
    with open("/tmp/initial_state.json", "r") as f:
        state = json.load(f)
        matched = state.get("matched_materials", {})
except Exception:
    pass

result = {
    "output_exists": args[0] == "true",
    "output_size_bytes": int(args[1]),
    "output_path": args[2],
    "is_valid_blend": args[3] == "true",
    "file_created": args[4] == "true",
    "matched_materials": matched,
    "floor_material": args[5],
    "wall_material": args[6],
    "desk_material": args[7],
    "glass_material": args[8],
    "materials": materials,
    "blender_was_running": args[9] == "true",
    "blender_window_title": args[10],
    "screenshot_path": "/tmp/task_end.png",
    "initial_screenshot_path": "/tmp/task_start.png",
    "timestamp": datetime.now().isoformat()
}

print(json.dumps(result, indent=2, default=str))
PYEOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
