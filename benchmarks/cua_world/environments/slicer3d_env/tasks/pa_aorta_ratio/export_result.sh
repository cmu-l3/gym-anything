#!/bin/bash
echo "=== Exporting PA:Aorta Ratio Assessment Result ==="

source /workspace/scripts/task_utils.sh

# Get patient ID
if [ -f /tmp/lidc_patient_id.txt ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id.txt)
else
    PATIENT_ID="LIDC-IDRI-0001"
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_PA_MEAS="$LIDC_DIR/pa_measurement.mrk.json"
OUTPUT_AORTA_MEAS="$LIDC_DIR/aorta_measurement.mrk.json"
OUTPUT_REPORT="$LIDC_DIR/pa_aorta_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/pa_aorta_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer
    cat > /tmp/export_pa_aorta_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/LIDC"
os.makedirs(output_dir, exist_ok=True)

# Find all line/ruler markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line markup(s)")

for node in line_nodes:
    name = node.GetName().lower()
    n_points = node.GetNumberOfControlPoints()
    
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        measurement_data = {
            "name": node.GetName(),
            "length_mm": length,
            "point1": p1,
            "point2": p2,
            "type": "line"
        }
        
        # Save based on name
        if "pa" in name or "pulmonary" in name:
            save_path = os.path.join(output_dir, "pa_measurement.mrk.json")
            with open(save_path, "w") as f:
                json.dump(measurement_data, f, indent=2)
            print(f"Saved PA measurement: {length:.1f} mm to {save_path}")
            
        elif "aorta" in name or "ao" in name:
            save_path = os.path.join(output_dir, "aorta_measurement.mrk.json")
            with open(save_path, "w") as f:
                json.dump(measurement_data, f, indent=2)
            print(f"Saved Aorta measurement: {length:.1f} mm to {save_path}")
        else:
            # Save generically
            save_path = os.path.join(output_dir, f"{node.GetName()}.mrk.json")
            with open(save_path, "w") as f:
                json.dump(measurement_data, f, indent=2)
            print(f"Saved measurement '{node.GetName()}': {length:.1f} mm")

# Also try to save markups using Slicer's native format
for node in line_nodes:
    try:
        name = node.GetName().lower()
        if "pa" in name or "pulmonary" in name:
            slicer.util.saveNode(node, os.path.join(output_dir, "pa_measurement_native.mrk.json"))
        elif "aorta" in name or "ao" in name:
            slicer.util.saveNode(node, os.path.join(output_dir, "aorta_measurement_native.mrk.json"))
    except Exception as e:
        print(f"Could not save native markup: {e}")

print("Export complete")
PYEOF
    
    # Run export script
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_pa_aorta_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 8
    pkill -f "export_pa_aorta_meas" 2>/dev/null || true
fi

# ============================================================
# Check for PA measurement
# ============================================================
PA_MEAS_EXISTS="false"
PA_DIAMETER=""
PA_CREATED_DURING_TASK="false"

POSSIBLE_PA_PATHS=(
    "$OUTPUT_PA_MEAS"
    "$LIDC_DIR/PA.mrk.json"
    "$LIDC_DIR/pa.mrk.json"
    "$LIDC_DIR/pulmonary.mrk.json"
    "$LIDC_DIR/MPA.mrk.json"
)

for path in "${POSSIBLE_PA_PATHS[@]}"; do
    if [ -f "$path" ]; then
        PA_MEAS_EXISTS="true"
        echo "Found PA measurement at: $path"
        
        # Check timestamp
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            PA_CREATED_DURING_TASK="true"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_PA_MEAS" ]; then
            cp "$path" "$OUTPUT_PA_MEAS" 2>/dev/null || true
        fi
        
        # Extract diameter
        PA_DIAMETER=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
length = data.get('length_mm', 0)
if length == 0:
    # Try alternative formats
    length = data.get('measurement', {}).get('length', 0)
print(f'{length:.2f}' if length > 0 else '')
" 2>/dev/null || echo "")
        break
    fi
done

# ============================================================
# Check for Aorta measurement
# ============================================================
AORTA_MEAS_EXISTS="false"
AORTA_DIAMETER=""
AORTA_CREATED_DURING_TASK="false"

POSSIBLE_AORTA_PATHS=(
    "$OUTPUT_AORTA_MEAS"
    "$LIDC_DIR/aorta.mrk.json"
    "$LIDC_DIR/Aorta.mrk.json"
    "$LIDC_DIR/ao.mrk.json"
    "$LIDC_DIR/ascending_aorta.mrk.json"
)

