#!/bin/bash
echo "=== Setting up classroom_material_overhaul task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# ================================================================
# PATHS
# ================================================================
SOURCE_BLEND="/home/ga/BlenderDemos/classroom/classroom.blend"
BROKEN_BLEND="/home/ga/BlenderProjects/classroom_broken.blend"
OUTPUT_BLEND="/home/ga/BlenderProjects/classroom_fixed.blend"

# Remove any existing output files to ensure clean state
rm -f "$OUTPUT_BLEND" 2>/dev/null || true
rm -f "$BROKEN_BLEND" 2>/dev/null || true

# Verify source file exists
if [ ! -f "$SOURCE_BLEND" ]; then
    echo "ERROR: Classroom demo scene not found at $SOURCE_BLEND"
    echo "Checking alternate locations..."
    # Try alternate locations
    if [ -f "/home/ga/BlenderDemos/classroom.blend" ]; then
        SOURCE_BLEND="/home/ga/BlenderDemos/classroom.blend"
        echo "Found at $SOURCE_BLEND"
    else
        echo "FATAL: Cannot find classroom.blend anywhere"
        exit 1
    fi
fi

echo "Source blend: $SOURCE_BLEND"

# ================================================================
# FIND MATERIALS, RECORD ORIGINALS, BREAK THEM, SAVE BROKEN FILE
# ================================================================
# This Python script runs inside Blender headlessly.
# It:
#   1. Opens the classroom scene
#   2. Searches all materials for floor/wall/desk/glass keywords
#   3. Records original properties to /tmp/original_materials.json
#   4. Resets those 4 materials to flat grey
#   5. Saves as classroom_broken.blend
#   6. Outputs the matched material names for initial_state.json

cat > /tmp/break_materials.py << 'PYEOF'
import bpy
import json
import re
import sys

# Open the classroom blend file
bpy.ops.wm.open_mainfile(filepath="SOURCE_BLEND_PLACEHOLDER")

# ----------------------------------------------------------------
# Material keyword matching — order matters: first match wins
# ----------------------------------------------------------------
CATEGORIES = {
    "floor": ["floor", "wood_floor", "parquet", "flooring", "planks"],
    "wall":  ["wall", "paint", "plaster", "drywall", "stucco"],
    "desk":  ["desk", "table", "furniture", "wood_desk", "wood_table"],
    "glass": ["glass", "window", "transparent", "pane", "glazing"],
}

matched = {}  # category -> material name
originals = {}  # category -> original properties dict

all_materials = list(bpy.data.materials)
print(f"Total materials in scene: {len(all_materials)}")
for mat in all_materials:
    print(f"  - {mat.name}")

# First pass: exact substring match (case-insensitive)
for cat, keywords in CATEGORIES.items():
    if cat in matched:
        continue
    for mat in all_materials:
        name_lower = mat.name.lower()
        for kw in keywords:
            if kw in name_lower:
                matched[cat] = mat.name
                break
        if cat in matched:
            break

# Report what we found
print(f"\nMatched materials: {json.dumps(matched, indent=2)}")

if len(matched) < 4:
    missing = [c for c in CATEGORIES if c not in matched]
    print(f"WARNING: Could not find materials for: {missing}")
    # Fallback: try broader matching or just pick remaining materials
    used_names = set(matched.values())
    remaining_mats = [m for m in all_materials if m.name not in used_names and m.use_nodes]
    for cat in missing:
        if remaining_mats:
            fallback = remaining_mats.pop(0)
            matched[cat] = fallback.name
            print(f"  Fallback for '{cat}': {fallback.name}")

# ----------------------------------------------------------------
# Record original properties and reset to grey
# ----------------------------------------------------------------
def get_principled_bsdf(mat):
    """Find the Principled BSDF node in a material's node tree."""
    if not mat.use_nodes or not mat.node_tree:
        return None
    for node in mat.node_tree.nodes:
        if node.type == 'BSDF_PRINCIPLED':
            return node
    return None

def get_material_props(mat):
    """Extract key properties from a material."""
    props = {
        "name": mat.name,
        "use_nodes": mat.use_nodes,
    }
    bsdf = get_principled_bsdf(mat)
    if bsdf:
        # Base Color — could be a direct value or connected to a texture
        bc_input = bsdf.inputs.get("Base Color")
        if bc_input:
            props["base_color"] = list(bc_input.default_value)
            props["base_color_linked"] = bc_input.is_linked

        rough_input = bsdf.inputs.get("Roughness")
        if rough_input:
            props["roughness"] = rough_input.default_value
            props["roughness_linked"] = rough_input.is_linked

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
    else:
        props["no_principled_bsdf"] = True

    return props

