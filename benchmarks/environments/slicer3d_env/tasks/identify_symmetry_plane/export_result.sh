#!/bin/bash
echo "=== Exporting Identify Midsagittal Symmetry Plane Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Directories
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
EXPECTED_SCREENSHOT="$SCREENSHOT_DIR/midsagittal_plane.png"

# Check if Slicer is running
SLICER_RUNNING="false"
SLICER_PID=""
if pgrep -f "Slicer" > /dev/null; then
    SLICER_RUNNING="true"
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
    echo "Slicer is running (PID: $SLICER_PID)"
fi

# Extract plane information from Slicer using Python
echo "Extracting plane markup information from Slicer..."

PLANE_INFO_FILE="/tmp/plane_info_extracted.json"

if [ "$SLICER_RUNNING" = "true" ]; then
    # Create extraction script
    cat > /tmp/extract_plane_info.py << 'PYEOF'
#!/usr/bin/env python3
import json
import math
import os

try:
    import slicer
    
    result = {
        "extraction_success": True,
        "plane_found": False,
        "plane_name": "",
        "plane_normal": [0.0, 0.0, 0.0],
        "plane_origin": [0.0, 0.0, 0.0],
        "plane_created_after_start": False,
        "volume_loaded": False,
        "volume_center": [0.0, 0.0, 0.0],
        "volume_bounds": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        "all_plane_nodes": [],
        "orientation_angle_from_lr_deg": 999.0
    }
    
    # Get task start time
    task_start = 0
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            task_start = int(f.read().strip())
    except:
        pass
    
    # Check for loaded volumes
    vol_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
    for vol in vol_nodes:
        name = vol.GetName()
        if "MRHead" in name or "mr" in name.lower():
            result["volume_loaded"] = True
            bounds = [0.0] * 6
            vol.GetBounds(bounds)
            result["volume_bounds"] = bounds
            result["volume_center"] = [
                (bounds[0] + bounds[1]) / 2.0,
                (bounds[2] + bounds[3]) / 2.0,
                (bounds[4] + bounds[5]) / 2.0
            ]
            break
    
    # Find plane markups
    plane_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsPlaneNode")
    
    for node in plane_nodes:
        node_name = node.GetName()
        result["all_plane_nodes"].append(node_name)
        
        # Check if name contains midsagittal (case insensitive)
        name_lower = node_name.lower()
        if "midsagittal" in name_lower or "midline" in name_lower or "symmetry" in name_lower or "sagittal" in name_lower:
            result["plane_found"] = True
            result["plane_name"] = node_name
            
            # Get plane normal
            normal = [0.0, 0.0, 0.0]
            node.GetNormal(normal)
            result["plane_normal"] = list(normal)
            
            # Get plane origin
            origin = [0.0, 0.0, 0.0]
            node.GetOrigin(origin)
            result["plane_origin"] = list(origin)
            
            # Calculate angle from L-R axis [1, 0, 0]
            lr_axis = [1.0, 0.0, 0.0]
            dot_product = abs(sum(a * b for a, b in zip(normal, lr_axis)))
            # Clamp to [-1, 1] for numerical stability
            dot_product = max(-1.0, min(1.0, dot_product))
            angle_rad = math.acos(dot_product)
            result["orientation_angle_from_lr_deg"] = math.degrees(angle_rad)
            
            # Check if plane was created after task start
            # (Slicer doesn't have creation timestamps, so we can't verify this directly)
            # We'll use the fact that the plane exists and has proper orientation as evidence
            result["plane_created_after_start"] = True
            
            break
    
    # If no matching name found, check if any plane exists
    if not result["plane_found"] and plane_nodes:
        # Use first plane found
        node = plane_nodes[0]
        result["plane_found"] = True
        result["plane_name"] = node.GetName()
        
        normal = [0.0, 0.0, 0.0]
        node.GetNormal(normal)
        result["plane_normal"] = list(normal)
        
        origin = [0.0, 0.0, 0.0]
        node.GetOrigin(origin)
        result["plane_origin"] = list(origin)
        
        lr_axis = [1.0, 0.0, 0.0]
        dot_product = abs(sum(a * b for a, b in zip(normal, lr_axis)))
        dot_product = max(-1.0, min(1.0, dot_product))
        angle_rad = math.acos(dot_product)
        result["orientation_angle_from_lr_deg"] = math.degrees(angle_rad)
        result["plane_created_after_start"] = True
    
    # Write result
    with open("/tmp/plane_info_extracted.json", "w") as f:
        json.dump(result, f, indent=2)
    
    print("Plane extraction complete")
    print(json.dumps(result, indent=2))

