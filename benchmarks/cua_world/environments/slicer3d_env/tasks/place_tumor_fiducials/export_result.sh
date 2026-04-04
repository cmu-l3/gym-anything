#!/bin/bash
echo "=== Exporting Place Tumor Fiducials Result ==="

source /workspace/scripts/task_utils.sh

# Get sample ID
SAMPLE_ID="BraTS2021_00000"
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MARKUP="$BRATS_DIR/tumor_boundaries.mrk.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/fiducials_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# Look for markup files in multiple locations
MARKUP_FILE=""
MARKUP_PATHS=(
    "$OUTPUT_MARKUP"
    "$BRATS_DIR/tumor_boundaries.json"
    "$BRATS_DIR/tumor_boundary.mrk.json"
    "$BRATS_DIR/$SAMPLE_ID/tumor_boundaries.mrk.json"
    "/home/ga/Documents/SlicerData/tumor_boundaries.mrk.json"
    "/home/ga/tumor_boundaries.mrk.json"
)

for path in "${MARKUP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKUP_FILE="$path"
        echo "Found markup file at: $path"
        break
    fi
done

# Also search for any .mrk.json files created during task
if [ -z "$MARKUP_FILE" ]; then
    echo "Searching for markup files created during task..."
    FOUND_FILES=$(find /home/ga -name "*.mrk.json" -newer /tmp/task_start_time.txt 2>/dev/null | head -5)
    if [ -n "$FOUND_FILES" ]; then
        echo "Found newly created markup files:"
        echo "$FOUND_FILES"
        MARKUP_FILE=$(echo "$FOUND_FILES" | head -1)
    fi
fi

# Initialize result variables
MARKUP_EXISTS="false"
MARKUP_VALID_JSON="false"
MARKUP_SIZE=0
MARKUP_MTIME=0
NUM_POINTS=0
POINT_LABELS=""
POINT_POSITIONS=""
CREATED_DURING_TASK="false"

if [ -n "$MARKUP_FILE" ] && [ -f "$MARKUP_FILE" ]; then
    MARKUP_EXISTS="true"
    MARKUP_SIZE=$(stat -c %s "$MARKUP_FILE" 2>/dev/null || echo "0")
    MARKUP_MTIME=$(stat -c %Y "$MARKUP_FILE" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$MARKUP_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
        echo "Markup file was created during task"
    fi
    
    # Copy markup file to expected location if found elsewhere
    if [ "$MARKUP_FILE" != "$OUTPUT_MARKUP" ]; then
        cp "$MARKUP_FILE" "$OUTPUT_MARKUP" 2>/dev/null || true
        echo "Copied markup file to expected location"
    fi
    
    # Parse markup JSON
    echo "Parsing markup file..."
    python3 << PYEOF
import json
import sys
import os

markup_file = "$MARKUP_FILE"
output_file = "/tmp/parsed_markup.json"

try:
    with open(markup_file, 'r') as f:
        data = json.load(f)
    
    result = {
        "valid_json": True,
        "num_points": 0,
        "point_labels": [],
        "point_positions": [],
        "is_slicer_format": False
    }
    
    # Handle Slicer markup format
    if "markups" in data:
        result["is_slicer_format"] = True
        for markup in data.get("markups", []):
            markup_type = markup.get("type", "")
            control_points = markup.get("controlPoints", [])
            
            for cp in control_points:
                label = cp.get("label", "Unknown")
                position = cp.get("position", [0, 0, 0])
                result["point_labels"].append(label)
                result["point_positions"].append(position)
                result["num_points"] += 1
                print(f"  Point '{label}': {position}")
    
    # Handle simple point list format
    elif "controlPoints" in data:
        for cp in data.get("controlPoints", []):
            label = cp.get("label", "Unknown")
            position = cp.get("position", [0, 0, 0])
            result["point_labels"].append(label)
            result["point_positions"].append(position)
            result["num_points"] += 1
            print(f"  Point '{label}': {position}")
    
    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2)
    
    print(f"Parsed {result['num_points']} points")
    
except json.JSONDecodeError as e:
    result = {"valid_json": False, "error": str(e)}
    with open(output_file, 'w') as f:
        json.dump(result, f)
    print(f"JSON parse error: {e}")