def reset_to_grey(mat):
    """Reset a material to flat grey: clear node tree, add fresh Principled BSDF."""
    mat.use_nodes = True
    tree = mat.node_tree

    # Remove ALL existing nodes (textures, mix shaders, etc.)
    for node in list(tree.nodes):
        tree.nodes.remove(node)

    # Remove ALL links
    for link in list(tree.links):
        tree.links.remove(link)

    # Add fresh output + Principled BSDF
    output_node = tree.nodes.new('ShaderNodeOutputMaterial')
    output_node.location = (300, 0)

    bsdf_node = tree.nodes.new('ShaderNodeBsdfPrincipled')
    bsdf_node.location = (0, 0)

    # Set to flat grey
    bsdf_node.inputs["Base Color"].default_value = (0.5, 0.5, 0.5, 1.0)
    bsdf_node.inputs["Roughness"].default_value = 0.5
    bsdf_node.inputs["Metallic"].default_value = 0.0

    # Reset transmission
    trans_input = bsdf_node.inputs.get("Transmission Weight") or bsdf_node.inputs.get("Transmission")
    if trans_input:
        trans_input.default_value = 0.0

    # Connect BSDF to output
    tree.links.new(bsdf_node.outputs["BSDF"], output_node.inputs["Surface"])

# Process each matched material
for cat, mat_name in matched.items():
    mat = bpy.data.materials.get(mat_name)
    if mat is None:
        print(f"ERROR: Material '{mat_name}' not found (category: {cat})")
        continue

    # Record original properties
    originals[cat] = get_material_props(mat)
    print(f"\nOriginal '{cat}' ({mat_name}):")
    print(f"  {json.dumps(originals[cat], indent=4, default=str)}")

    # Reset to grey
    reset_to_grey(mat)
    print(f"  -> Reset to flat grey")

# ----------------------------------------------------------------
# Save broken blend file
# ----------------------------------------------------------------
output_path = "BROKEN_BLEND_PLACEHOLDER"
bpy.ops.wm.save_as_mainfile(filepath=output_path)
print(f"\nSaved broken scene to: {output_path}")

# ----------------------------------------------------------------
# Write original materials JSON
# ----------------------------------------------------------------
with open("/tmp/original_materials.json", "w") as f:
    json.dump(originals, f, indent=2, default=str)

# ----------------------------------------------------------------
# Output matched names as JSON line for shell parsing
# ----------------------------------------------------------------
print("MATCHED_JSON:" + json.dumps(matched))
PYEOF

# Replace placeholders with actual paths
sed -i "s|SOURCE_BLEND_PLACEHOLDER|$SOURCE_BLEND|g" /tmp/break_materials.py
sed -i "s|BROKEN_BLEND_PLACEHOLDER|$BROKEN_BLEND|g" /tmp/break_materials.py

echo "Running Blender headlessly to break materials..."
BLENDER_OUTPUT=$(/opt/blender/blender --background --python /tmp/break_materials.py 2>&1)
echo "$BLENDER_OUTPUT" | tail -40

# ================================================================
# PARSE MATCHED MATERIAL NAMES
# ================================================================
MATCHED_JSON=$(echo "$BLENDER_OUTPUT" | grep '^MATCHED_JSON:' | head -1 | sed 's/^MATCHED_JSON://')
if [ -z "$MATCHED_JSON" ]; then
    echo "ERROR: Could not extract matched material names from Blender output"
    MATCHED_JSON='{"floor":"unknown","wall":"unknown","desk":"unknown","glass":"unknown"}'
fi
echo "Matched materials: $MATCHED_JSON"

# Extract individual names for initial_state.json
FLOOR_MAT=$(echo "$MATCHED_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('floor','unknown'))" 2>/dev/null || echo "unknown")
WALL_MAT=$(echo "$MATCHED_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('wall','unknown'))" 2>/dev/null || echo "unknown")
DESK_MAT=$(echo "$MATCHED_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('desk','unknown'))" 2>/dev/null || echo "unknown")
GLASS_MAT=$(echo "$MATCHED_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('glass','unknown'))" 2>/dev/null || echo "unknown")

# ================================================================
# SAVE INITIAL STATE
# ================================================================
cat > /tmp/initial_state.json << EOF
{
    "source_blend": "$SOURCE_BLEND",
    "broken_blend": "$BROKEN_BLEND",
    "output_blend": "$OUTPUT_BLEND",
    "matched_materials": $MATCHED_JSON,
    "floor_material": "$FLOOR_MAT",
    "wall_material": "$WALL_MAT",
    "desk_material": "$DESK_MAT",
    "glass_material": "$GLASS_MAT",
    "grey_base_color": [0.5, 0.5, 0.5, 1.0],
    "grey_roughness": 0.5,
    "grey_metallic": 0.0,
    "grey_transmission": 0.0,
    "task_start_time": $(date +%s),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Initial state saved to /tmp/initial_state.json:"
cat /tmp/initial_state.json

# ================================================================
# KILL ANY RUNNING BLENDER, LAUNCH WITH BROKEN SCENE
# ================================================================
echo "Stopping any existing Blender instances..."
pkill -9 -f blender 2>/dev/null || true
sleep 2

echo "Launching Blender with broken classroom scene..."
su - ga -c "DISPLAY=:1 /opt/blender/blender '$BROKEN_BLEND' &"
sleep 8

# Focus and maximize Blender window
focus_blender 2>/dev/null || true
sleep 1
maximize_blender 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Fix 4 broken materials in the classroom scene"
echo "  Floor material:  $FLOOR_MAT"
echo "  Wall material:   $WALL_MAT"
echo "  Desk material:   $DESK_MAT"
echo "  Glass material:  $GLASS_MAT"
echo "Save to: $OUTPUT_BLEND"