for path in "${POSSIBLE_AORTA_PATHS[@]}"; do
    if [ -f "$path" ]; then
        AORTA_MEAS_EXISTS="true"
        echo "Found Aorta measurement at: $path"
        
        # Check timestamp
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            AORTA_CREATED_DURING_TASK="true"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$OUTPUT_AORTA_MEAS" ]; then
            cp "$path" "$OUTPUT_AORTA_MEAS" 2>/dev/null || true
        fi
        
        # Extract diameter
        AORTA_DIAMETER=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
length = data.get('length_mm', 0)
if length == 0:
    length = data.get('measurement', {}).get('length', 0)
print(f'{length:.2f}' if length > 0 else '')
" 2>/dev/null || echo "")
        break
    fi
done

# ============================================================
# Check for report JSON
# ============================================================
REPORT_EXISTS="false"
REPORTED_PA=""
REPORTED_AORTA=""
REPORTED_RATIO=""
REPORTED_ASSESSMENT=""
REPORT_CREATED_DURING_TASK="false"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$LIDC_DIR/report.json"
    "$LIDC_DIR/pa_ao_report.json"
    "/home/ga/Documents/pa_aorta_report.json"
    "/home/ga/pa_aorta_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        
        # Check timestamp
        FILE_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_DURING_TASK="true"
        fi
        
        # Copy to expected location
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Extract report fields
        REPORTED_PA=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
v = d.get('pa_diameter_mm', d.get('pa_diameter', d.get('mpa_diameter_mm', '')))
print(v if v else '')
" 2>/dev/null || echo "")
        
        REPORTED_AORTA=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
v = d.get('aorta_diameter_mm', d.get('aorta_diameter', d.get('ao_diameter_mm', '')))
print(v if v else '')
" 2>/dev/null || echo "")
        
        REPORTED_RATIO=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
v = d.get('pa_aorta_ratio', d.get('ratio', d.get('pa_ao_ratio', '')))
print(v if v else '')
" 2>/dev/null || echo "")
        
        REPORTED_ASSESSMENT=$(python3 -c "
import json
with open('$path') as f:
    d = json.load(f)
v = d.get('assessment', d.get('classification', d.get('finding', '')))
print(v if v else '')
" 2>/dev/null || echo "")
        
        break
    fi
done

# Use report values if measurement values not directly found
if [ -z "$PA_DIAMETER" ] && [ -n "$REPORTED_PA" ]; then
    PA_DIAMETER="$REPORTED_PA"
fi
if [ -z "$AORTA_DIAMETER" ] && [ -n "$REPORTED_AORTA" ]; then
    AORTA_DIAMETER="$REPORTED_AORTA"
fi

# Copy ground truth for verification
cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_pa_aorta_gt.json" /tmp/pa_aorta_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/pa_aorta_ground_truth.json 2>/dev/null || true

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "slicer_was_running": $SLICER_RUNNING,
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "pa_measurement": {
        "exists": $PA_MEAS_EXISTS,
        "created_during_task": $PA_CREATED_DURING_TASK,
        "diameter_mm": "$PA_DIAMETER"
    },
    "aorta_measurement": {
        "exists": $AORTA_MEAS_EXISTS,
        "created_during_task": $AORTA_CREATED_DURING_TASK,
        "diameter_mm": "$AORTA_DIAMETER"
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "created_during_task": $REPORT_CREATED_DURING_TASK,
        "pa_diameter_mm": "$REPORTED_PA",
        "aorta_diameter_mm": "$REPORTED_AORTA",
        "pa_aorta_ratio": "$REPORTED_RATIO",
        "assessment": "$REPORTED_ASSESSMENT"
    },
    "screenshot_exists": $([ -f "/tmp/pa_aorta_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/pa_aorta_ground_truth.json" ] && echo "true" || echo "false"),
    "patient_id": "$PATIENT_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/pa_aorta_task_result.json 2>/dev/null || sudo rm -f /tmp/pa_aorta_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/pa_aorta_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/pa_aorta_task_result.json
chmod 666 /tmp/pa_aorta_task_result.json 2>/dev/null || sudo chmod 666 /tmp/pa_aorta_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/pa_aorta_task_result.json
echo ""
echo "=== Export Complete ==="