except Exception as e:
    result = {"valid_json": False, "error": str(e)}
    with open(output_file, 'w') as f:
        json.dump(result, f)
    print(f"Error: {e}")
PYEOF

    # Read parsed results
    if [ -f /tmp/parsed_markup.json ]; then
        MARKUP_VALID_JSON=$(python3 -c "import json; print('true' if json.load(open('/tmp/parsed_markup.json')).get('valid_json', False) else 'false')" 2>/dev/null || echo "false")
        NUM_POINTS=$(python3 -c "import json; print(json.load(open('/tmp/parsed_markup.json')).get('num_points', 0))" 2>/dev/null || echo "0")
        POINT_LABELS=$(python3 -c "import json; print(','.join(json.load(open('/tmp/parsed_markup.json')).get('point_labels', [])))" 2>/dev/null || echo "")
    fi
else
    echo "No markup file found"
fi

# Load ground truth reference
GT_REF_FILE="$GROUND_TRUTH_DIR/${SAMPLE_ID}_boundary_ref.json"
HAS_GROUND_TRUTH="false"
if [ -f "$GT_REF_FILE" ]; then
    HAS_GROUND_TRUTH="true"
    echo "Ground truth reference found"
fi

# Compare fiducial positions to ground truth
echo "Comparing fiducial positions to ground truth..."
python3 << PYEOF
import json
import os
import math
import numpy as np

parsed_file = "/tmp/parsed_markup.json"
gt_ref_file = "$GT_REF_FILE"
comparison_file = "/tmp/position_comparison.json"

comparison = {
    "points_near_tumor": 0,
    "superior_is_highest": False,
    "inferior_is_lowest": False,
    "z_spread_mm": 0,
    "y_spread_mm": 0,
    "distances_to_boundary": {}
}

try:
    # Load parsed markup
    if not os.path.exists(parsed_file):
        raise FileNotFoundError("Parsed markup not found")
    
    with open(parsed_file) as f:
        parsed = json.load(f)
    
    if not parsed.get("valid_json", False):
        raise ValueError("Invalid markup JSON")
    
    point_labels = parsed.get("point_labels", [])
    point_positions = parsed.get("point_positions", [])
    
    if len(point_positions) == 0:
        raise ValueError("No points found")
    
    # Load ground truth reference
    if not os.path.exists(gt_ref_file):
        print("Warning: Ground truth reference not found")
        with open(comparison_file, 'w') as f:
            json.dump(comparison, f)
        raise SystemExit(0)
    
    with open(gt_ref_file) as f:
        gt_ref = json.load(f)
    
    gt_boundary = gt_ref.get("boundary_points", {})
    tumor_center = gt_ref.get("tumor_center_ras", [0, 0, 0])
    tumor_extent = gt_ref.get("tumor_extent_mm", {})
    
    # Calculate distances and check positions
    def distance_3d(p1, p2):
        return math.sqrt(sum((a-b)**2 for a, b in zip(p1, p2)))
    
    tolerance_mm = 15.0  # Allow points within 15mm of boundary
    
    for i, (label, pos) in enumerate(zip(point_labels, point_positions)):
        label_lower = label.lower()
        
        # Find corresponding ground truth boundary point
        gt_key = None
        for key in ["superior", "inferior", "anterior", "posterior"]:
            if key in label_lower:
                gt_key = key
                break
        
        if gt_key and gt_key in gt_boundary:
            gt_pos = gt_boundary[gt_key]["ras"]
            dist = distance_3d(pos, gt_pos)
            comparison["distances_to_boundary"][label] = dist
            
            if dist <= tolerance_mm:
                comparison["points_near_tumor"] += 1
                print(f"  {label}: {dist:.1f}mm from boundary (OK)")
            else:
                print(f"  {label}: {dist:.1f}mm from boundary (too far)")
        else:
            # Check distance to tumor center
            dist_to_center = distance_3d(pos, tumor_center)
            max_tumor_radius = max(
                tumor_extent.get("x_lr", 0),
                tumor_extent.get("y_ap", 0),
                tumor_extent.get("z_si", 0)
            ) / 2 + tolerance_mm
            
            if dist_to_center <= max_tumor_radius:
                comparison["points_near_tumor"] += 1
                print(f"  {label}: within tumor region")
            else:
                print(f"  {label}: outside tumor region")
    
    # Check Z ordering (Superior should have highest Z)
    z_coords = {}
    for label, pos in zip(point_labels, point_positions):
        label_lower = label.lower()
        if "superior" in label_lower:
            z_coords["superior"] = pos[2]
        elif "inferior" in label_lower:
            z_coords["inferior"] = pos[2]
    
    if "superior" in z_coords and "inferior" in z_coords:
        comparison["superior_is_highest"] = z_coords["superior"] > z_coords["inferior"]
        comparison["inferior_is_lowest"] = z_coords["inferior"] < z_coords["superior"]
        comparison["z_spread_mm"] = abs(z_coords["superior"] - z_coords["inferior"])
        print(f"  Z spread: {comparison['z_spread_mm']:.1f}mm")
    
    # Check Y spread (Anterior-Posterior)
    y_coords = {}
    for label, pos in zip(point_labels, point_positions):
        label_lower = label.lower()
        if "anterior" in label_lower:
            y_coords["anterior"] = pos[1]
        elif "posterior" in label_lower:
            y_coords["posterior"] = pos[1]
    
    if "anterior" in y_coords and "posterior" in y_coords:
        comparison["y_spread_mm"] = abs(y_coords["anterior"] - y_coords["posterior"])
        print(f"  Y spread: {comparison['y_spread_mm']:.1f}mm")

