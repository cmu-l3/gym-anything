#!/bin/bash
echo "=== Exporting Rename Volume Node Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task start: $TASK_START"
echo "Task end: $TASK_END"
echo "Duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Check if Slicer is running
SLICER_RUNNING="false"
SLICER_PID=""
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
    echo "Slicer is running (PID: $SLICER_PID)"
else
    echo "Slicer is NOT running"
fi

# Query final volume state from Slicer
echo "Querying final volume state..."

cat > /tmp/query_final_state.py << 'PYEOF'
import json
import slicer
import os

# Get all volume nodes
volume_nodes = slicer.mrmlScene.GetNodesByClass("vtkMRMLScalarVolumeNode")
volume_nodes.InitTraversal()

volumes = []
node = volume_nodes.GetNextItemAsObject()
while node:
    # Get additional info about the node
    vol_info = {
        "name": node.GetName(),
        "id": node.GetID(),
        "class": node.GetClassName()
    }
    
    # Check if it has image data
    if node.GetImageData():
        dims = node.GetImageData().GetDimensions()
        vol_info["dimensions"] = list(dims)
        vol_info["has_data"] = True
    else:
        vol_info["has_data"] = False
    
    volumes.append(vol_info)
    node = volume_nodes.GetNextItemAsObject()

# Check specific names
volume_names = [v["name"] for v in volumes]
has_mrhead = "MRHead" in volume_names
has_new_name = "STUDY001_T1_Brain" in volume_names

# Check Subject Hierarchy for names too
shNode = slicer.mrmlScene.GetSubjectHierarchyNode()
sh_names = []
if shNode:
    # Get all items
    scene_item_id = shNode.GetSceneItemID()
    child_ids = []
    shNode.GetItemChildren(scene_item_id, child_ids, True)
    for item_id in child_ids:
        name = shNode.GetItemName(item_id)
        if name:
            sh_names.append(name)

result = {
    "volume_count": len(volumes),
    "volume_names": volume_names,
    "volumes": volumes,
    "has_mrhead": has_mrhead,
    "has_new_name": has_new_name,
    "subject_hierarchy_names": sh_names,
    "mrhead_in_sh": "MRHead" in sh_names,
    "new_name_in_sh": "STUDY001_T1_Brain" in sh_names
}

# Save result
with open("/tmp/final_volumes.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Final state: {len(volumes)} volumes")
print(f"Volume names: {volume_names}")
print(f"Has MRHead: {has_mrhead}")
print(f"Has STUDY001_T1_Brain: {has_new_name}")
PYEOF

# Execute query in Slicer
QUERY_SUCCESS="false"
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Running query script in Slicer..."
    su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer --no-main-window --python-script /tmp/query_final_state.py" > /tmp/final_query.log 2>&1 &
    QUERY_PID=$!
    
    # Wait for query with timeout
    for i in {1..20}; do
        if [ -f /tmp/final_volumes.json ]; then
            QUERY_SUCCESS="true"
            break
        fi
        sleep 1
    done
    
    kill $QUERY_PID 2>/dev/null || true
fi

# Load initial state
INITIAL_VOLUME_COUNT=1
INITIAL_HAS_MRHEAD="true"
if [ -f /tmp/initial_volumes.json ]; then
    INITIAL_VOLUME_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_volumes.json')).get('volume_count', 1))" 2>/dev/null || echo "1")
    INITIAL_HAS_MRHEAD=$(python3 -c "import json; print('true' if json.load(open('/tmp/initial_volumes.json')).get('has_mrhead', True) else 'false')" 2>/dev/null || echo "true")
fi

# Load final state
FINAL_VOLUME_COUNT=0
FINAL_VOLUME_NAMES=""
FINAL_HAS_MRHEAD="true"
FINAL_HAS_NEW_NAME="false"

if [ -f /tmp/final_volumes.json ]; then
    echo "Final volumes state:"
    cat /tmp/final_volumes.json
    
    FINAL_VOLUME_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/final_volumes.json')).get('volume_count', 0))" 2>/dev/null || echo "0")
    FINAL_VOLUME_NAMES=$(python3 -c "import json; print(','.join(json.load(open('/tmp/final_volumes.json')).get('volume_names', [])))" 2>/dev/null || echo "")
    FINAL_HAS_MRHEAD=$(python3 -c "import json; print('true' if json.load(open('/tmp/final_volumes.json')).get('has_mrhead', True) else 'false')" 2>/dev/null || echo "true")
    FINAL_HAS_NEW_NAME=$(python3 -c "import json; print('true' if json.load(open('/tmp/final_volumes.json')).get('has_new_name', False) else 'false')" 2>/dev/null || echo "false")
else
    echo "WARNING: Could not query final state from Slicer"
fi

# Determine if rename was successful
RENAME_SUCCESS="false"
if [ "$FINAL_HAS_NEW_NAME" = "true" ] && [ "$FINAL_HAS_MRHEAD" = "false" ]; then
    RENAME_SUCCESS="true"
fi

# Check if volume count changed (anti-gaming: shouldn't change for rename)
VOLUME_COUNT_UNCHANGED="false"
if [ "$FINAL_VOLUME_COUNT" = "$INITIAL_VOLUME_COUNT" ] && [ "$FINAL_VOLUME_COUNT" -gt 0 ]; then
    VOLUME_COUNT_UNCHANGED="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "duration_seconds": $((TASK_END - TASK_START)),
    "slicer_was_running": $SLICER_RUNNING,
    "query_success": $QUERY_SUCCESS,
    "initial_volume_count": $INITIAL_VOLUME_COUNT,
    "initial_has_mrhead": $INITIAL_HAS_MRHEAD,
    "final_volume_count": $FINAL_VOLUME_COUNT,
    "final_volume_names": "$FINAL_VOLUME_NAMES",
    "final_has_mrhead": $FINAL_HAS_MRHEAD,
    "final_has_new_name": $FINAL_HAS_NEW_NAME,
    "volume_count_unchanged": $VOLUME_COUNT_UNCHANGED,
    "rename_success": $RENAME_SUCCESS,
    "screenshot_exists": $([ -f /tmp/task_final.png ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/rename_task_result.json 2>/dev/null || sudo rm -f /tmp/rename_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/rename_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/rename_task_result.json
chmod 666 /tmp/rename_task_result.json 2>/dev/null || sudo chmod 666 /tmp/rename_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/rename_task_result.json
echo ""
echo "=== Export Complete ==="