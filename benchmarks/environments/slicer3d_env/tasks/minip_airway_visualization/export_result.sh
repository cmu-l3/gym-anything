#!/bin/bash
echo "=== Exporting MinIP Airway Visualization Result ==="

source /workspace/scripts/task_utils.sh

# Get patient ID
PATIENT_ID="LIDC-IDRI-0001"
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_SCREENSHOT="$LIDC_DIR/minip_airway_visualization.png"
OUTPUT_LANDMARKS="$LIDC_DIR/airway_landmarks.mrk.json"
OUTPUT_MEASUREMENTS="$LIDC_DIR/airway_measurements.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/minip_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export any markups from Slicer
    cat > /tmp/export_airway_data.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/LIDC"
os.makedirs(output_dir, exist_ok=True)

all_landmarks = []
all_measurements = []

# Export fiducial landmarks
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
print(f"Found {len(fid_nodes)} fiducial node(s)")

for node in fid_nodes:
    n_points = node.GetNumberOfControlPoints()
    for i in range(n_points):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        label = node.GetNthControlPointLabel(i)
        all_landmarks.append({
            "name": label,
            "position_mm": pos,
            "node_name": node.GetName()
        })
        print(f"  Landmark: {label} at {pos}")

# Export line measurements
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line/ruler markup(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        all_measurements.append({
            "name": node.GetName(),
            "length_mm": length,
            "p1": p1,
            "p2": p2
        })
        print(f"  Measurement '{node.GetName()}': {length:.1f} mm")

# Save landmarks
if all_landmarks:
    landmarks_path = os.path.join(output_dir, "airway_landmarks.mrk.json")
    with open(landmarks_path, "w") as f:
        json.dump({"landmarks": all_landmarks}, f, indent=2)
    print(f"Saved {len(all_landmarks)} landmarks")

# Save measurements
if all_measurements:
    # Try to map measurements to airway structures by name or position
    measurements_out = {}
    
    for m in all_measurements:
        name_lower = m["name"].lower()
        length = m["length_mm"]
        
        if "trach" in name_lower:
            measurements_out["trachea_diameter_mm"] = length
        elif "right" in name_lower or "rb" in name_lower:
            measurements_out["right_bronchus_diameter_mm"] = length
        elif "left" in name_lower or "lb" in name_lower:
            measurements_out["left_bronchus_diameter_mm"] = length
        else:
            # Store with original name
            measurements_out[m["name"]] = length
    
    # If we couldn't match names, use positional heuristics
    if len(measurements_out) < 3 and len(all_measurements) >= 3:
        sorted_meas = sorted(all_measurements, key=lambda x: x["length_mm"], reverse=True)
        if "trachea_diameter_mm" not in measurements_out:
            measurements_out["trachea_diameter_mm"] = sorted_meas[0]["length_mm"]
        if "right_bronchus_diameter_mm" not in measurements_out and len(sorted_meas) > 1:
            measurements_out["right_bronchus_diameter_mm"] = sorted_meas[1]["length_mm"]
        if "left_bronchus_diameter_mm" not in measurements_out and len(sorted_meas) > 2:
            measurements_out["left_bronchus_diameter_mm"] = sorted_meas[2]["length_mm"]
    
    measurements_out["all_measurements"] = all_measurements
    
    meas_path = os.path.join(output_dir, "airway_measurements.json")
    with open(meas_path, "w") as f:
        json.dump(measurements_out, f, indent=2)
    print(f"Saved measurements to {meas_path}")

# Capture screenshot if not done by agent
screenshot_path = os.path.join(output_dir, "minip_airway_visualization.png")
if not os.path.exists(screenshot_path):
    # Try to capture current 3D view
    try:
        layoutManager = slicer.app.layoutManager()
        view = layoutManager.threeDWidget(0).threeDView() if layoutManager.threeDWidgetCount > 0 else None
        if view:
            renderWindow = view.renderWindow()
            wti = vtk.vtkWindowToImageFilter()
            wti.SetInput(renderWindow)
            wti.Update()
            writer = vtk.vtkPNGWriter()
            writer.SetFileName(screenshot_path)
            writer.SetInputConnection(wti.GetOutputPort())
            writer.Write()
            print(f"Captured 3D view to {screenshot_path}")
    except Exception as e:
        print(f"Could not capture screenshot: {e}")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_airway_data.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_airway_data" 2>/dev/null || true
fi

# Check for output files
SCREENSHOT_EXISTS="false"
SCREENSHOT_PATH=""
SCREENSHOT_SIZE=0

POSSIBLE_SCREENSHOT_PATHS=(
    "$OUTPUT_SCREENSHOT"
    "$LIDC_DIR/screenshot.png"
    "$LIDC_DIR/minip.png"
    "$LIDC_DIR/airway.png"
    "/home/ga/Documents/minip_airway_visualization.png"
)

for path in "${POSSIBLE_SCREENSHOT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SCREENSHOT_EXISTS="true"
        SCREENSHOT_PATH="$path"
        SCREENSHOT_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SCREENSHOT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "Found screenshot at: $path ($SCREENSHOT_SIZE bytes)"
        if [ "$path" != "$OUTPUT_SCREENSHOT" ]; then
            cp "$path" "$OUTPUT_SCREENSHOT" 2>/dev/null || true
        fi
        break
    fi
done

# Check if screenshot was created during task
SCREENSHOT_CREATED_DURING_TASK="false"
if [ "$SCREENSHOT_EXISTS" = "true" ] && [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
    SCREENSHOT_CREATED_DURING_TASK="true"
fi

# Check for landmarks file
LANDMARKS_EXISTS="false"
LANDMARKS_COUNT=0

POSSIBLE_LANDMARK_PATHS=(
    "$OUTPUT_LANDMARKS"
    "$LIDC_DIR/landmarks.mrk.json"
    "$LIDC_DIR/airway_fiducials.mrk.json"
)

for path in "${POSSIBLE_LANDMARK_PATHS[@]}"; do
    if [ -f "$path" ]; then
        LANDMARKS_EXISTS="true"
        echo "Found landmarks at: $path"
        LANDMARKS_COUNT=$(python3 -c "import json; d=json.load(open('$path')); print(len(d.get('landmarks', [])))" 2>/dev/null || echo "0")
        if [ "$path" != "$OUTPUT_LANDMARKS" ]; then
            cp "$path" "$OUTPUT_LANDMARKS" 2>/dev/null || true
        fi
        break
    fi
done

# Check for measurements file
MEASUREMENTS_EXISTS="false"
TRACHEA_DIAM=""
RIGHT_BRONCHUS_DIAM=""
LEFT_BRONCHUS_DIAM=""

POSSIBLE_MEAS_PATHS=(
    "$OUTPUT_MEASUREMENTS"
    "$LIDC_DIR/measurements.json"
)

for path in "${POSSIBLE_MEAS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MEASUREMENTS_EXISTS="true"
        echo "Found measurements at: $path"
        TRACHEA_DIAM=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('trachea_diameter_mm', ''))" 2>/dev/null || echo "")
        RIGHT_BRONCHUS_DIAM=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('right_bronchus_diameter_mm', ''))" 2>/dev/null || echo "")
        LEFT_BRONCHUS_DIAM=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('left_bronchus_diameter_mm', ''))" 2>/dev/null || echo "")
        if [ "$path" != "$OUTPUT_MEASUREMENTS" ]; then
            cp "$path" "$OUTPUT_MEASUREMENTS" 2>/dev/null || true
        fi
        break
    fi
