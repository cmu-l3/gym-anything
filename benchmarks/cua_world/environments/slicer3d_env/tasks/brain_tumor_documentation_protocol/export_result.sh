#!/bin/bash
echo "=== Exporting Brain Tumor Documentation Result ==="

source /workspace/scripts/task_utils.sh

# Get sample ID
if [ -f /tmp/brats_sample_id ]; then
    SAMPLE_ID=$(cat /tmp/brats_sample_id)
else
    SAMPLE_ID="BraTS2021_00000"
fi

BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"
DOC_DIR="$BRATS_DIR/Documentation"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/doc_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer
    cat > /tmp/export_doc_measurements.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/BraTS/Documentation"
os.makedirs(output_dir, exist_ok=True)

measurements = []

# Get line/ruler markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup(s)")

for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        measurements.append({
            "name": node.GetName(),
            "type": "line",
            "length_mm": round(length, 2),
            "p1": [round(x, 2) for x in p1],
            "p2": [round(x, 2) for x in p2],
        })
        print(f"  Line '{node.GetName()}': {length:.2f} mm")

# Save measurements
if measurements:
    meas_path = os.path.join(output_dir, "measurements.mrk.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": measurements}, f, indent=2)
    print(f"Saved {len(measurements)} measurements to {meas_path}")
    
    # Also export each node as native Slicer format
    for node in line_nodes:
        node_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
        slicer.util.saveNode(node, node_path)
else:
    print("No line measurements found")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_doc_measurements.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_doc_measurements" 2>/dev/null || true
fi

# Initialize result variables
AXIAL_EXISTS="false"
AXIAL_SIZE=0
AXIAL_MTIME=0

SAGITTAL_EXISTS="false"
SAGITTAL_SIZE=0
SAGITTAL_MTIME=0

CORONAL_EXISTS="false"
CORONAL_SIZE=0
CORONAL_MTIME=0

MEASUREMENTS_EXISTS="false"
MEASUREMENTS_COUNT=0
MAX_DIAMETER_MM=""
PERP_DIAMETER_MM=""

REPORT_EXISTS="false"
REPORT_VALID="false"
REPORTED_MAX_DIAM=""
REPORTED_PERP_DIAM=""
REPORTED_PRODUCT=""
REPORTED_LOCATION=""

# Check for screenshots (try multiple naming conventions)
echo "Checking for screenshots..."

# Axial screenshot
for name in "axial_view.png" "axial.png" "Axial.png" "axial_screenshot.png"; do
    path="$DOC_DIR/$name"
    if [ -f "$path" ]; then
        AXIAL_EXISTS="true"
        AXIAL_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        AXIAL_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "  Found axial: $name ($AXIAL_SIZE bytes)"
        # Copy to expected name if different
        [ "$name" != "axial_view.png" ] && cp "$path" "$DOC_DIR/axial_view.png" 2>/dev/null
        break
    fi
done

# Sagittal screenshot
for name in "sagittal_view.png" "sagittal.png" "Sagittal.png" "sagittal_screenshot.png"; do
    path="$DOC_DIR/$name"
    if [ -f "$path" ]; then
        SAGITTAL_EXISTS="true"
        SAGITTAL_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        SAGITTAL_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "  Found sagittal: $name ($SAGITTAL_SIZE bytes)"
        [ "$name" != "sagittal_view.png" ] && cp "$path" "$DOC_DIR/sagittal_view.png" 2>/dev/null
        break
    fi
done

# Coronal screenshot
for name in "coronal_view.png" "coronal.png" "Coronal.png" "coronal_screenshot.png"; do
    path="$DOC_DIR/$name"
    if [ -f "$path" ]; then
        CORONAL_EXISTS="true"
        CORONAL_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        CORONAL_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        echo "  Found coronal: $name ($CORONAL_SIZE bytes)"
        [ "$name" != "coronal_view.png" ] && cp "$path" "$DOC_DIR/coronal_view.png" 2>/dev/null
        break
    fi
done

# Also check for any PNG files created during task
echo "Looking for any screenshots created during task..."
SCREENSHOT_COUNT=$(find "$DOC_DIR" -name "*.png" -newer /tmp/task_start_time_iso.txt 2>/dev/null | wc -l)
echo "  Found $SCREENSHOT_COUNT PNG files created during task"

# Check for measurements file
echo "Checking for measurements..."
MEAS_PATH="$DOC_DIR/measurements.mrk.json"
if [ -f "$MEAS_PATH" ]; then
    MEASUREMENTS_EXISTS="true"
    # Parse measurement data
    MEAS_DATA=$(python3 << PYEOF
import json
try:
    with open("$MEAS_PATH") as f:
        data = json.load(f)
    measurements = data.get("measurements", [])
    lengths = [m.get("length_mm", 0) for m in measurements if m.get("type") == "line"]
    if lengths:
        lengths_sorted = sorted(lengths, reverse=True)
        max_d = lengths_sorted[0] if len(lengths_sorted) > 0 else 0
        perp_d = lengths_sorted[1] if len(lengths_sorted) > 1 else 0
        print(f"{len(lengths)}|{max_d:.2f}|{perp_d:.2f}")
    else:
        print("0|0|0")
except Exception as e:
    print(f"0|0|0")
PYEOF
)
    MEASUREMENTS_COUNT=$(echo "$MEAS_DATA" | cut -d'|' -f1)
    MAX_DIAMETER_MM=$(echo "$MEAS_DATA" | cut -d'|' -f2)
    PERP_DIAMETER_MM=$(echo "$MEAS_DATA" | cut -d'|' -f3)
    echo "  Found $MEASUREMENTS_COUNT measurements"
    echo "  Max diameter: $MAX_DIAMETER_MM mm"
    echo "  Perpendicular: $PERP_DIAMETER_MM mm"
