#!/bin/bash
echo "=== Exporting Brain Lesion Localization Result ==="

source /workspace/scripts/task_utils.sh

# Get the sample ID used
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
OUTPUT_DIR="$BRATS_DIR/LocalizationReport"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task timing info
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/lesion_localization_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export fiducials from Slicer
    cat > /tmp/export_fiducials.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS/LocalizationReport"
os.makedirs(output_dir, exist_ok=True)

fiducials_data = []

# Get all fiducial nodes
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    print(f"  Node '{node.GetName()}' has {n_points} control points")
    
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        fiducials_data.append({
            "node_name": node.GetName(),
            "label": label,
            "position_ras": {"R": pos[0], "A": pos[1], "S": pos[2]},
            "index": i
        })
        print(f"    Point {i}: {label} at RAS ({pos[0]:.1f}, {pos[1]:.1f}, {pos[2]:.1f})")
    
    # Save the node to a file
    if n_points > 0:
        mrk_path = os.path.join(output_dir, "lesion_centroid.mrk.json")
        slicer.util.saveNode(node, mrk_path)
        print(f"  Saved to {mrk_path}")

# Save all fiducials data
if fiducials_data:
    all_fid_path = os.path.join(output_dir, "all_fiducials.json")
    with open(all_fid_path, 'w') as f:
        json.dump({"fiducials": fiducials_data}, f, indent=2)
    print(f"Exported {len(fiducials_data)} fiducial points to {all_fid_path}")
else:
    print("No fiducial points found in scene")

print("Fiducial export complete")
PYEOF

    # Run the export script in Slicer (briefly)
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_fiducials.py --no-main-window > /tmp/slicer_fid_export.log 2>&1 &
    EXPORT_PID=$!
    sleep 8
    kill $EXPORT_PID 2>/dev/null || true
fi

# Check for agent's output files
echo "Checking for agent output files..."

# Initialize check variables
AXIAL_EXISTS="false"
CORONAL_EXISTS="false"
SAGITTAL_EXISTS="false"
FIDUCIAL_EXISTS="false"
REPORT_EXISTS="false"

AXIAL_PATH=""
CORONAL_PATH=""
SAGITTAL_PATH=""
FIDUCIAL_PATH=""
REPORT_PATH=""

# Search for screenshots in multiple locations
SEARCH_DIRS=(
    "$OUTPUT_DIR"
    "$BRATS_DIR"
    "/home/ga/Documents/SlicerData/Screenshots"
    "/home/ga/Documents"
    "/home/ga"
)

# Look for axial screenshot
for dir in "${SEARCH_DIRS[@]}"; do
    for name in "lesion_axial.png" "axial.png" "Axial.png" "*axial*.png"; do
        found=$(find "$dir" -maxdepth 1 -name "$name" -newer /tmp/task_start_time 2>/dev/null | head -1)
        if [ -n "$found" ] && [ -f "$found" ]; then
            AXIAL_EXISTS="true"
            AXIAL_PATH="$found"
            echo "Found axial screenshot: $AXIAL_PATH"
            break 2
        fi
    done
done

# Look for coronal screenshot
for dir in "${SEARCH_DIRS[@]}"; do
    for name in "lesion_coronal.png" "coronal.png" "Coronal.png" "*coronal*.png"; do
        found=$(find "$dir" -maxdepth 1 -name "$name" -newer /tmp/task_start_time 2>/dev/null | head -1)
        if [ -n "$found" ] && [ -f "$found" ]; then
            CORONAL_EXISTS="true"
            CORONAL_PATH="$found"
            echo "Found coronal screenshot: $CORONAL_PATH"
            break 2
        fi
    done
done

# Look for sagittal screenshot
for dir in "${SEARCH_DIRS[@]}"; do
    for name in "lesion_sagittal.png" "sagittal.png" "Sagittal.png" "*sagittal*.png"; do
        found=$(find "$dir" -maxdepth 1 -name "$name" -newer /tmp/task_start_time 2>/dev/null | head -1)
        if [ -n "$found" ] && [ -f "$found" ]; then
            SAGITTAL_EXISTS="true"
            SAGITTAL_PATH="$found"
            echo "Found sagittal screenshot: $SAGITTAL_PATH"
            break 2
        fi
    done
done

# Look for fiducial markup
for dir in "${SEARCH_DIRS[@]}"; do
    for name in "lesion_centroid.mrk.json" "centroid.mrk.json" "*.mrk.json"; do
        found=$(find "$dir" -maxdepth 1 -name "$name" 2>/dev/null | head -1)
        if [ -n "$found" ] && [ -f "$found" ]; then
            FIDUCIAL_EXISTS="true"
            FIDUCIAL_PATH="$found"
            echo "Found fiducial markup: $FIDUCIAL_PATH"
            break 2
        fi
    done
done

# Look for report JSON
for dir in "${SEARCH_DIRS[@]}"; do
    for name in "localization_report.json" "report.json" "lesion_report.json"; do
        found=$(find "$dir" -maxdepth 1 -name "$name" 2>/dev/null | head -1)
        if [ -n "$found" ] && [ -f "$found" ]; then
            REPORT_EXISTS="true"
            REPORT_PATH="$found"
            echo "Found report: $REPORT_PATH"
            break 2
        fi
    done
done

# Extract fiducial coordinates if found
FIDUCIAL_R=""
FIDUCIAL_A=""
FIDUCIAL_S=""

