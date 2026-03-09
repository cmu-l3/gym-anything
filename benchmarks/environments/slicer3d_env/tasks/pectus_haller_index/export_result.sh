#!/bin/bash
echo "=== Exporting Pectus Haller Index Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get the patient ID used
if [ -f /tmp/pectus_patient_id ]; then
    PATIENT_ID=$(cat /tmp/pectus_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0001"
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_TRANSVERSE="$LIDC_DIR/transverse_measurement.mrk.json"
OUTPUT_AP="$LIDC_DIR/ap_measurement.mrk.json"
OUTPUT_REPORT="$LIDC_DIR/haller_index_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get task start time for timestamp verification
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/pectus_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Export any measurements from Slicer before analysis
    cat > /tmp/export_pectus_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/LIDC"
os.makedirs(output_dir, exist_ok=True)

# Find all line/ruler markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup(s)")

all_measurements = []

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        
        # Calculate length in mm
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        # Determine measurement type by name or orientation
        name = node.GetName().lower()
        is_transverse = any(kw in name for kw in ['trans', 'width', 'horizontal', 'side'])
        is_ap = any(kw in name for kw in ['ap', 'anterior', 'depth', 'vertical'])
        
        # If no clear name, guess by orientation
        if not is_transverse and not is_ap:
            dx = abs(p2[0] - p1[0])
            dy = abs(p2[1] - p1[1])
            if dx > dy * 1.5:
                is_transverse = True
            elif dy > dx * 1.5:
                is_ap = True
        
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
            "is_transverse": is_transverse,
            "is_ap": is_ap,
            "slice_position": (p1[2] + p2[2]) / 2  # Average z position
        }
        all_measurements.append(measurement)
        print(f"  '{node.GetName()}': {length:.1f} mm (trans={is_transverse}, ap={is_ap})")
        
        # Save individual markup files
        mrk_filename = node.GetName().replace(' ', '_') + ".mrk.json"
        mrk_path = os.path.join(output_dir, mrk_filename)
        slicer.util.saveNode(node, mrk_path)

# Also check for any fiducial points that might indicate measurement locations
fid_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
for node in fid_nodes:
    for i in range(node.GetNumberOfControlPoints()):
        pos = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(i, pos)
        all_measurements.append({
            "name": node.GetNthControlPointLabel(i),
            "type": "fiducial",
            "position": pos
        })

# Save all measurements
if all_measurements:
    meas_path = os.path.join(output_dir, "all_measurements.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": all_measurements}, f, indent=2)
    print(f"Saved {len(all_measurements)} measurements to {meas_path}")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_pectus_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_pectus_meas" 2>/dev/null || true
fi

# Check for measurement files
TRANSVERSE_EXISTS="false"
TRANSVERSE_MM=""
AP_EXISTS="false"
AP_MM=""

# Search for transverse measurement
POSSIBLE_TRANS_PATHS=(
    "$OUTPUT_TRANSVERSE"
    "$LIDC_DIR/transverse.mrk.json"
    "$LIDC_DIR/Transverse.mrk.json"
    "$LIDC_DIR/width_measurement.mrk.json"
)

for path in "${POSSIBLE_TRANS_PATHS[@]}"; do
    if [ -f "$path" ]; then
        TRANSVERSE_EXISTS="true"
        echo "Found transverse measurement at: $path"
        if [ "$path" != "$OUTPUT_TRANSVERSE" ]; then
            cp "$path" "$OUTPUT_TRANSVERSE" 2>/dev/null || true
        fi
        break
    fi
done

# Search for AP measurement
POSSIBLE_AP_PATHS=(
    "$OUTPUT_AP"
    "$LIDC_DIR/ap.mrk.json"
    "$LIDC_DIR/AP.mrk.json"
    "$LIDC_DIR/ap_measurement.mrk.json"
    "$LIDC_DIR/depth_measurement.mrk.json"
)

for path in "${POSSIBLE_AP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        AP_EXISTS="true"
        echo "Found AP measurement at: $path"
        if [ "$path" != "$OUTPUT_AP" ]; then
            cp "$path" "$OUTPUT_AP" 2>/dev/null || true
        fi
        break
    fi
done

# Try to extract measurements from all_measurements.json
if [ -f "$LIDC_DIR/all_measurements.json" ]; then
    echo "Extracting measurements from all_measurements.json..."
    python3 << 'PYEOF'
import json
import os

lidc_dir = "/home/ga/Documents/SlicerData/LIDC"
all_meas_path = os.path.join(lidc_dir, "all_measurements.json")

with open(all_meas_path) as f:
    data = json.load(f)

measurements = data.get("measurements", [])

transverse_meas = None
ap_meas = None

for m in measurements:
    if m.get("type") != "line":
        continue
    
    if m.get("is_transverse") and (transverse_meas is None or m["length_mm"] > transverse_meas["length_mm"]):
        transverse_meas = m
    elif m.get("is_ap") and (ap_meas is None or m["length_mm"] < ap_meas.get("length_mm", float('inf'))):
        ap_meas = m

