#!/bin/bash
echo "=== Exporting Cardiothoracic Ratio Measurement Result ==="

source /workspace/scripts/task_utils.sh

# Get the patient ID used
if [ -f /tmp/lidc_patient_id ]; then
    PATIENT_ID=$(cat /tmp/lidc_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0001"
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
OUTPUT_CARDIAC="$LIDC_DIR/cardiac_diameter.mrk.json"
OUTPUT_THORACIC="$LIDC_DIR/thoracic_diameter.mrk.json"
OUTPUT_REPORT="$LIDC_DIR/ctr_report.json"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/ctr_final.png ga
sleep 1

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    
    # Try to export measurements from Slicer
    cat > /tmp/export_ctr_meas.py << 'PYEOF'
import slicer
import os
import json
import math

output_dir = "/home/ga/Documents/SlicerData/LIDC"
os.makedirs(output_dir, exist_ok=True)

# Look for line markups (ruler measurements)
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
print(f"Found {len(line_nodes)} line/ruler markup(s)")

measurements = []
for node in line_nodes:
    n_points = node.GetNumberOfControlPoints()
    if n_points >= 2:
        p1 = [0.0, 0.0, 0.0]
        p2 = [0.0, 0.0, 0.0]
        node.GetNthControlPointPosition(0, p1)
        node.GetNthControlPointPosition(1, p2)
        length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
        
        name = node.GetName().lower()
        measurement = {
            "name": node.GetName(),
            "type": "line",
            "length_mm": length,
            "p1": p1,
            "p2": p2,
            "z_coord": (p1[2] + p2[2]) / 2
        }
        measurements.append(measurement)
        print(f"  Line '{node.GetName()}': {length:.1f} mm at z={measurement['z_coord']:.1f}")
        
        # Try to save individual markup
        if "cardiac" in name or "heart" in name:
            mrk_path = os.path.join(output_dir, "cardiac_diameter.mrk.json")
            slicer.util.saveNode(node, mrk_path)
        elif "thorac" in name or "chest" in name:
            mrk_path = os.path.join(output_dir, "thoracic_diameter.mrk.json")
            slicer.util.saveNode(node, mrk_path)

# Save all measurements
if measurements:
    meas_path = os.path.join(output_dir, "all_measurements.json")
    with open(meas_path, "w") as f:
        json.dump({"measurements": measurements}, f, indent=2)
    print(f"Exported {len(measurements)} measurements")
else:
    print("No line measurements found in scene")

print("Export complete")
PYEOF

    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --python-script /tmp/export_ctr_meas.py --no-main-window > /tmp/slicer_export.log 2>&1 &
    sleep 10
    pkill -f "export_ctr_meas" 2>/dev/null || true
fi

# Check for measurement files
CARDIAC_EXISTS="false"
CARDIAC_DIAMETER=""
CARDIAC_Z=""

THORACIC_EXISTS="false"
THORACIC_DIAMETER=""
THORACIC_Z=""

# Search for cardiac measurement
CARDIAC_PATHS=(
    "$OUTPUT_CARDIAC"
    "$LIDC_DIR/cardiac.mrk.json"
    "$LIDC_DIR/heart_diameter.mrk.json"
)

for path in "${CARDIAC_PATHS[@]}"; do
    if [ -f "$path" ]; then
        CARDIAC_EXISTS="true"
        echo "Found cardiac measurement at: $path"
        CARDIAC_DIAMETER=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
# Handle Slicer markup format
if 'markups' in data:
    for m in data.get('markups', []):
        for cp in m.get('controlPoints', []):
            pass
        # Calculate from control points
        cps = m.get('controlPoints', [])
        if len(cps) >= 2:
            import math
            p1 = cps[0].get('position', [0,0,0])
            p2 = cps[1].get('position', [0,0,0])
            length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
            print(f'{length:.2f}')
            break
elif 'measurements' in data:
    for m in data.get('measurements', []):
        if m.get('length_mm', 0) > 0:
            print(f\"{m['length_mm']:.2f}\")
            break
" 2>/dev/null || echo "")
        break
    fi
done

# Search for thoracic measurement
THORACIC_PATHS=(
    "$OUTPUT_THORACIC"
    "$LIDC_DIR/thoracic.mrk.json"
    "$LIDC_DIR/chest_diameter.mrk.json"
)

for path in "${THORACIC_PATHS[@]}"; do
    if [ -f "$path" ]; then
        THORACIC_EXISTS="true"
        echo "Found thoracic measurement at: $path"
        THORACIC_DIAMETER=$(python3 -c "
import json
with open('$path') as f:
    data = json.load(f)
if 'markups' in data:
    for m in data.get('markups', []):
        cps = m.get('controlPoints', [])
        if len(cps) >= 2:
            import math
            p1 = cps[0].get('position', [0,0,0])
            p2 = cps[1].get('position', [0,0,0])
            length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
            print(f'{length:.2f}')
            break
elif 'measurements' in data:
    for m in data.get('measurements', []):
        if m.get('length_mm', 0) > 0:
            print(f\"{m['length_mm']:.2f}\")
            break
" 2>/dev/null || echo "")
        break
    fi
done

# If no separate files, check all_measurements.json
if [ "$CARDIAC_EXISTS" = "false" ] || [ "$THORACIC_EXISTS" = "false" ]; then
    if [ -f "$LIDC_DIR/all_measurements.json" ]; then
        echo "Extracting from all_measurements.json..."
        python3 << PYEOF
import json
with open("$LIDC_DIR/all_measurements.json") as f:
    data = json.load(f)

measurements = data.get("measurements", [])
# Sort by length descending
measurements.sort(key=lambda x: x.get("length_mm", 0), reverse=True)

# Assume larger measurement is thoracic, smaller is cardiac
if len(measurements) >= 2:
    thoracic = measurements[0]
    cardiac = measurements[1]
    print(f"THORACIC:{thoracic['length_mm']:.2f}")
    print(f"CARDIAC:{cardiac['length_mm']:.2f}")
    print(f"THORACIC_Z:{thoracic.get('z_coord', 0):.2f}")
    print(f"CARDIAC_Z:{cardiac.get('z_coord', 0):.2f}")
elif len(measurements) == 1:
    print(f"SINGLE:{measurements[0]['length_mm']:.2f}")
PYEOF
        EXTRACTED=$(python3 << PYEOF
import json
with open("$LIDC_DIR/all_measurements.json") as f:
    data = json.load(f)
measurements = data.get("measurements", [])
measurements.sort(key=lambda x: x.get("length_mm", 0), reverse=True)
if len(measurements) >= 2:
    print(f"{measurements[0]['length_mm']:.2f},{measurements[1]['length_mm']:.2f},{measurements[0].get('z_coord',0):.2f},{measurements[1].get('z_coord',0):.2f}")
PYEOF
)
        if [ -n "$EXTRACTED" ]; then
            THORACIC_DIAMETER=$(echo "$EXTRACTED" | cut -d',' -f1)
            CARDIAC_DIAMETER=$(echo "$EXTRACTED" | cut -d',' -f2)
            THORACIC_Z=$(echo "$EXTRACTED" | cut -d',' -f3)
            CARDIAC_Z=$(echo "$EXTRACTED" | cut -d',' -f4)
            CARDIAC_EXISTS="true"
            THORACIC_EXISTS="true"
        fi
    fi
fi

# Check for report file
REPORT_EXISTS="false"
REPORTED_CARDIAC=""
REPORTED_THORACIC=""
REPORTED_CTR=""
REPORTED_CLASSIFICATION=""

REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$LIDC_DIR/report.json"
    "$LIDC_DIR/ctr.json"
)

for path in "${REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        REPORTED_CARDIAC=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('cardiac_diameter_mm', d.get('cardiac_diameter', '')))" 2>/dev/null || echo "")
        REPORTED_THORACIC=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('thoracic_diameter_mm', d.get('thoracic_diameter', '')))" 2>/dev/null || echo "")
        REPORTED_CTR=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('ctr_ratio', d.get('ctr', d.get('CTR', ''))))" 2>/dev/null || echo "")
        REPORTED_CLASSIFICATION=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('classification', ''))" 2>/dev/null || echo "")
        break
    fi
