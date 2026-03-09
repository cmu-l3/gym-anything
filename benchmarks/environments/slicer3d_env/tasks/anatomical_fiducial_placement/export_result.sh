#!/bin/bash
echo "=== Exporting Anatomical Fiducial Placement Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_MARKUP="$BRATS_DIR/navigation_landmarks.mrk.json"
OUTPUT_SCREENSHOT="$BRATS_DIR/landmarks_screenshot.png"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/landmarks_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export markups from Slicer
    cat > /tmp/export_landmarks.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/BraTS"
os.makedirs(output_dir, exist_ok=True)

# Look for fiducial/point markup nodes
point_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(point_nodes)} fiducial/point node(s)")

all_fiducials = []

for node in point_nodes:
    node_name = node.GetName()
    n_points = node.GetNumberOfControlPoints()
    print(f"  Node '{node_name}': {n_points} point(s)")
    
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        
        fiducial = {
            "node_name": node_name,
            "point_index": i,
            "label": label,
            "position_ras": pos
        }
        all_fiducials.append(fiducial)
        print(f"    Point {i}: '{label}' at [{pos[0]:.1f}, {pos[1]:.1f}, {pos[2]:.1f}]")
    
    # Save each node as markup file
    if n_points > 0:
        mrk_path = os.path.join(output_dir, f"{node_name}.mrk.json")
        slicer.util.saveNode(node, mrk_path)
        print(f"  Saved: {mrk_path}")

# Also save consolidated fiducial data
if all_fiducials:
    consolidated_path = os.path.join(output_dir, "all_fiducials.json")
    with open(consolidated_path, "w") as f:
        json.dump({"fiducials": all_fiducials, "count": len(all_fiducials)}, f, indent=2)
    print(f"Consolidated fiducials saved to: {consolidated_path}")

# Check for Navigation_Landmarks specifically
nav_node = slicer.util.getNode("Navigation_Landmarks") if slicer.util.getNode("Navigation_Landmarks") else None
if nav_node:
    nav_path = os.path.join(output_dir, "navigation_landmarks.mrk.json")
    slicer.util.saveNode(nav_node, nav_path)
    print(f"Navigation_Landmarks saved to: {nav_path}")
else:
    print("Note: No node named 'Navigation_Landmarks' found")

# Try to take a screenshot
try:
    screenshot_path = os.path.join(output_dir, "landmarks_screenshot.png")
    # Capture screenshot of the current view
    layoutManager = slicer.app.layoutManager()
    if layoutManager:
        widget = layoutManager.viewport()
        if widget:
            pixmap = widget.grab()
            pixmap.save(screenshot_path)
            print(f"Screenshot saved to: {screenshot_path}")
except Exception as e:
    print(f"Could not capture screenshot: {e}")

print("Export complete")
PYEOF

    # Run export script in Slicer (headless)
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_landmarks.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    EXPORT_PID=$!
    sleep 15
    kill $EXPORT_PID 2>/dev/null || true
fi

# Check for markup file
MARKUP_EXISTS="false"
MARKUP_PATH=""
FIDUCIAL_COUNT=0
FIDUCIAL_DATA="[]"

POSSIBLE_MARKUP_PATHS=(
    "$OUTPUT_MARKUP"
    "$BRATS_DIR/Navigation_Landmarks.mrk.json"
    "$BRATS_DIR/all_fiducials.json"
    "$BRATS_DIR/F.mrk.json"
    "/home/ga/Documents/navigation_landmarks.mrk.json"
)

for path in "${POSSIBLE_MARKUP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKUP_EXISTS="true"
        MARKUP_PATH="$path"
        echo "Found markup at: $path"
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_MARKUP" ]; then
            cp "$path" "$OUTPUT_MARKUP" 2>/dev/null || true
        fi
        
        # Parse the file to extract fiducial data
        FIDUCIAL_DATA=$(python3 << PYPARSEOF
import json
import sys

try:
    with open("$path", "r") as f:
        data = json.load(f)
    
    fiducials = []
    
    # Handle Slicer markup format
    if "markups" in data:
        for markup in data.get("markups", []):
            for cp in markup.get("controlPoints", []):
                fid = {
                    "label": cp.get("label", ""),
                    "position": cp.get("position", [0,0,0])
                }
                fiducials.append(fid)
    # Handle consolidated format
    elif "fiducials" in data:
        fiducials = data["fiducials"]
    # Handle simple array format
    elif isinstance(data, list):
        fiducials = data
    
    print(json.dumps(fiducials))
except Exception as e:
    print("[]")
    sys.stderr.write(f"Parse error: {e}\\n")
PYPARSEOF
)
        FIDUCIAL_COUNT=$(echo "$FIDUCIAL_DATA" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
        echo "Found $FIDUCIAL_COUNT fiducials"
        break
    fi
done

# Check if agent created screenshot
SCREENSHOT_EXISTS="false"
SCREENSHOT_PATH=""

POSSIBLE_SCREENSHOT_PATHS=(
    "$OUTPUT_SCREENSHOT"
    "$BRATS_DIR/landmarks_screenshot.png"
    "$BRATS_DIR/screenshot.png"
    "/home/ga/Documents/landmarks_screenshot.png"
)

for path in "${POSSIBLE_SCREENSHOT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SCREENSHOT_EXISTS="true"
        SCREENSHOT_PATH="$path"
        echo "Found screenshot at: $path"
        if [ "$path" != "$OUTPUT_SCREENSHOT" ]; then
            cp "$path" "$OUTPUT_SCREENSHOT" 2>/dev/null || true
        fi
        break
    fi
done

# Check if files were created during task (anti-gaming)
MARKUP_CREATED_DURING_TASK="false"
if [ "$MARKUP_EXISTS" = "true" ] && [ -f "$OUTPUT_MARKUP" ]; then
    MARKUP_MTIME=$(stat -c %Y "$OUTPUT_MARKUP" 2>/dev/null || echo "0")
    if [ "$MARKUP_MTIME" -gt "$TASK_START" ]; then
        MARKUP_CREATED_DURING_TASK="true"
    fi
fi

# Copy ground truth for verifier
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_landmarks_gt.json" /tmp/landmarks_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/landmarks_ground_truth.json 2>/dev/null || true

# Copy agent markup for verifier
if [ -f "$OUTPUT_MARKUP" ]; then
    cp "$OUTPUT_MARKUP" /tmp/agent_landmarks.mrk.json 2>/dev/null || true
    chmod 644 /tmp/agent_landmarks.mrk.json 2>/dev/null || true
fi

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "markup_exists": $MARKUP_EXISTS,
    "markup_path": "$MARKUP_PATH",
    "markup_created_during_task": $MARKUP_CREATED_DURING_TASK,
    "fiducial_count": $FIDUCIAL_COUNT,
    "fiducial_data": $FIDUCIAL_DATA,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "$SCREENSHOT_PATH",
    "ground_truth_available": $([ -f "/tmp/landmarks_ground_truth.json" ] && echo "true" || echo "false"),
    "sample_id": "$SAMPLE_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/fiducial_task_result.json 2>/dev/null || sudo rm -f /tmp/fiducial_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/fiducial_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/fiducial_task_result.json
chmod 666 /tmp/fiducial_task_result.json 2>/dev/null || sudo chmod 666 /tmp/fiducial_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/fiducial_task_result.json
echo ""
echo "=== Export Complete ==="