except Exception as e:
    print(f"Comparison error: {e}")
    comparison["error"] = str(e)

with open(comparison_file, 'w') as f:
    json.dump(comparison, f, indent=2)

print("Comparison complete")
PYEOF

# Read comparison results
POINTS_NEAR_TUMOR=0
SUPERIOR_HIGHEST="false"
INFERIOR_LOWEST="false"
Z_SPREAD_MM=0

if [ -f /tmp/position_comparison.json ]; then
    POINTS_NEAR_TUMOR=$(python3 -c "import json; print(json.load(open('/tmp/position_comparison.json')).get('points_near_tumor', 0))" 2>/dev/null || echo "0")
    SUPERIOR_HIGHEST=$(python3 -c "import json; print('true' if json.load(open('/tmp/position_comparison.json')).get('superior_is_highest', False) else 'false')" 2>/dev/null || echo "false")
    INFERIOR_LOWEST=$(python3 -c "import json; print('true' if json.load(open('/tmp/position_comparison.json')).get('inferior_is_lowest', False) else 'false')" 2>/dev/null || echo "false")
    Z_SPREAD_MM=$(python3 -c "import json; print(json.load(open('/tmp/position_comparison.json')).get('z_spread_mm', 0))" 2>/dev/null || echo "0")
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
    "markup_file_exists": $MARKUP_EXISTS,
    "markup_file_path": "$MARKUP_FILE",
    "markup_valid_json": $MARKUP_VALID_JSON,
    "markup_size_bytes": $MARKUP_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "num_points": $NUM_POINTS,
    "point_labels": "$POINT_LABELS",
    "points_near_tumor": $POINTS_NEAR_TUMOR,
    "superior_is_highest_z": $SUPERIOR_HIGHEST,
    "inferior_is_lowest_z": $INFERIOR_LOWEST,
    "z_spread_mm": $Z_SPREAD_MM,
    "has_ground_truth": $HAS_GROUND_TRUTH,
    "sample_id": "$SAMPLE_ID",
    "screenshot_path": "/tmp/fiducials_final.png"
}
EOF

# Move to final location
rm -f /tmp/fiducials_task_result.json 2>/dev/null || sudo rm -f /tmp/fiducials_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/fiducials_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/fiducials_task_result.json
chmod 666 /tmp/fiducials_task_result.json 2>/dev/null || sudo chmod 666 /tmp/fiducials_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also copy parsed markup and comparison for verifier
cp /tmp/parsed_markup.json /tmp/parsed_markup_copy.json 2>/dev/null || true
cp /tmp/position_comparison.json /tmp/position_comparison_copy.json 2>/dev/null || true
chmod 666 /tmp/parsed_markup_copy.json /tmp/position_comparison_copy.json 2>/dev/null || true

echo ""
echo "Result saved to /tmp/fiducials_task_result.json"
cat /tmp/fiducials_task_result.json
echo ""
echo "=== Export Complete ==="