done

# Copy ground truth for verifier
if [ -f "$GROUND_TRUTH_DIR/${PATIENT_ID}_airway_gt.json" ]; then
    cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_airway_gt.json" /tmp/airway_ground_truth.json 2>/dev/null || true
    chmod 644 /tmp/airway_ground_truth.json 2>/dev/null || true
fi

# Copy output files for verifier
[ -f "$OUTPUT_SCREENSHOT" ] && cp "$OUTPUT_SCREENSHOT" /tmp/agent_screenshot.png 2>/dev/null || true
[ -f "$OUTPUT_LANDMARKS" ] && cp "$OUTPUT_LANDMARKS" /tmp/agent_landmarks.json 2>/dev/null || true
[ -f "$OUTPUT_MEASUREMENTS" ] && cp "$OUTPUT_MEASUREMENTS" /tmp/agent_measurements.json 2>/dev/null || true

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "patient_id": "$PATIENT_ID",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "$SCREENSHOT_PATH",
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "landmarks_exists": $LANDMARKS_EXISTS,
    "landmarks_count": $LANDMARKS_COUNT,
    "measurements_exists": $MEASUREMENTS_EXISTS,
    "trachea_diameter_mm": "$TRACHEA_DIAM",
    "right_bronchus_diameter_mm": "$RIGHT_BRONCHUS_DIAM",
    "left_bronchus_diameter_mm": "$LEFT_BRONCHUS_DIAM",
    "ground_truth_available": $([ -f "/tmp/airway_ground_truth.json" ] && echo "true" || echo "false"),
    "final_screenshot": "/tmp/minip_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/minip_task_result.json 2>/dev/null || sudo rm -f /tmp/minip_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/minip_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/minip_task_result.json
chmod 666 /tmp/minip_task_result.json 2>/dev/null || sudo chmod 666 /tmp/minip_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/minip_task_result.json
echo ""
echo "=== Export Complete ==="