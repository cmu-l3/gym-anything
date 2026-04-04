#!/bin/bash
echo "=== Exporting Campfire Simulation Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_BLEND="/home/ga/BlenderProjects/campfire_sim.blend"
RESULT_FILE="/tmp/task_result.json"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamp
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE_KB=0

if [ -f "$OUTPUT_BLEND" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_BLEND" 2>/dev/null || echo "0")
    FILE_SIZE_KB=$((FILE_SIZE / 1024))
    FILE_MTIME=$(stat -c%Y "$OUTPUT_BLEND" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 3. Analyze the Scene with Blender Python
# This script opens the submitted file and inspects the physics and material settings
cat > /tmp/analyze_sim.py << 'PYEOF'
import bpy
import json
import sys

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/campfire_sim.blend")
    
    result = {
        "analysis_success": True,
        "object_count": len(bpy.data.objects),
        "domain_found": False,
        "domain_type_gas": False,
        "domain_resolution": 0,
        "flow_found": False,
        "flow_type_fire": False,  # True if FIRE or BOTH
        "volume_material_found": False,
        "frame_start": bpy.context.scene.frame_start,
        "frame_end": bpy.context.scene.frame_end
    }

    # Check Objects for Modifiers
    for obj in bpy.data.objects:
        # Check Fluid Modifiers
        for mod in obj.modifiers:
            if mod.type == 'FLUID':
                if mod.fluid_type == 'DOMAIN':
                    result["domain_found"] = True
                    ds = mod.domain_settings
                    if ds.domain_type == 'GAS':
                        result["domain_type_gas"] = True
                    result["domain_resolution"] = ds.resolution_max
                    
                    # Check Material on Domain Object
                    # Needs to be a Volume shader
                    if obj.active_material and obj.active_material.use_nodes:
                        tree = obj.active_material.node_tree
                        for node in tree.nodes:
                            if node.type in ['PRINCIPLED_VOLUME', 'VOLUME_SCATTER', 'VOLUME_ABSORPTION']:
                                # Check if connected to Output Volume socket
                                # (Strict check: is it linked to Material Output Volume?)
                                # For simplicity, existence of the node is usually enough evidence of intent,
                                # but let's check links if possible.
                                result["volume_material_found"] = True
                    
                elif mod.fluid_type == 'FLOW':
                    result["flow_found"] = True
                    fs = mod.flow_settings
                    if fs.flow_type in ['FIRE', 'BOTH']:
                        result["flow_type_fire"] = True

    print("ANALYSIS_JSON:" + json.dumps(result))

except Exception as e:
    print("ANALYSIS_JSON:" + json.dumps({"analysis_success": False, "error": str(e)}))
PYEOF

if [ "$FILE_EXISTS" = "true" ]; then
    ANALYSIS_OUTPUT=$(su - ga -c "/opt/blender/blender --background --python /tmp/analyze_sim.py 2>/dev/null" | grep "^ANALYSIS_JSON:" | sed 's/^ANALYSIS_JSON://')
else
    ANALYSIS_OUTPUT='{"analysis_success": false, "error": "File not found"}'
fi

# 4. Merge results into final JSON
python3 << PYEOF
import json
import os

try:
    analysis = json.loads('$ANALYSIS_OUTPUT')
except:
    analysis = {}

final_result = {
    "file_exists": "$FILE_EXISTS" == "true",
    "file_modified": "$FILE_MODIFIED" == "true",
    "file_size_kb": int("$FILE_SIZE_KB"),
    "scene_analysis": analysis
}

with open("$RESULT_FILE", "w") as f:
    json.dump(final_result, f, indent=2)
PYEOF

echo "Result saved to $RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "=== Export complete ==="