# If not explicitly labeled, use heuristics: larger measurement is transverse
if transverse_meas is None and ap_meas is None:
    line_meas = [m for m in measurements if m.get("type") == "line"]
    if len(line_meas) >= 2:
        line_meas.sort(key=lambda x: x["length_mm"], reverse=True)
        transverse_meas = line_meas[0]
        ap_meas = line_meas[1]
    elif len(line_meas) == 1:
        # Only one measurement - check if it's more transverse or AP
        m = line_meas[0]
        if m["length_mm"] > 150:  # Likely transverse
            transverse_meas = m
        else:
            ap_meas = m

# Save extracted values
result = {}
if transverse_meas:
    result["transverse_mm"] = transverse_meas["length_mm"]
    result["transverse_slice"] = transverse_meas.get("slice_position", 0)
if ap_meas:
    result["ap_mm"] = ap_meas["length_mm"]
    result["ap_slice"] = ap_meas.get("slice_position", 0)

with open("/tmp/extracted_measurements.json", "w") as f:
    json.dump(result, f)

print(f"Extracted: transverse={result.get('transverse_mm', 'N/A')}, ap={result.get('ap_mm', 'N/A')}")
PYEOF
fi

# Read extracted measurements
if [ -f "/tmp/extracted_measurements.json" ]; then
    TRANSVERSE_MM=$(python3 -c "import json; print(json.load(open('/tmp/extracted_measurements.json')).get('transverse_mm', ''))" 2>/dev/null || echo "")
    AP_MM=$(python3 -c "import json; print(json.load(open('/tmp/extracted_measurements.json')).get('ap_mm', ''))" 2>/dev/null || echo "")
    
    if [ -n "$TRANSVERSE_MM" ]; then
        TRANSVERSE_EXISTS="true"
    fi
    if [ -n "$AP_MM" ]; then
        AP_EXISTS="true"
    fi
fi

# Check for report file
REPORT_EXISTS="false"
REPORTED_HI=""
REPORTED_TRANS=""
REPORTED_AP=""
REPORTED_CLASS=""
REPORTED_SURGICAL=""

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$LIDC_DIR/haller_report.json"
    "$LIDC_DIR/report.json"
    "/home/ga/Documents/haller_index_report.json"
    "/home/ga/haller_index_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_TRANS=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('transverse_diameter_mm', d.get('transverse_mm', '')))" 2>/dev/null || echo "")
        REPORTED_AP=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('ap_diameter_mm', d.get('ap_mm', '')))" 2>/dev/null || echo "")
        REPORTED_HI=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('haller_index', d.get('hi', '')))" 2>/dev/null || echo "")
        REPORTED_CLASS=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('severity_classification', d.get('classification', '')))" 2>/dev/null || echo "")
        REPORTED_SURGICAL=$(python3 -c "import json; d=json.load(open('$path')); print(str(d.get('surgical_candidate', '')).lower())" 2>/dev/null || echo "")
        break
    fi
done

# Use reported values if measurement files weren't found but report exists
if [ -z "$TRANSVERSE_MM" ] && [ -n "$REPORTED_TRANS" ]; then
    TRANSVERSE_MM="$REPORTED_TRANS"
    TRANSVERSE_EXISTS="true"
fi
if [ -z "$AP_MM" ] && [ -n "$REPORTED_AP" ]; then
    AP_MM="$REPORTED_AP"
    AP_EXISTS="true"
fi

# Check file timestamps for anti-gaming
TRANS_CREATED_DURING="false"
AP_CREATED_DURING="false"
REPORT_CREATED_DURING="false"

if [ -f "$OUTPUT_TRANSVERSE" ]; then
    MTIME=$(stat -c %Y "$OUTPUT_TRANSVERSE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        TRANS_CREATED_DURING="true"
    fi
fi

if [ -f "$OUTPUT_AP" ]; then
    MTIME=$(stat -c %Y "$OUTPUT_AP" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        AP_CREATED_DURING="true"
    fi
fi

if [ -f "$OUTPUT_REPORT" ]; then
    MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
fi

# Copy ground truth for verification
echo "Copying ground truth for verification..."
cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_haller_gt.json" /tmp/haller_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/haller_ground_truth.json 2>/dev/null || true

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "patient_id": "$PATIENT_ID",
    "task_start_time": $TASK_START,
    "transverse_measurement_exists": $TRANSVERSE_EXISTS,
    "transverse_mm": "$TRANSVERSE_MM",
    "transverse_created_during_task": $TRANS_CREATED_DURING,
    "ap_measurement_exists": $AP_EXISTS,
    "ap_mm": "$AP_MM",
    "ap_created_during_task": $AP_CREATED_DURING,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING,
    "reported_transverse_mm": "$REPORTED_TRANS",
    "reported_ap_mm": "$REPORTED_AP",
    "reported_haller_index": "$REPORTED_HI",
    "reported_classification": "$REPORTED_CLASS",
    "reported_surgical_candidate": "$REPORTED_SURGICAL",
    "screenshot_exists": $([ -f "/tmp/pectus_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/haller_ground_truth.json" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/pectus_task_result.json 2>/dev/null || sudo rm -f /tmp/pectus_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/pectus_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/pectus_task_result.json
chmod 666 /tmp/pectus_task_result.json 2>/dev/null || sudo chmod 666 /tmp/pectus_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/pectus_task_result.json
echo ""
echo "=== Export Complete ==="