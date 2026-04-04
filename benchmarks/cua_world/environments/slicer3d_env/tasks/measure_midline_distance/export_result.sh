#!/bin/bash
echo "=== Exporting Measure Midline Distance Result ==="

source /workspace/scripts/task_utils.sh

# Get paths
BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
EXPECTED_SCREENSHOT="$SCREENSHOT_DIR/midline_distance.png"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Initialize result variables
LINE_ANNOTATION_EXISTS="false"
LINE_LENGTH_MM="0"
ENDPOINT1_RAS="[0, 0, 0]"
ENDPOINT2_RAS="[0, 0, 0]"
NUM_LINE_NODES=0

# Try to extract line markup data from Slicer
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Extracting markup data from Slicer..."
    
    cat > /tmp/extract_midline_markup.py << 'PYEOF'
import slicer
import json
import math
import os

output_data = {
    "line_nodes": [],
    "num_line_nodes": 0,
    "screenshot_dir": "/home/ga/Documents/SlicerData/Screenshots"
}

# Find all line markup nodes
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
output_data["num_line_nodes"] = len(line_nodes)

print(f"Found {len(line_nodes)} line markup node(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        
        # Calculate length
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        line_info = {
            "name": node.GetName(),
            "length_mm": length,
            "p1_ras": p1,
            "p2_ras": p2,
            "num_points": n_points
        }
        output_data["line_nodes"].append(line_info)
        
        print(f"  Line '{node.GetName()}': {length:.2f} mm")
        print(f"    P1 (RAS): [{p1[0]:.1f}, {p1[1]:.1f}, {p1[2]:.1f}]")
        print(f"    P2 (RAS): [{p2[0]:.1f}, {p2[1]:.1f}, {p2[2]:.1f}]")
        
        # Save the markup node
        try:
            markup_path = f"/home/ga/Documents/SlicerData/BraTS/midline_measurement_{node.GetName()}.mrk.json"
            slicer.util.saveNode(node, markup_path)
            print(f"    Saved to: {markup_path}")
        except Exception as e:
            print(f"    Failed to save markup: {e}")

# Also check for any fiducial nodes (in case user placed points instead of line)
fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
output_data["num_fiducial_nodes"] = len(fiducial_nodes)

# Save the extracted data
output_path = "/tmp/slicer_markup_data.json"
with open(output_path, "w") as f:
    json.dump(output_data, f, indent=2)

print(f"\nMarkup data saved to {output_path}")
PYEOF

    # Run the extraction script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/extract_midline_markup.py --no-main-window > /tmp/slicer_extract.log 2>&1 &
    EXTRACT_PID=$!
    
    # Wait for extraction (max 15 seconds)
    for i in $(seq 1 15); do
        if [ -f /tmp/slicer_markup_data.json ]; then
            break
        fi
        sleep 1
    done
    
    # Kill extraction process if still running
    kill $EXTRACT_PID 2>/dev/null || true
    sleep 1
fi

# Parse the extracted markup data
if [ -f /tmp/slicer_markup_data.json ]; then
    echo "Parsing extracted markup data..."
    
    MARKUP_DATA=$(cat /tmp/slicer_markup_data.json)
    NUM_LINE_NODES=$(echo "$MARKUP_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin).get('num_line_nodes', 0))" 2>/dev/null || echo "0")
    
    if [ "$NUM_LINE_NODES" -gt 0 ]; then
        LINE_ANNOTATION_EXISTS="true"
        
        # Get the first line's data
        LINE_LENGTH_MM=$(echo "$MARKUP_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data.get('line_nodes'):
    print(f\"{data['line_nodes'][0]['length_mm']:.2f}\")
else:
    print('0')
" 2>/dev/null || echo "0")
        
        ENDPOINT1_RAS=$(echo "$MARKUP_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data.get('line_nodes'):
    p = data['line_nodes'][0]['p1_ras']
    print(f'[{p[0]:.2f}, {p[1]:.2f}, {p[2]:.2f}]')
else:
    print('[0, 0, 0]')
" 2>/dev/null || echo "[0, 0, 0]")
        
        ENDPOINT2_RAS=$(echo "$MARKUP_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data.get('line_nodes'):
    p = data['line_nodes'][0]['p2_ras']
    print(f'[{p[0]:.2f}, {p[1]:.2f}, {p[2]:.2f}]')
else:
    print('[0, 0, 0]')
" 2>/dev/null || echo "[0, 0, 0]")
    fi
fi

# Check for user-saved screenshot
USER_SCREENSHOT_EXISTS="false"
USER_SCREENSHOT_SIZE_KB=0
USER_SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    USER_SCREENSHOT_EXISTS="true"
    USER_SCREENSHOT_SIZE_KB=$(du -k "$EXPECTED_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
    
    # Check if created during task
    SCREENSHOT_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        USER_SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# Also check for any new screenshots in the directory
FINAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l || echo "0")
INITIAL_SCREENSHOT_COUNT=$(cat /tmp/initial_screenshot_count.txt 2>/dev/null || echo "0")
NEW_SCREENSHOTS=$((FINAL_SCREENSHOT_COUNT - INITIAL_SCREENSHOT_COUNT))

# Find the newest screenshot if any were created
NEWEST_SCREENSHOT=""
if [ "$NEW_SCREENSHOTS" -gt 0 ]; then
    NEWEST_SCREENSHOT=$(ls -t "$SCREENSHOT_DIR"/*.png 2>/dev/null | head -1)
    if [ -n "$NEWEST_SCREENSHOT" ] && [ -f "$NEWEST_SCREENSHOT" ]; then
        # Copy to expected location if user saved elsewhere
        if [ "$USER_SCREENSHOT_EXISTS" = "false" ]; then
            cp "$NEWEST_SCREENSHOT" "$EXPECTED_SCREENSHOT" 2>/dev/null || true
            USER_SCREENSHOT_EXISTS="true"
            USER_SCREENSHOT_SIZE_KB=$(du -k "$EXPECTED_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
            USER_SCREENSHOT_CREATED_DURING_TASK="true"
        fi
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "line_annotation_exists": $LINE_ANNOTATION_EXISTS,
    "num_line_nodes": $NUM_LINE_NODES,
    "line_length_mm": $LINE_LENGTH_MM,
    "endpoint1_ras": $ENDPOINT1_RAS,
    "endpoint2_ras": $ENDPOINT2_RAS,
    "user_screenshot_exists": $USER_SCREENSHOT_EXISTS,
    "user_screenshot_size_kb": $USER_SCREENSHOT_SIZE_KB,
    "user_screenshot_created_during_task": $USER_SCREENSHOT_CREATED_DURING_TASK,
    "new_screenshots_count": $NEW_SCREENSHOTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/midline_task_result.json 2>/dev/null || sudo rm -f /tmp/midline_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/midline_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/midline_task_result.json
chmod 666 /tmp/midline_task_result.json 2>/dev/null || sudo chmod 666 /tmp/midline_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/midline_task_result.json
echo ""
echo "=== Export Complete ==="