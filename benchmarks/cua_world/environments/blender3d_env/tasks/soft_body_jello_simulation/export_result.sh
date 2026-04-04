#!/bin/bash
echo "=== Exporting Soft Body Simulation Result ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/BlenderProjects/jelly_sim.blend"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if output file exists
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Output file not found."
    # Create empty result
    echo '{"exists": false, "file_created": false}' > /tmp/task_result.json
    exit 0
fi

OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
FILE_CREATED="false"
if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
    FILE_CREATED="true"
fi

# ------------------------------------------------------------------
# ANALYZE BLEND FILE & RUN PHYSICS TEST
# ------------------------------------------------------------------
# This script opens the saved file and runs a short simulation to 
# verify the physics configuration actually works.
# ------------------------------------------------------------------
cat > /tmp/analyze_softbody.py << 'PYEOF'
import bpy
import json
import numpy as np
import sys

# Redirect stdout to avoid polluting JSON output
# (We will print only the final JSON to a specific marker)

result = {
    "exists": True,
    "modifiers": {
        "soft_body": False,
        "collision": False
    },
    "settings": {},
    "physics_test": {
        "falls": False,
        "bounces": False,
        "deforms": False,
        "deformation_delta": 0.0
    },
    "errors": []
}

try:
    bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/jelly_sim.blend")
    
    # 1. Check Modifiers
    jelly = bpy.data.objects.get("JellySuzanne")
    plate = bpy.data.objects.get("Plate")
    
    if not jelly:
        result["errors"].append("JellySuzanne object missing")
    else:
        # Check for Soft Body
        sb = next((m for m in jelly.modifiers if m.type == 'SOFT_BODY'), None)
        if sb:
            result["modifiers"]["soft_body"] = True
            s = sb.settings
            result["settings"] = {
                "use_goal": s.use_goal,
                "goal_default": s.goal_default,
                "use_edges": s.use_edges,
                "pull": s.pull,
                "push": s.push,
                "bend": s.bend,
                "mass": s.mass
            }
    
    if not plate:
        result["errors"].append("Plate object missing")
    else:
        # Check for Collision
        col = next((m for m in plate.modifiers if m.type == 'COLLISION'), None)
        if col:
            result["modifiers"]["collision"] = True

    # 2. Physics Simulation Test
    # If modifiers are present, we run a short bake/step to see if it moves
    if result["modifiers"]["soft_body"]:
        
        # Helper to get mesh stats
        def get_mesh_stats(obj):
            # We must get the evaluated object (after physics)
            depsgraph = bpy.context.evaluated_depsgraph_get()
            obj_eval = obj.evaluated_get(depsgraph)
            mesh = obj_eval.data
            
            # Calculate center Z
            verts = [v.co for v in mesh.vertices]
            if not verts: return 0, 0
            
            # Convert local coords to world Z (assuming no parent/simple transforms)
            # Soft body deformation happens in local space usually, but checking world Z is safer
            # Actually soft body moves the vertices.
            
            zs = [v.co.z for v in verts]
            avg_z = sum(zs) / len(zs)
            
            # Calculate "spread" (deformation proxy) - std dev of distance from center
            center = sum((v.co for v in verts), bpy.mathutils.Vector((0,0,0))) / len(verts)
            distances = [(v.co - center).length for v in verts]
            spread = sum(distances) / len(distances)
            
            return avg_z, spread

        # Frame 1 (Start)
        bpy.context.scene.frame_set(1)
        z_start, spread_start = get_mesh_stats(jelly)
        
        # Frame 15 (Mid-air)
        bpy.context.scene.frame_set(15)
        z_mid, spread_mid = get_mesh_stats(jelly)
        
        # Frame 40 (Impact)
        bpy.context.scene.frame_set(40)
        z_impact, spread_impact = get_mesh_stats(jelly)
        
        # Analysis
        # 1. Did it fall?
        if z_mid < z_start - 0.5:
            result["physics_test"]["falls"] = True
            
        # 2. Did it stop/bounce at the plate?
        # Plate is at Z=0. If it fell through floor, Z would be very negative
        # If it stayed suspended, Z would be high
        # If it hit plate, Z should be around 0.0 to 1.5 (depending on origin)
        if -1.0 < z_impact < 2.0 and z_impact < z_start:
            result["physics_test"]["bounces"] = True
            
        # 3. Did it deform?
        # Compare spread (shape) at impact vs start
        delta = abs(spread_impact - spread_start)
        result["physics_test"]["deformation_delta"] = delta
        if delta > 0.05: # Threshold for "squish"
            result["physics_test"]["deforms"] = True

except Exception as e:
    result["errors"].append(str(e))

# Print final JSON to be captured
print("JSON_RESULT:" + json.dumps(result))
PYEOF

# Run analysis
ANALYSIS_LOG=$(mktemp)
su - ga -c "/opt/blender/blender --background --python /tmp/analyze_softbody.py" > "$ANALYSIS_LOG" 2>&1

# Extract JSON
JSON_DATA=$(grep "JSON_RESULT:" "$ANALYSIS_LOG" | sed 's/JSON_RESULT://')

if [ -z "$JSON_DATA" ]; then
    JSON_DATA='{"exists": true, "error": "Analysis failed"}'
fi

# Clean up
rm -f "$ANALYSIS_LOG"

# Combine with shell metadata
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_created": $FILE_CREATED,
    "analysis": $JSON_DATA
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json