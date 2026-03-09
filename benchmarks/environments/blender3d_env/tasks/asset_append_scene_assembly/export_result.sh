#!/bin/bash
echo "=== Exporting asset_append_scene_assembly result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_BLEND="/home/ga/BlenderProjects/assembled_room.blend"
OUTPUT_IMAGE="/home/ga/BlenderProjects/assembled_room.png"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence and timestamps
BLEND_EXISTS="false"
BLEND_CREATED_DURING="false"
IMAGE_EXISTS="false"
IMAGE_CREATED_DURING="false"
IMAGE_SIZE="0"

if [ -f "$OUTPUT_BLEND" ]; then
    BLEND_EXISTS="true"
    MTIME=$(stat -c %Y "$OUTPUT_BLEND")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        BLEND_CREATED_DURING="true"
    fi
fi

if [ -f "$OUTPUT_IMAGE" ]; then
    IMAGE_EXISTS="true"
    IMAGE_SIZE=$(stat -c %s "$OUTPUT_IMAGE")
    MTIME=$(stat -c %Y "$OUTPUT_IMAGE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        IMAGE_CREATED_DURING="true"
    fi
fi

# Analyze the blend file content using Blender Python
SCENE_ANALYSIS="{}"
if [ "$BLEND_EXISTS" = "true" ]; then
    echo "Analyzing blend file..."
    cat > /tmp/analyze_scene.py << 'PYEOF'
import bpy
import json
import math

# Open file without loading UI to be faster/safer
bpy.ops.wm.open_mainfile(filepath="/home/ga/BlenderProjects/assembled_room.blend")

objects = []
target_names = ["Table", "Chair", "Bookshelf"]
found_targets = {}

# Define room bounds (approximate)
ROOM_X_MIN, ROOM_X_MAX = -4.0, 4.0
ROOM_Y_MIN, ROOM_Y_MAX = -3.0, 3.0

# Check objects
for obj in bpy.data.objects:
    # Basic info
    info = {
        "name": obj.name,
        "location": list(obj.location),
        "dimensions": list(obj.dimensions),
        "type": obj.type
    }
    objects.append(info)
    
    # Check if this is one of our targets (simple name check)
    # We check if target name is contained in object name (e.g., "Table.001")
    for target in target_names:
        if target.lower() in obj.name.lower():
            # Store detail about this target found
            found_targets[target] = {
                "name": obj.name,
                "location": list(obj.location),
                "in_room": (ROOM_X_MIN <= obj.location.x <= ROOM_X_MAX and 
                           ROOM_Y_MIN <= obj.location.y <= ROOM_Y_MAX),
                "on_floor": abs(obj.location.z) < 0.5  # Tolerance for pivot points
            }

# Check room integrity (did they delete the floor?)
room_integrity = any("RoomFloor" in o["name"] for o in objects)

# Calculate overlaps (simple distance check)
overlaps = []
target_keys = list(found_targets.keys())
for i in range(len(target_keys)):
    for j in range(i + 1, len(target_keys)):
        t1 = found_targets[target_keys[i]]
        t2 = found_targets[target_keys[j]]
        
        # Euclidean distance in XY plane
        dist = math.sqrt((t1["location"][0] - t2["location"][0])**2 + 
                         (t1["location"][1] - t2["location"][1])**2)
        
        # If distance is too small, they overlap
        # Using 0.8m as a rough threshold for furniture separation
        if dist < 0.5: 
            overlaps.append(f"{target_keys[i]}-{target_keys[j]}")

result = {
    "found_objects": found_targets,
    "room_integrity": room_integrity,
    "overlaps": overlaps,
    "object_count": len(objects)
}

print("JSON_START" + json.dumps(result) + "JSON_END")
PYEOF

    # Run analysis
    ANALYSIS_OUT=$(/opt/blender/blender --background --python /tmp/analyze_scene.py 2>/dev/null)
    
    # Extract JSON
    SCENE_ANALYSIS=$(echo "$ANALYSIS_OUT" | grep -o "JSON_START.*JSON_END" | sed 's/JSON_START//;s/JSON_END//')
fi

# Create final JSON
cat > /tmp/task_result.json << EOF
{
    "blend_exists": $BLEND_EXISTS,
    "blend_created_during": $BLEND_CREATED_DURING,
    "image_exists": $IMAGE_EXISTS,
    "image_created_during": $IMAGE_CREATED_DURING,
    "image_size": $IMAGE_SIZE,
    "scene_analysis": ${SCENE_ANALYSIS:-{}}
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json