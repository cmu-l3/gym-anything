#!/bin/bash
echo "=== Exporting Tracheal Shape Index Result ==="

source /workspace/scripts/task_utils.sh

# Get patient ID
if [ -f /tmp/trachea_patient_id ]; then
    PATIENT_ID=$(cat /tmp/trachea_patient_id)
else
    PATIENT_ID="LIDC-IDRI-0003"
fi

LIDC_DIR="/home/ga/Documents/SlicerData/LIDC"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"
OUTPUT_MEASUREMENT="$LIDC_DIR/trachea_measurements.mrk.json"
OUTPUT_REPORT="$LIDC_DIR/trachea_report.json"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/trachea_final.png ga
sleep 1

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TASK_DURATION=$((TASK_END - TASK_START))

# Check if Slicer is running
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
fi

# Check for report file
REPORT_EXISTS="false"
REPORT_MODIFIED_AFTER_START="false"
AP_DIAMETER="0"
TRANS_DIAMETER="0"
TRACHEAL_INDEX="0"
CLASSIFICATION=""
SLICE_NUMBER="0"

POSSIBLE_REPORT_PATHS=(
    "$OUTPUT_REPORT"
    "$LIDC_DIR/trachea_report.json"
    "$LIDC_DIR/report.json"
    "/home/ga/Documents/trachea_report.json"
    "/home/ga/trachea_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        echo "Found report at: $path"
        
        # Check if modified after task start
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
            REPORT_MODIFIED_AFTER_START="true"
        fi
        
        # Copy to expected location if needed
        if [ "$path" != "$OUTPUT_REPORT" ]; then
            cp "$path" "$OUTPUT_REPORT" 2>/dev/null || true
        fi
        
        # Parse report fields
        AP_DIAMETER=$(python3 -c "
import json
try:
    d = json.load(open('$path'))
    val = d.get('ap_diameter_mm', d.get('ap_diameter', d.get('AP_diameter', 0)))
    print(float(val))
except:
    print(0)
" 2>/dev/null || echo "0")

        TRANS_DIAMETER=$(python3 -c "
import json
try:
    d = json.load(open('$path'))
    val = d.get('transverse_diameter_mm', d.get('transverse_diameter', d.get('trans_diameter', 0)))
    print(float(val))
except:
    print(0)
" 2>/dev/null || echo "0")

        TRACHEAL_INDEX=$(python3 -c "
import json
try:
    d = json.load(open('$path'))
    val = d.get('tracheal_index', d.get('TI', d.get('ti', 0)))
    print(float(val))
except:
    print(0)
" 2>/dev/null || echo "0")

        CLASSIFICATION=$(python3 -c "
import json
try:
    d = json.load(open('$path'))
    print(d.get('classification', d.get('Classification', '')))
except:
    print('')
" 2>/dev/null || echo "")

        SLICE_NUMBER=$(python3 -c "
import json
try:
    d = json.load(open('$path'))
    val = d.get('slice_number', d.get('measurement_slice', d.get('slice', 0)))
    print(int(val))
except:
    print(0)
" 2>/dev/null || echo "0")

        break
    fi
done

# Check for measurement markup file
MARKUP_EXISTS="false"
MARKUP_MODIFIED_AFTER_START="false"
MEASURED_AP="0"
MEASURED_TRANS="0"

POSSIBLE_MARKUP_PATHS=(
    "$OUTPUT_MEASUREMENT"
    "$LIDC_DIR/trachea_measurements.mrk.json"
    "$LIDC_DIR/measurements.mrk.json"
    "/home/ga/Documents/trachea_measurements.mrk.json"
)

for path in "${POSSIBLE_MARKUP_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MARKUP_EXISTS="true"
        echo "Found markup at: $path"
        
        MARKUP_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$MARKUP_MTIME" -gt "$TASK_START" ]; then
            MARKUP_MODIFIED_AFTER_START="true"
        fi
        
        if [ "$path" != "$OUTPUT_MEASUREMENT" ]; then
            cp "$path" "$OUTPUT_MEASUREMENT" 2>/dev/null || true
        fi
        
        # Try to extract measurements from markup
        MEASURED_VALUES=$(python3 -c "
import json
import math
try:
    d = json.load(open('$path'))
    measurements = d.get('measurements', d.get('markups', []))
    lengths = []
    for m in measurements:
        if 'length_mm' in m:
            lengths.append(m['length_mm'])
        elif 'p1' in m and 'p2' in m:
            p1, p2 = m['p1'], m['p2']
            length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
            lengths.append(length)
    lengths.sort()
    if len(lengths) >= 2:
        print(f'{lengths[-1]:.2f},{lengths[-2]:.2f}')
    elif len(lengths) == 1:
        print(f'{lengths[0]:.2f},0')
    else:
        print('0,0')
except:
    print('0,0')
" 2>/dev/null || echo "0,0")

        MEASURED_AP=$(echo "$MEASURED_VALUES" | cut -d',' -f1)
        MEASURED_TRANS=$(echo "$MEASURED_VALUES" | cut -d',' -f2)
        
        break
    fi
done

# Copy ground truth for verifier
cp "$GROUND_TRUTH_DIR/${PATIENT_ID}_trachea_gt.json" /tmp/trachea_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/trachea_ground_truth.json 2>/dev/null || true

# Check for screenshot created during task
SCREENSHOT_EXISTS="false"
if [ -f /tmp/trachea_final.png ]; then
    SCREENSHOT_EXISTS="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_id": "$PATIENT_ID",
    "slicer_was_running": $SLICER_RUNNING,
    "report_exists": $REPORT_EXISTS,
    "report_modified_after_start": $REPORT_MODIFIED_AFTER_START,
    "markup_exists": $MARKUP_EXISTS,
    "markup_modified_after_start": $MARKUP_MODIFIED_AFTER_START,
    "ap_diameter_mm": $AP_DIAMETER,
    "transverse_diameter_mm": $TRANS_DIAMETER,
    "tracheal_index": $TRACHEAL_INDEX,
    "classification": "$CLASSIFICATION",
    "slice_number": $SLICE_NUMBER,
    "measured_ap_from_markup": $MEASURED_AP,
    "measured_trans_from_markup": $MEASURED_TRANS,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $TASK_DURATION,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/trachea_task_result.json 2>/dev/null || sudo rm -f /tmp/trachea_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/trachea_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/trachea_task_result.json
chmod 666 /tmp/trachea_task_result.json 2>/dev/null || sudo chmod 666 /tmp/trachea_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Export result:"
cat /tmp/trachea_task_result.json
echo ""
echo "=== Export Complete ==="