if [ "$FIDUCIAL_EXISTS" = "true" ] && [ -f "$FIDUCIAL_PATH" ]; then
    # Try to extract coordinates from Slicer markup JSON
    COORDS=$(python3 << PYEOF
import json
import sys

try:
    with open("$FIDUCIAL_PATH") as f:
        data = json.load(f)
    
    # Slicer markup format
    if "markups" in data:
        for markup in data["markups"]:
            if "controlPoints" in markup:
                for cp in markup["controlPoints"]:
                    pos = cp.get("position", [0, 0, 0])
                    print(f"{pos[0]},{pos[1]},{pos[2]}")
                    sys.exit(0)
    
    # Alternative format (from our export)
    if "fiducials" in data:
        for fid in data["fiducials"]:
            pos = fid.get("position_ras", {})
            print(f"{pos.get('R', 0)},{pos.get('A', 0)},{pos.get('S', 0)}")
            sys.exit(0)
            
except Exception as e:
    print(f"0,0,0", file=sys.stderr)
    sys.exit(1)
PYEOF
2>/dev/null || echo "")
    
    if [ -n "$COORDS" ]; then
        FIDUCIAL_R=$(echo "$COORDS" | cut -d',' -f1)
        FIDUCIAL_A=$(echo "$COORDS" | cut -d',' -f2)
        FIDUCIAL_S=$(echo "$COORDS" | cut -d',' -f3)
        echo "Fiducial coordinates: R=$FIDUCIAL_R, A=$FIDUCIAL_A, S=$FIDUCIAL_S"
    fi
fi

# Extract report data if found
REPORTED_LATERALITY=""
REPORTED_MIDLINE=""
REPORTED_R=""
REPORTED_A=""
REPORTED_S=""

if [ "$REPORT_EXISTS" = "true" ] && [ -f "$REPORT_PATH" ]; then
    REPORTED_LATERALITY=$(python3 -c "import json; d=json.load(open('$REPORT_PATH')); print(d.get('laterality', ''))" 2>/dev/null || echo "")
    REPORTED_MIDLINE=$(python3 -c "import json; d=json.load(open('$REPORT_PATH')); print(d.get('midline_distance_mm', ''))" 2>/dev/null || echo "")
    REPORTED_R=$(python3 -c "import json; d=json.load(open('$REPORT_PATH')); c=d.get('lesion_centroid_ras', {}); print(c.get('R', ''))" 2>/dev/null || echo "")
    REPORTED_A=$(python3 -c "import json; d=json.load(open('$REPORT_PATH')); c=d.get('lesion_centroid_ras', {}); print(c.get('A', ''))" 2>/dev/null || echo "")
    REPORTED_S=$(python3 -c "import json; d=json.load(open('$REPORT_PATH')); c=d.get('lesion_centroid_ras', {}); print(c.get('S', ''))" 2>/dev/null || echo "")
    echo "Report: laterality=$REPORTED_LATERALITY, midline=$REPORTED_MIDLINE mm"
fi

# Copy ground truth for verifier
cp "$GROUND_TRUTH_DIR/${SAMPLE_ID}_centroid_gt.json" /tmp/ground_truth_centroid.json 2>/dev/null || true
chmod 644 /tmp/ground_truth_centroid.json 2>/dev/null || true

# Copy agent files for verifier
mkdir -p /tmp/agent_outputs
[ -f "$AXIAL_PATH" ] && cp "$AXIAL_PATH" /tmp/agent_outputs/axial.png 2>/dev/null || true
[ -f "$CORONAL_PATH" ] && cp "$CORONAL_PATH" /tmp/agent_outputs/coronal.png 2>/dev/null || true
[ -f "$SAGITTAL_PATH" ] && cp "$SAGITTAL_PATH" /tmp/agent_outputs/sagittal.png 2>/dev/null || true
[ -f "$FIDUCIAL_PATH" ] && cp "$FIDUCIAL_PATH" /tmp/agent_outputs/fiducial.mrk.json 2>/dev/null || true
[ -f "$REPORT_PATH" ] && cp "$REPORT_PATH" /tmp/agent_outputs/report.json 2>/dev/null || true
chmod -R 755 /tmp/agent_outputs 2>/dev/null || true

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
    "sample_id": "$SAMPLE_ID",
    "axial_screenshot_exists": $AXIAL_EXISTS,
    "axial_screenshot_path": "$AXIAL_PATH",
    "coronal_screenshot_exists": $CORONAL_EXISTS,
    "coronal_screenshot_path": "$CORONAL_PATH",
    "sagittal_screenshot_exists": $SAGITTAL_EXISTS,
    "sagittal_screenshot_path": "$SAGITTAL_PATH",
    "fiducial_exists": $FIDUCIAL_EXISTS,
    "fiducial_path": "$FIDUCIAL_PATH",
    "fiducial_coords": {
        "R": "$FIDUCIAL_R",
        "A": "$FIDUCIAL_A",
        "S": "$FIDUCIAL_S"
    },
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "reported_laterality": "$REPORTED_LATERALITY",
    "reported_midline_mm": "$REPORTED_MIDLINE",
    "reported_coords": {
        "R": "$REPORTED_R",
        "A": "$REPORTED_A",
        "S": "$REPORTED_S"
    },
    "final_screenshot": "/tmp/lesion_localization_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/lesion_localization_result.json 2>/dev/null || sudo rm -f /tmp/lesion_localization_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/lesion_localization_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/lesion_localization_result.json
chmod 666 /tmp/lesion_localization_result.json 2>/dev/null || sudo chmod 666 /tmp/lesion_localization_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/lesion_localization_result.json
echo ""
echo "=== Export Complete ==="