#!/bin/bash
echo "=== Exporting copper_pipe_curve_modeling result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_BLEND="/home/ga/BlenderProjects/pipe_system.blend"
OUTPUT_RENDER="/home/ga/BlenderProjects/pipe_render.png"

# Take final screenshot of the UI
take_screenshot /tmp/task_final.png

# Check render output
RENDER_EXISTS="false"
RENDER_SIZE="0"
if [ -f "$OUTPUT_RENDER" ]; then
    RENDER_EXISTS="true"
    RENDER_SIZE=$(stat -c%s "$OUTPUT_RENDER" 2>/dev/null || echo "0")
fi

# Check blend file
BLEND_EXISTS="false"
if [ -f "$OUTPUT_BLEND" ]; then
    BLEND_EXISTS="true"
fi

# ================================================================
# ANALYZE BLEND FILE WITH BLENDER PYTHON
# ================================================================
# We need to extract:
# 1. Number of curve objects
# 2. Bevel depth of each curve
# 3. Spline point counts (to detect bends vs straight lines)
# 4. Material properties (Base Color, Metallic, Roughness)

ANALYSIS_SCRIPT=$(mktemp /tmp/analyze_pipes.XXXXXX.py)
cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import bpy
import json
import sys

# Open the submitted file
try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/pipe_system.blend")
except:
    print(json.dumps({"error": "Could not open blend file"}))
    sys.exit(0)

curves = []
materials_data = []

# Iterate through all objects to find curves
for obj in bpy.data.objects:
    if obj.type == 'CURVE':
        curve_data = obj.data
        
        # Get spline info to detect bends
        spline_info = []
        is_bent = False
        for spline in curve_data.splines:
            point_count = len(spline.bezier_points) if spline.type == 'BEZIER' else len(spline.points)
            spline_info.append({
                "type": spline.type,
                "point_count": point_count
            })
            # A spline with > 2 points likely has a bend, or 2 points with handles
            if point_count > 2:
                is_bent = True
            elif spline.type == 'BEZIER' and point_count == 2:
                # Check handles if only 2 points
                p1 = spline.bezier_points[0]
                p2 = spline.bezier_points[1]
                # If handles are not vector/auto-aligned to line, it might be curved
                # Simplification: just assume >2 points or manual check is hard
                pass

        # Get material info
        mat_info = {"name": "None", "metallic": 0.0, "roughness": 0.5, "color": [0.8, 0.8, 0.8]}
        if obj.data.materials:
            mat = obj.data.materials[0]
            if mat and mat.use_nodes and mat.node_tree:
                mat_info["name"] = mat.name
                # Find Principled BSDF
                bsdf = None
                for node in mat.node_tree.nodes:
                    if node.type == 'BSDF_PRINCIPLED':
                        bsdf = node
                        break
                
                if bsdf:
                    # Base Color
                    bc = bsdf.inputs.get("Base Color")
                    if bc:
                        mat_info["color"] = list(bc.default_value)[:3]
                    
                    # Metallic
                    met = bsdf.inputs.get("Metallic")
                    if met:
                        mat_info["metallic"] = met.default_value
                    
                    # Roughness
                    rough = bsdf.inputs.get("Roughness")
                    if rough:
                        mat_info["roughness"] = rough.default_value
            
            # Store unique materials for global check
            materials_data.append(mat_info)

        curves.append({
            "name": obj.name,
            "bevel_depth": curve_data.bevel_depth,
            "bevel_resolution": curve_data.bevel_resolution,
            "fill_mode": curve_data.fill_mode,
            "splines": spline_info,
            "is_bent": is_bent,
            "material": mat_info
        })

result = {
    "curve_count": len(curves),
    "curves": curves,
    "unique_materials": materials_data
}

print("JSON:" + json.dumps(result))
PYEOF

# Run analysis
SCENE_DATA="{}"
if [ "$BLEND_EXISTS" = "true" ]; then
    RAW_OUTPUT=$(/opt/blender/blender --background --python "$ANALYSIS_SCRIPT" 2>/dev/null)
    # Extract JSON line
    SCENE_DATA=$(echo "$RAW_OUTPUT" | grep "^JSON:" | sed 's/^JSON://')
    if [ -z "$SCENE_DATA" ]; then
        SCENE_DATA='{"error": "Failed to parse Blender output"}'
    fi
else
    SCENE_DATA='{"error": "Blend file not found"}'
fi

rm -f "$ANALYSIS_SCRIPT"

# Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "blend_exists": $BLEND_EXISTS,
    "render_exists": $RENDER_EXISTS,
    "render_size": $RENDER_SIZE,
    "scene_data": $SCENE_DATA,
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json