done

# Copy ground truth reference
echo "Copying ground truth reference..."
cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_ctr_reference.json" /tmp/ctr_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/ctr_ground_truth.json 2>/dev/null || true

# Calculate CTR from extracted measurements if not in report
CALCULATED_CTR=""
if [ -n "$CARDIAC_DIAMETER" ] && [ -n "$THORACIC_DIAMETER" ]; then
    CALCULATED_CTR=$(python3 -c "
cardiac = float('$CARDIAC_DIAMETER') if '$CARDIAC_DIAMETER' else 0
thoracic = float('$THORACIC_DIAMETER') if '$THORACIC_DIAMETER' else 0
if thoracic > 0:
    print(f'{cardiac/thoracic:.3f}')
" 2>/dev/null || echo "")
fi

# Check if measurements were at same level
SAME_LEVEL="false"
if [ -n "$CARDIAC_Z" ] && [ -n "$THORACIC_Z" ]; then
    Z_DIFF=$(python3 -c "
cz = float('$CARDIAC_Z') if '$CARDIAC_Z' else 0
tz = float('$THORACIC_Z') if '$THORACIC_Z' else 0
diff = abs(cz - tz)
print(f'{diff:.2f}')
if diff <= 20:
    print('SAME')
" 2>/dev/null)
    if echo "$Z_DIFF" | grep -q "SAME"; then
        SAME_LEVEL="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "cardiac_measurement_exists": $CARDIAC_EXISTS,
    "thoracic_measurement_exists": $THORACIC_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "extracted_cardiac_diameter_mm": "$CARDIAC_DIAMETER",
    "extracted_thoracic_diameter_mm": "$THORACIC_DIAMETER",
    "extracted_cardiac_z": "$CARDIAC_Z",
    "extracted_thoracic_z": "$THORACIC_Z",
    "calculated_ctr": "$CALCULATED_CTR",
    "same_level_measurements": $SAME_LEVEL,
    "reported_cardiac_diameter_mm": "$REPORTED_CARDIAC",
    "reported_thoracic_diameter_mm": "$REPORTED_THORACIC",
    "reported_ctr": "$REPORTED_CTR",
    "reported_classification": "$REPORTED_CLASSIFICATION",
    "screenshot_exists": $([ -f "/tmp/ctr_final.png" ] && echo "true" || echo "false"),
    "ground_truth_available": $([ -f "/tmp/ctr_ground_truth.json" ] && echo "true" || echo "false"),
    "patient_id": "$PATIENT_ID",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/ctr_task_result.json 2>/dev/null || sudo rm -f /tmp/ctr_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/ctr_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/ctr_task_result.json
chmod 666 /tmp/ctr_task_result.json 2>/dev/null || sudo chmod 666 /tmp/ctr_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/ctr_task_result.json
echo ""
echo "=== Export Complete ==="