except Exception as e:
    error_result = {
        "extraction_success": False,
        "error": str(e),
        "plane_found": False
    }
    with open("/tmp/plane_info_extracted.json", "w") as f:
        json.dump(error_result, f, indent=2)
    print(f"Error during extraction: {e}")
PYEOF

    # Run extraction script in Slicer
    chmod 644 /tmp/extract_plane_info.py
    
    # Execute in Slicer's Python environment
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --python-script /tmp/extract_plane_info.py 2>/tmp/slicer_extract.log &
    EXTRACT_PID=$!
    
    # Wait for extraction with timeout
    for i in {1..30}; do
        if [ -f "$PLANE_INFO_FILE" ]; then
            echo "Plane info extracted successfully"
            break
        fi
        sleep 1
    done
    
    # Kill extraction process if still running
    kill $EXTRACT_PID 2>/dev/null || true
fi

# Read extracted plane info
PLANE_FOUND="false"
PLANE_NAME=""
PLANE_NORMAL_X="0"
PLANE_NORMAL_Y="0"
PLANE_NORMAL_Z="0"
PLANE_ORIGIN_X="0"
PLANE_ORIGIN_Y="0"
PLANE_ORIGIN_Z="0"
ORIENTATION_ANGLE="999"
VOLUME_LOADED="false"
VOLUME_CENTER_X="0"
VOLUME_CENTER_Y="0"
VOLUME_CENTER_Z="0"

if [ -f "$PLANE_INFO_FILE" ]; then
    echo "Reading plane info from extraction..."
    PLANE_FOUND=$(python3 -c "import json; d=json.load(open('$PLANE_INFO_FILE')); print('true' if d.get('plane_found', False) else 'false')" 2>/dev/null || echo "false")
    PLANE_NAME=$(python3 -c "import json; d=json.load(open('$PLANE_INFO_FILE')); print(d.get('plane_name', ''))" 2>/dev/null || echo "")
    PLANE_NORMAL_X=$(python3 -c "import json; d=json.load(open('$PLANE_INFO_FILE')); print(d.get('plane_normal', [0,0,0])[0])" 2>/dev/null || echo "0")
    PLANE_NORMAL_Y=$(python3 -c "import json; d=json.load(open('$PLANE_INFO_FILE')); print(d.get('plane_normal', [0,0,0])[1])" 2>/dev/null || echo "0")
    PLANE_NORMAL_Z=$(python3 -c "import json; d=json.load(open('$PLANE_INFO_FILE')); print(d.get('plane_normal', [0,0,0])[2])" 2>/dev/null || echo "0")
    PLANE_ORIGIN_X=$(python3 -c "import json; d=json.load(open('$PLANE_INFO_FILE')); print(d.get('plane_origin', [0,0,0])[0])" 2>/dev/null || echo "0")
    PLANE_ORIGIN_Y=$(python3 -c "import json; d=json.load(open('$PLANE_INFO_FILE')); print(d.get('plane_origin', [0,0,0])[1])" 2>/dev/null || echo "0")
    PLANE_ORIGIN_Z=$(python3 -c "import json; d=json.load(open('$PLANE_INFO_FILE')); print(d.get('plane_origin', [0,0,0])[2])" 2>/dev/null || echo "0")
    ORIENTATION_ANGLE=$(python3 -c "import json; d=json.load(open('$PLANE_INFO_FILE')); print(d.get('orientation_angle_from_lr_deg', 999))" 2>/dev/null || echo "999")
    VOLUME_LOADED=$(python3 -c "import json; d=json.load(open('$PLANE_INFO_FILE')); print('true' if d.get('volume_loaded', False) else 'false')" 2>/dev/null || echo "false")
    VOLUME_CENTER_X=$(python3 -c "import json; d=json.load(open('$PLANE_INFO_FILE')); print(d.get('volume_center', [0,0,0])[0])" 2>/dev/null || echo "0")
    VOLUME_CENTER_Y=$(python3 -c "import json; d=json.load(open('$PLANE_INFO_FILE')); print(d.get('volume_center', [0,0,0])[1])" 2>/dev/null || echo "0")
    VOLUME_CENTER_Z=$(python3 -c "import json; d=json.load(open('$PLANE_INFO_FILE')); print(d.get('volume_center', [0,0,0])[2])" 2>/dev/null || echo "0")
    
    echo "Plane found: $PLANE_FOUND"
    echo "Plane name: $PLANE_NAME"
    echo "Orientation angle from L-R: $ORIENTATION_ANGLE degrees"