fi

# Check for documentation report
echo "Checking for documentation report..."
REPORT_PATH="$DOC_DIR/documentation_report.json"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Parse report
    REPORT_DATA=$(python3 << PYEOF
import json
try:
    with open("$REPORT_PATH") as f:
        data = json.load(f)
    required_fields = ["patient_id", "finding", "max_axial_diameter_mm", 
                       "perpendicular_diameter_mm", "bidimensional_product_mm2",
                       "tumor_location", "screenshot_count", "documentation_complete"]
    present = sum(1 for f in required_fields if f in data)
    max_d = data.get("max_axial_diameter_mm", 0)
    perp_d = data.get("perpendicular_diameter_mm", 0)
    product = data.get("bidimensional_product_mm2", 0)
    location = data.get("tumor_location", "")
    valid = present >= 6  # Allow some fields missing
    print(f"{'true' if valid else 'false'}|{max_d}|{perp_d}|{product}|{location}")
except Exception as e:
    print(f"false|0|0|0|")
PYEOF
)
    REPORT_VALID=$(echo "$REPORT_DATA" | cut -d'|' -f1)
    REPORTED_MAX_DIAM=$(echo "$REPORT_DATA" | cut -d'|' -f2)
    REPORTED_PERP_DIAM=$(echo "$REPORT_DATA" | cut -d'|' -f3)
    REPORTED_PRODUCT=$(echo "$REPORT_DATA" | cut -d'|' -f4)
    REPORTED_LOCATION=$(echo "$REPORT_DATA" | cut -d'|' -f5)
    echo "  Report valid: $REPORT_VALID"
    echo "  Reported max diameter: $REPORTED_MAX_DIAM mm"
    echo "  Reported location: $REPORTED_LOCATION"
fi

# Check timestamp validity for anti-gaming
AXIAL_CREATED_DURING_TASK="false"
SAGITTAL_CREATED_DURING_TASK="false"
CORONAL_CREATED_DURING_TASK="false"

if [ "$AXIAL_EXISTS" = "true" ] && [ "$AXIAL_MTIME" -gt "$TASK_START" ]; then
    AXIAL_CREATED_DURING_TASK="true"
fi
if [ "$SAGITTAL_EXISTS" = "true" ] && [ "$SAGITTAL_MTIME" -gt "$TASK_START" ]; then
    SAGITTAL_CREATED_DURING_TASK="true"
fi
if [ "$CORONAL_EXISTS" = "true" ] && [ "$CORONAL_MTIME" -gt "$TASK_START" ]; then
    CORONAL_CREATED_DURING_TASK="true"
fi

# Copy ground truth for verifier
cp /tmp/documentation_ground_truth.json /tmp/doc_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/doc_ground_truth.json 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "sample_id": "$SAMPLE_ID",
    "screenshots": {
        "axial_exists": $AXIAL_EXISTS,
        "axial_size_bytes": $AXIAL_SIZE,
        "axial_created_during_task": $AXIAL_CREATED_DURING_TASK,
        "sagittal_exists": $SAGITTAL_EXISTS,
        "sagittal_size_bytes": $SAGITTAL_SIZE,
        "sagittal_created_during_task": $SAGITTAL_CREATED_DURING_TASK,
        "coronal_exists": $CORONAL_EXISTS,
        "coronal_size_bytes": $CORONAL_SIZE,
        "coronal_created_during_task": $CORONAL_CREATED_DURING_TASK,
        "total_screenshots_during_task": $SCREENSHOT_COUNT
    },
    "measurements": {
        "file_exists": $MEASUREMENTS_EXISTS,
        "count": $MEASUREMENTS_COUNT,
        "max_diameter_mm": "$MAX_DIAMETER_MM",
        "perpendicular_diameter_mm": "$PERP_DIAMETER_MM"
    },
    "report": {
        "file_exists": $REPORT_EXISTS,
        "valid_format": $REPORT_VALID,
        "max_diameter_mm": "$REPORTED_MAX_DIAM",
        "perpendicular_diameter_mm": "$REPORTED_PERP_DIAM",
        "bidimensional_product_mm2": "$REPORTED_PRODUCT",
        "tumor_location": "$REPORTED_LOCATION"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/doc_task_result.json 2>/dev/null || sudo rm -f /tmp/doc_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/doc_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/doc_task_result.json
chmod 666 /tmp/doc_task_result.json 2>/dev/null || sudo chmod 666 /tmp/doc_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/doc_task_result.json
echo ""
echo "=== Export Complete ==="