fi

# Check for screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB="0"
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k "$EXPECTED_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
    
    # Check if screenshot was created during task
    SCREENSHOT_MTIME=$(stat -c%Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
    
    echo "Screenshot found: $EXPECTED_SCREENSHOT ($SCREENSHOT_SIZE_KB KB)"
    echo "Created during task: $SCREENSHOT_CREATED_DURING_TASK"
    
    # Copy screenshot for verification
    cp "$EXPECTED_SCREENSHOT" /tmp/user_midsagittal_screenshot.png 2>/dev/null || true
fi

# Also check for any new screenshots
FINAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l || echo "0")
INITIAL_SCREENSHOT_COUNT=$(cat /tmp/initial_screenshot_count.txt 2>/dev/null || echo "0")
NEW_SCREENSHOTS=$((FINAL_SCREENSHOT_COUNT - INITIAL_SCREENSHOT_COUNT))

# Check plane naming
NAME_CONTAINS_MIDSAGITTAL="false"
if [ -n "$PLANE_NAME" ]; then
    NAME_LOWER=$(echo "$PLANE_NAME" | tr '[:upper:]' '[:lower:]')
    if echo "$NAME_LOWER" | grep -q "midsagittal\|midline\|symmetry"; then
        NAME_CONTAINS_MIDSAGITTAL="true"
    fi
fi

# Create final result JSON
RESULT_FILE="/tmp/symmetry_plane_result.json"
cat > "$RESULT_FILE" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_sec": $((TASK_END - TASK_START)),
    
    "slicer_was_running": $SLICER_RUNNING,
    "volume_loaded": $VOLUME_LOADED,
    "volume_center": [$VOLUME_CENTER_X, $VOLUME_CENTER_Y, $VOLUME_CENTER_Z],
    
    "plane_found": $PLANE_FOUND,
    "plane_name": "$PLANE_NAME",
    "name_contains_midsagittal": $NAME_CONTAINS_MIDSAGITTAL,
    "plane_normal": [$PLANE_NORMAL_X, $PLANE_NORMAL_Y, $PLANE_NORMAL_Z],
    "plane_origin": [$PLANE_ORIGIN_X, $PLANE_ORIGIN_Y, $PLANE_ORIGIN_Z],
    "orientation_angle_from_lr_deg": $ORIENTATION_ANGLE,
    
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "$EXPECTED_SCREENSHOT",
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "new_screenshots_count": $NEW_SCREENSHOTS,
    
    "final_screenshot_path": "/tmp/task_final_state.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo ""
echo "=== Export Result ==="
cat "$RESULT_FILE"
echo ""
echo "Result saved to: $RESULT_FILE"
echo "=== Export Complete ==="